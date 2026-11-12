#if DEBUG
import CoreBluetooth
import UIKit

/// Internal feasibility experiment, enabled only by -encounterPrototype YES.
/// All state and Core Bluetooth delegates are serialized on the main queue.
final class EncounterManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {
    static let serviceID = CBUUID(string: "50277558-B84D-48A1-A59B-9BCE42E3F014")
    static let tokenID = CBUUID(string: "50277558-B84D-48A1-A59B-9BCE42E3F015")
    static let isAvailable: Bool = {
        (UserDefaults.standard.bool(forKey: "encounterPrototype") || UserDefaults.standard.bool(forKey: enabledKey)) || (DemoMode.isEnabled && DemoMode.scene == .encounters)
    }()

    @Published private(set) var enabled = false
    @Published private(set) var records: [EncounterRecord] = []
    @Published private(set) var status = String(localized: "停止中")
    @Published private(set) var scanning = false
    @Published private(set) var advertising = false
    @Published private(set) var completedReads = 0
    @Published private(set) var failedReads = 0
    @Published private(set) var backgroundReads = 0
    @Published private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var startedAt: Date?

    private let defaults: UserDefaults
    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var serviceReady = false
    private var addingService = false
    private var needsServiceReset = false
    private var token = UUID()
    private var tokenDate = Date.distantPast
    private var active: [UUID: CBPeripheral] = [:]
    private var attempts: [UUID: UUID] = [:]
    private var cooldown: [UUID: Date] = [:]
    private var observers: [NSObjectProtocol] = []
    private static let enabledKey = "encounterPrototype.enabled"
    private static let recordsKey = "encounterPrototype.records"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        guard Self.isAvailable, !DemoMode.isEnabled else {
            if DemoMode.isEnabled && DemoMode.scene == .encounters {
                records = (0..<3).map { EncounterRecord(id: UUID(), firstSeen: Date().addingTimeInterval(Double(-$0 * 300)), lastSeen: Date()) }
                status = String(localized: "デモ：実際の検出ではありません")
            }
            return
        }
        if let data = defaults.data(forKey: Self.recordsKey), let saved = try? JSONDecoder().decode([EncounterRecord].self, from: data) {
            records = EncounterPolicy.pruned(saved, now: Date())
        }
        persist()
        for name in [UIApplication.didBecomeActiveNotification, NSNotification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        if defaults.bool(forKey: Self.enabledKey) { setEnabled(true) }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func setEnabled(_ value: Bool) {
        guard Self.isAvailable, !DemoMode.isEnabled else { return }
        enabled = value
        defaults.set(value, forKey: Self.enabledKey)
        if value {
            startedAt = Date()
            rotateTokenIfNeeded()
            // Managers are created only after opt-in; disabled launches do not request Bluetooth.
            if central == nil {
                central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "AirTalk.encounter.central.v1"])
                peripheral = CBPeripheralManager(delegate: self, queue: .main, options: [CBPeripheralManagerOptionRestoreIdentifierKey: "AirTalk.encounter.peripheral.v1"])
            }
            reconcile()
        } else {
            central?.stopScan()
            peripheral?.stopAdvertising()
            for peer in Array(active.values) { central?.cancelPeripheralConnection(peer) }
            attempts.removeAll()
            cooldown.removeAll()
            scanning = false
            advertising = false
            token = UUID()
            tokenDate = .distantPast
            status = String(localized: "停止中")
        }
    }

    func eraseObservations() {
        records = []
        completedReads = 0
        failedReads = 0
        backgroundReads = 0
        persist()
    }

    func refresh() {
        guard !DemoMode.isEnabled else { return }
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        records = EncounterPolicy.pruned(records, now: Date())
        persist()
        if enabled { rotateTokenIfNeeded(); reconcile() }
    }

    private func persist() {
        guard !DemoMode.isEnabled else { return }
        // No chat content is ever passed to this store. Expiry is enforced on every read/wake.
        if records.isEmpty { defaults.removeObject(forKey: Self.recordsKey) }
        else if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.recordsKey) }
    }

    private func rotateTokenIfNeeded() {
        let pruned = EncounterPolicy.pruned(records, now: Date())
        if pruned != records { records = pruned; persist() }
        if Date().timeIntervalSince(tokenDate) >= EncounterPolicy.tokenLifetime || tokenDate > Date() {
            token = UUID()
            tokenDate = Date()
        }
    }

    private func reconcile() {
        guard enabled else { return }
        guard central?.state == .poweredOn, peripheral?.state == .poweredOn else {
            scanning = false
            advertising = false
            if central?.state == .unauthorized || peripheral?.state == .unauthorized {
                status = String(localized: "Bluetoothの使用を許可してください")
            } else if central?.state == .unsupported || peripheral?.state == .unsupported {
                status = String(localized: "この端末では検証できません")
            } else {
                status = String(localized: "Bluetoothの準備を待っています")
            }
            return
        }
        if central?.isScanning == false {
            central?.scanForPeripherals(withServices: [Self.serviceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        scanning = central?.isScanning == true
        if !serviceReady && !addingService {
            addingService = true
            let service = CBMutableService(type: Self.serviceID, primary: true)
            service.characteristics = [CBMutableCharacteristic(type: Self.tokenID, properties: [.read], value: nil, permissions: [.readable])]
            peripheral?.add(service)
        } else if serviceReady && peripheral?.isAdvertising == false {
            peripheral?.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceID]])
        }
        status = String(localized: "すれ違いを検証中")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            active.removeAll(); attempts.removeAll(); cooldown.removeAll()
        }
        reconcile()
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state != .poweredOn { serviceReady = false; addingService = false }
        if peripheral.state == .poweredOn && needsServiceReset {
            peripheral.stopAdvertising()
            peripheral.removeAllServices()
            needsServiceReset = false
        }
        reconcile()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        addingService = false
        guard service.uuid == Self.serviceID else { return }
        serviceReady = error == nil
        guard error == nil else { status = String(localized: "Bluetooth処理に失敗しました。一度停止して再開してください"); return }
        reconcile()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard enabled else { peripheral.stopAdvertising(); return }
        advertising = error == nil && peripheral.isAdvertising
        if error != nil { status = String(localized: "Bluetooth処理に失敗しました。一度停止して再開してください") }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard enabled, request.characteristic.uuid == Self.tokenID else {
            peripheral.respond(to: request, withResult: .readNotPermitted); return
        }
        rotateTokenIfNeeded()
        let data = EncounterPolicy.packet(for: token)
        guard request.offset <= data.count else { peripheral.respond(to: request, withResult: .invalidOffset); return }
        request.value = data.subdata(in: request.offset..<data.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peer: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard enabled, active[peer.identifier] == nil else { return }
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let now = Date()
        cooldown = cooldown.filter { now.timeIntervalSince($0.value) < 15 * 60 }
        let interval: TimeInterval = lowPower ? 15 * 60 : 5 * 60
        guard active.count < (lowPower ? 1 : 2),
              cooldown[peer.identifier].map({ now.timeIntervalSince($0) >= interval }) ?? true else { return }
        // Bound memory in crowded venues; OS controls scan timing, no polling loop.
        if cooldown.count >= 256, let oldest = cooldown.min(by: { $0.value < $1.value })?.key { cooldown[oldest] = nil }
        cooldown[peer.identifier] = now
        begin(peer)
        central.connect(peer, options: nil)
    }

    private func begin(_ peer: CBPeripheral) {
        peer.delegate = self
        active[peer.identifier] = peer
        let attempt = UUID()
        attempts[peer.identifier] = attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak peer] in
            guard let self, let peer, self.attempts[peer.identifier] == attempt else { return }
            self.finish(peer, failed: true)
        }
    }

    private func finish(_ peer: CBPeripheral, failed: Bool) {
        guard attempts.removeValue(forKey: peer.identifier) != nil else { return }
        if failed { failedReads += 1 }
        // Keep the peer in active until cancellation completes, preventing stale callbacks from
        // a previous attempt being mistaken for a new attempt on the same peripheral.
        central?.cancelPeripheralConnection(peer)
    }

    func centralManager(_ central: CBCentralManager, didConnect peer: CBPeripheral) {
        guard enabled, attempts[peer.identifier] != nil else { central.cancelPeripheralConnection(peer); return }
        peer.discoverServices([Self.serviceID])
    }

    func peripheral(_ peer: CBPeripheral, didDiscoverServices error: Error?) {
        guard enabled, attempts[peer.identifier] != nil else { return }
        guard error == nil, let service = peer.services?.first(where: { $0.uuid == Self.serviceID }) else { finish(peer, failed: true); return }
        peer.discoverCharacteristics([Self.tokenID], for: service)
    }

    func peripheral(_ peer: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard enabled, attempts[peer.identifier] != nil else { return }
        guard error == nil, let characteristic = service.characteristics?.first(where: { $0.uuid == Self.tokenID && $0.properties.contains(.read) }) else { finish(peer, failed: true); return }
        peer.readValue(for: characteristic)
    }

    func peripheral(_ peer: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard enabled, attempts[peer.identifier] != nil, characteristic.uuid == Self.tokenID else { return }
        guard error == nil, let data = characteristic.value, let received = EncounterPolicy.token(from: data), received != token else { finish(peer, failed: true); return }
        records = EncounterPolicy.recording(received, in: records, now: Date())
        completedReads += 1
        if UIApplication.shared.applicationState == .background { backgroundReads += 1 }
        persist()
        finish(peer, failed: false)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peer: CBPeripheral, error: Error?) {
        if attempts.removeValue(forKey: peer.identifier) != nil { failedReads += 1 }
        active[peer.identifier] = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peer: CBPeripheral, error: Error?) {
        if attempts.removeValue(forKey: peer.identifier) != nil { failedReads += 1 }
        active[peer.identifier] = nil
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        for peer in dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? [] {
            guard enabled, active.count < 2 else { central.cancelPeripheralConnection(peer); continue }
            begin(peer)
            if peer.state == .connected { peer.discoverServices([Self.serviceID]) }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        // Rebuild the dynamic read service rather than exposing a restored stale token value.
        needsServiceReset = true
        serviceReady = false
        addingService = false
    }
}
#endif
