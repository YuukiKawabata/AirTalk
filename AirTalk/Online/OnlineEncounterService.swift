import CoreBluetooth
import CryptoKit
import UIKit

struct OnlineEncounterOffer: Codable {
  let token: String
  let challenge: String
}
struct OnlineEncounterReceipt: Codable, Equatable {
  let tokenA: String
  let tokenB: String
  let challengeA: String
  let challengeB: String
  let signatureA: String
  var signatureB: String
  var payload: Data {
    Data(
      ["airtalk-encounter-v1", tokenA, tokenB, challengeA, challengeB].joined(separator: "\n").utf8)
  }
}
private struct QueuedEncounter: Codable, Equatable {
  let receipt: OnlineEncounterReceipt
  let expires: Date
}

/// Opt-in, bounded BLE proof exchange. It cannot prove physical distance or defeat a relay.
/// Messages and profiles never enter this service. Real-device feasibility is a release gate.
@MainActor
final class OnlineEncounterService: NSObject, @preconcurrency CBCentralManagerDelegate,
  @preconcurrency CBPeripheralManagerDelegate, @preconcurrency CBPeripheralDelegate
{
  static let service = CBUUID(string: "50277558-B84D-48A1-A59B-9BCE42E3F024")
  static let offerID = CBUUID(string: "50277558-B84D-48A1-A59B-9BCE42E3F025")
  static let writeID = CBUUID(string: "50277558-B84D-48A1-A59B-9BCE42E3F026")
  static let receiptID = CBUUID(string: "50277558-B84D-48A1-A59B-9BCE42E3F027")
  private var central: CBCentralManager?
  private var peripheral: CBPeripheralManager?
  private var token: OnlineEncounterToken?
  private var offer: OnlineEncounterOffer?
  private var enabled = false
  private var ready = false
  private var adding = false
  private var resetServices = false
  private var key: P256.Signing.PrivateKey?
  private var peers: [UUID: CBPeripheral] = [:]
  private var cooldown: [UUID: Date] = [:]
  private var phases: [UUID: Int] = [:]
  private var outgoing: [UUID: Data] = [:]
  private var sent: [UUID: Int] = [:]
  private var remoteOffers: [UUID: OnlineEncounterOffer] = [:]
  private var input: [UUID: Data] = [:]
  private var replies: [UUID: Data] = [:]
  private var remoteExpiry: [UUID: Date] = [:]
  private var queue: [QueuedEncounter] = []
  private let onReceipt: (OnlineEncounterReceipt) -> Void
  private let prefix: String
  var needsFreshToken: Bool {
    guard let token else { return true }
    return token.expiresAt - 86_400_000 < Date().timeIntervalSince1970 * 1000 - 900_000
  }
  var pending: [OnlineEncounterReceipt] {
    prune()
    return queue.map(\.receipt)
  }

  init(scope: String = "pilot", onReceipt: @escaping (OnlineEncounterReceipt) -> Void) {
    self.onReceipt = onReceipt
    prefix =
      "ble." + SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    super.init()
    if let data = OnlineVault.read(prefix + ".queue"),
      let saved = try? JSONDecoder().decode([QueuedEncounter].self, from: data)
    {
      queue = saved
    }
    prune()
    // No Bluetooth access until an explicit opt-in; restored opt-in uses a still valid token.
    if let data = OnlineVault.read(prefix + ".token"),
      let saved = try? JSONDecoder().decode(OnlineEncounterToken.self, from: data),
      saved.expiresAt > Date().timeIntervalSince1970 * 1000
    {
      start(token: saved)
    }
  }
  private func signingKey() throws -> P256.Signing.PrivateKey {
    if let key { return key }
    let value: P256.Signing.PrivateKey
    if let data = OnlineVault.read(prefix + ".key") {
      value = try P256.Signing.PrivateKey(rawRepresentation: data)
    } else {
      value = P256.Signing.PrivateKey()
      try OnlineVault.write(value.rawRepresentation, key: prefix + ".key")
    }
    key = value
    return value
  }
  func publicKey() throws -> [String: String] {
    let bytes = try signingKey().publicKey.x963Representation
    return [
      "kty": "EC", "crv": "P-256", "x": Data(bytes[1..<33]).base64URL,
      "y": Data(bytes[33..<65]).base64URL,
    ]
  }
  private func random() -> String {
    var data = Data(count: 32)
    data.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
    return data.base64URL
  }
  func start(token: OnlineEncounterToken) {
    guard token.expiresAt > Date().timeIntervalSince1970 * 1000, (try? signingKey()) != nil else {
      return
    }
    self.token = token
    offer = .init(token: token.token, challenge: random())
    enabled = true
    try? OnlineVault.write(try? JSONEncoder().encode(token), key: prefix + ".token")
    if central == nil {
      central = CBCentralManager(
        delegate: self, queue: .main,
        options: [CBCentralManagerOptionRestoreIdentifierKey: "AirTalk.online.central.v1"])
      peripheral = CBPeripheralManager(
        delegate: self, queue: .main,
        options: [CBPeripheralManagerOptionRestoreIdentifierKey: "AirTalk.online.peripheral.v1"])
    }
    reconcile()
  }
  func stop() {
    enabled = false
    central?.stopScan()
    peripheral?.stopAdvertising()
    for peer in peers.values { central?.cancelPeripheralConnection(peer) }
    phases.removeAll()
    outgoing.removeAll()
    sent.removeAll()
    remoteOffers.removeAll()
    input.removeAll()
    replies.removeAll()
    remoteExpiry.removeAll()
    token = nil
    offer = nil
    try? OnlineVault.write(nil, key: prefix + ".token")
  }
  func erase() {
    stop()
    queue = []
    try? OnlineVault.write(nil, key: prefix + ".queue")
    try? OnlineVault.write(nil, key: prefix + ".key")
    key = nil
  }
  func acknowledge(_ receipt: OnlineEncounterReceipt) {
    queue.removeAll { $0.receipt == receipt }
    persist()
  }
  private func persist() {
    try? OnlineVault.write(try? JSONEncoder().encode(queue), key: prefix + ".queue")
  }
  private func prune() {
    let now = Date()
    let oldQueue = queue
    queue.removeAll { $0.expires <= now }
    if queue.count > 100 { queue.removeFirst(queue.count - 100) }
    if oldQueue != queue { persist() }
    for (id, date) in remoteExpiry where date <= now {
      input[id] = nil
      replies[id] = nil
      remoteExpiry[id] = nil
    }
  }
  private func received(_ receipt: OnlineEncounterReceipt) {
    prune()
    guard !queue.contains(where: { $0.receipt == receipt }) else { return }
    queue.append(.init(receipt: receipt, expires: Date().addingTimeInterval(86400)))
    prune()
    persist()
    onReceipt(receipt)
  }
  private func valid() -> Bool {
    guard enabled, let token, token.expiresAt > Date().timeIntervalSince1970 * 1000 else {
      if enabled { stop() }
      return false
    }
    return true
  }
  private func reconcile() {
    guard valid(), central?.state == .poweredOn, peripheral?.state == .poweredOn else { return }
    if central?.isScanning == false {
      central?.scanForPeripherals(
        withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
      )
    }
    if !ready && !adding {
      adding = true
      let service = CBMutableService(type: Self.service, primary: true)
      service.characteristics = [
        CBMutableCharacteristic(
          type: Self.offerID, properties: .read, value: nil, permissions: .readable),
        CBMutableCharacteristic(
          type: Self.writeID, properties: .write, value: nil, permissions: .writeable),
        CBMutableCharacteristic(
          type: Self.receiptID, properties: .read, value: nil, permissions: .readable),
      ]
      peripheral?.add(service)
    } else if ready && peripheral?.isAdvertising == false {
      peripheral?.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.service]])
    }
  }
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state != .poweredOn {
      peers.removeAll()
      phases.removeAll()
    }
    reconcile()
  }
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state != .poweredOn {
      ready = false
      adding = false
    }
    if resetServices && peripheral.state == .poweredOn {
      peripheral.removeAllServices()
      resetServices = false
    }
    reconcile()
  }
  func peripheralManager(
    _ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?
  ) {
    adding = false
    ready = error == nil
    if ready { reconcile() }
  }
  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
    guard valid() else {
      peripheral.respond(to: request, withResult: .readNotPermitted)
      return
    }
    prune()
    let data: Data?
    if request.characteristic.uuid == Self.offerID {
      data = try? JSONEncoder().encode(offer)
    } else if request.characteristic.uuid == Self.receiptID {
      data = replies[request.central.identifier]
    } else {
      data = nil
    }
    guard let data, request.offset <= data.count else {
      peripheral.respond(to: request, withResult: .invalidOffset)
      return
    }
    request.value = Data(data.dropFirst(request.offset))
    peripheral.respond(to: request, withResult: .success)
  }
  func peripheralManager(
    _ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]
  ) {
    guard let first = requests.first else { return }
    guard valid() else {
      peripheral.respond(to: first, withResult: .writeNotPermitted)
      return
    }
    prune()
    for request in requests {
      let id = request.central.identifier
      guard request.characteristic.uuid == Self.writeID, request.offset == 0,
        let chunk = request.value, chunk.count > 1
      else {
        peripheral.respond(to: first, withResult: .invalidAttributeValueLength)
        return
      }
      guard input[id] != nil || input.count < 4 else {
        peripheral.respond(to: first, withResult: .insufficientResources)
        return
      }
      if chunk[0] == 0 {
        input[id] = Data()
        replies[id] = nil
      }
      guard chunk[0] <= 1, var data = input[id], data.count + chunk.count - 1 <= 4096 else {
        peripheral.respond(to: first, withResult: .invalidAttributeValueLength)
        return
      }
      data.append(chunk.dropFirst())
      input[id] = data
      remoteExpiry[id] = Date().addingTimeInterval(15)
      if let hello = try? JSONDecoder().decode(OnlineEncounterReceipt.self, from: data),
        let own = offer,
        hello.tokenB == own.token, hello.challengeB == own.challenge, hello.tokenA != own.token,
        hello.tokenA.count == 43, hello.challengeA.count == 43, hello.signatureA.count == 86,
        hello.signatureB.isEmpty
      {
        do {
          var receipt = hello
          receipt.signatureB = try signingKey().signature(for: receipt.payload).rawRepresentation
            .base64URL
          replies[id] = try JSONEncoder().encode(receipt)
          input[id] = nil
          received(receipt)
        } catch {
          peripheral.respond(to: first, withResult: .unlikelyError)
          return
        }
      }
    }
    peripheral.respond(to: first, withResult: .success)
  }
  func centralManager(
    _ central: CBCentralManager, didDiscover peer: CBPeripheral, advertisementData: [String: Any],
    rssi: NSNumber
  ) {
    guard valid(), peers[peer.identifier] == nil else { return }
    let now = Date()
    let low = ProcessInfo.processInfo.isLowPowerModeEnabled
    cooldown = cooldown.filter { now.timeIntervalSince($0.value) < 900 }
    guard peers.count < (low ? 1 : 2),
      now.timeIntervalSince(cooldown[peer.identifier] ?? .distantPast) > (low ? 900 : 300)
    else { return }
    if cooldown.count >= 256, let oldest = cooldown.min(by: { $0.value < $1.value }) {
      cooldown[oldest.key] = nil
    }
    cooldown[peer.identifier] = now
    peers[peer.identifier] = peer
    phases[peer.identifier] = 0
    peer.delegate = self
    central.connect(peer)
    Task { [weak self, weak peer] in
      try? await Task.sleep(for: .seconds(10))
      guard let self, let peer, self.peers[peer.identifier] === peer else { return }
      self.finish(peer)
    }
  }
  private func finish(_ peer: CBPeripheral) {
    central?.cancelPeripheralConnection(peer)
    phases[peer.identifier] = nil
    outgoing[peer.identifier] = nil
    sent[peer.identifier] = nil
    remoteOffers[peer.identifier] = nil
  }
  func centralManager(_ central: CBCentralManager, didConnect peer: CBPeripheral) {
    guard valid(), phases[peer.identifier] != nil else {
      finish(peer)
      return
    }
    peer.discoverServices([Self.service])
  }
  func centralManager(
    _ central: CBCentralManager, didFailToConnect peer: CBPeripheral, error: Error?
  ) {
    peers[peer.identifier] = nil
    phases[peer.identifier] = nil
  }
  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peer: CBPeripheral, error: Error?
  ) {
    peers[peer.identifier] = nil
    phases[peer.identifier] = nil
    outgoing[peer.identifier] = nil
    sent[peer.identifier] = nil
    remoteOffers[peer.identifier] = nil
  }
  func peripheral(_ peer: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil, valid(),
      let service = peer.services?.first(where: { $0.uuid == Self.service })
    else {
      finish(peer)
      return
    }
    peer.discoverCharacteristics([Self.offerID, Self.writeID, Self.receiptID], for: service)
  }
  private func characteristic(_ peer: CBPeripheral, _ id: CBUUID) -> CBCharacteristic? {
    peer.services?.first(where: { $0.uuid == Self.service })?.characteristics?.first(where: {
      $0.uuid == id
    })
  }
  func peripheral(
    _ peer: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    guard error == nil, valid(), let c = characteristic(peer, Self.offerID),
      characteristic(peer, Self.writeID) != nil, characteristic(peer, Self.receiptID) != nil
    else {
      finish(peer)
      return
    }
    peer.readValue(for: c)
  }
  func peripheral(
    _ peer: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard error == nil, valid(), let data = characteristic.value, data.count <= 4096,
      phases[peer.identifier] != nil
    else {
      finish(peer)
      return
    }
    if characteristic.uuid == Self.offerID {
      guard let other = try? JSONDecoder().decode(OnlineEncounterOffer.self, from: data),
        let own = offer, other.token.count == 43, other.challenge.count == 43,
        other.token != own.token
      else {
        finish(peer)
        return
      }
      do {
        var hello = OnlineEncounterReceipt(
          tokenA: own.token, tokenB: other.token, challengeA: own.challenge,
          challengeB: other.challenge, signatureA: "", signatureB: "")
        let sig = try signingKey().signature(for: hello.payload).rawRepresentation.base64URL
        hello = OnlineEncounterReceipt(
          tokenA: hello.tokenA, tokenB: hello.tokenB, challengeA: hello.challengeA,
          challengeB: hello.challengeB, signatureA: sig, signatureB: "")
        outgoing[peer.identifier] = try JSONEncoder().encode(hello)
        sent[peer.identifier] = 0
        remoteOffers[peer.identifier] = other
        phases[peer.identifier] = 1
        writeNext(peer)
      } catch { finish(peer) }
    } else if characteristic.uuid == Self.receiptID {
      guard let receipt = try? JSONDecoder().decode(OnlineEncounterReceipt.self, from: data),
        let helloData = outgoing[peer.identifier],
        let hello = try? JSONDecoder().decode(OnlineEncounterReceipt.self, from: helloData),
        receipt.payload == hello.payload, receipt.signatureA == hello.signatureA,
        receipt.signatureB.count == 86
      else {
        finish(peer)
        return
      }
      received(receipt)
      finish(peer)
    }
  }
  private func writeNext(_ peer: CBPeripheral) {
    guard valid(), let data = outgoing[peer.identifier], let offset = sent[peer.identifier],
      let c = characteristic(peer, Self.writeID)
    else {
      finish(peer)
      return
    }
    if offset >= data.count {
      guard let result = characteristic(peer, Self.receiptID) else {
        finish(peer)
        return
      }
      peer.readValue(for: result)
      return
    }
    let size = min(180, peer.maximumWriteValueLength(for: .withResponse) - 1)
    guard size > 0 else {
      finish(peer)
      return
    }
    let end = min(offset + size, data.count)
    var chunk = Data([offset == 0 ? 0 : 1])
    chunk.append(data[offset..<end])
    sent[peer.identifier] = end
    peer.writeValue(chunk, for: c, type: .withResponse)
  }
  func peripheral(
    _ peer: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard error == nil, phases[peer.identifier] != nil else {
      finish(peer)
      return
    }
    writeNext(peer)
  }
  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    for peer in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] {
      central.cancelPeripheralConnection(peer)
    }
    reconcile()
  }
  func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
    resetServices = true
    ready = false
    adding = false
    if peripheral.state == .poweredOn {
      peripheral.removeAllServices()
      resetServices = false
    }
    reconcile()
  }
}

extension Data {
  fileprivate var base64URL: String {
    base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
      of: "/", with: "_"
    ).replacingOccurrences(of: "=", with: "")
  }
}
