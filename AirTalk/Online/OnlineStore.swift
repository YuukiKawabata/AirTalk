import AuthenticationServices
import CryptoKit
import SwiftUI
import UserNotifications

@MainActor
final class OnlineStore: ObservableObject {
  @Published var profile: OnlineProfile?
  @Published var people: [OnlinePerson] = []
  @Published var requests: [OnlineRequest] = []
  @Published var connections: [OnlinePerson] = []
  @Published var rooms: [OnlineRoom] = []
  @Published var activeRoom: OnlineRoom?
  @Published var messages: [OnlineMessage] = []
  @Published var error: String?
  @Published var busy = false
  var screenVisible = false
  @Published var signedIn = false
  @Published var hasReconnectIntent = false
  @Published var peerReady = false
  @Published var challenge: OnlineChallenge?
  /// Shown once right after registration to offer encounter detection and request notifications.
  @Published var offerSetup = false
  let client: OnlineClient?
  private var socket: URLSessionWebSocketTask?
  private var receiving: Task<Void, Never>?
  private var heartbeat: Task<Void, Never>?
  private var revision = 0
  private var uploading = false
  lazy var encounters = OnlineEncounterService(
    scope: client?.configuration.baseURL.absoluteString ?? "unconfigured",
    onReceipt: { [weak self] receipt in
      Task { @MainActor in await self?.upload(receipt) }
    })

  init(configuration: OnlineConfiguration? = .current) {
    client = configuration.map { OnlineClient(configuration: $0) }
    signedIn = client?.credentials != nil
  }
  func perform(_ action: () async throws -> Void) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do { try await action() } catch is CancellationError {} catch {
      self.error = error.localizedDescription
    }
  }
  func load() async {
    await perform { try await self.reload() }
  }
  private func reload() async throws {
    guard let client, signedIn else { return }
    let rev = revision
    if activeRoom == nil { try await client.refreshIfNeeded() }
    let p: OnlineProfile = try await client.call("v1/me/profile")
    guard rev == revision else { return }
    profile = p
    guard p.consent else { return }
    let found: OnlinePeopleResponse = try await client.call("v1/encounters")
    let pending: OnlineRequestsResponse = try await client.call("v1/requests")
    let saved: OnlinePeopleResponse = try await client.call("v1/connections")
    let active: OnlineRoomsResponse = try await client.call("v1/conversations")
    guard rev == revision else { return }
    people = found.people
    requests = pending.requests
    connections = saved.people
    rooms = active.rooms
  }
  func prepareLogin() async {
    await perform {
      guard let client else { throw OnlineFailure.unavailable }
      self.challenge = try await client.call(
        "v1/auth/apple/challenge", method: "POST", body: [:], authenticated: false)
    }
  }
  func signIn(_ result: Result<ASAuthorization, Error>) async {
    await perform {
      guard let client, let challenge else { throw OnlineFailure.unavailable }
      // The server consumes a challenge on every attempt, so never reuse one after a failure.
      defer { if !signedIn { self.challenge = nil } }
      let auth = try result.get()
      guard let apple = auth.credential as? ASAuthorizationAppleIDCredential,
        let code = apple.authorizationCode, let identity = apple.identityToken,
        let codeString = String(data: code, encoding: .utf8),
        let tokenString = String(data: identity, encoding: .utf8)
      else { throw OnlineFailure.invalidResponse }
      let credentials: OnlineCredentials = try await client.call(
        "v1/auth/apple", method: "POST",
        body: [
          "challengeID": challenge.id, "code": codeString, "identityToken": tokenString,
        ], authenticated: false)
      try client.install(credentials)
      signedIn = true
      self.challenge = nil
      try await reload()
    }
  }
  #if DEBUG
    func localSignIn(name: String) async {
      await perform {
        guard let client, client.configuration.local else { throw OnlineFailure.unavailable }
        let c: OnlineCredentials = try await client.call(
          "v1/dev/login", method: "POST", body: ["name": name], authenticated: false)
        try client.install(c)
        signedIn = true
        try await reload()
      }
    }
  #endif
  func consent(name: String, intro: String) async {
    await perform {
      guard let client else { throw OnlineFailure.unavailable }
      let _: OnlineProfile = try await client.call(
        "v1/me/profile", method: "PATCH",
        body: ["name": name, "intro": intro, "icon": "person.circle"])
      let _: OnlineOK = try await client.call(
        "v1/me/consents", method: "PUT",
        body: ["adult": true, "consent": true, "ble": false, "version": "pilot-1"])
      try await reload()
      if profile?.consent == true { offerSetup = true }
    }
  }
  func request(_ person: OnlinePerson) async {
    await mutate("v1/requests", body: ["peerID": person.id])
  }
  func respond(_ request: OnlineRequest, accept: Bool) async {
    await mutate("v1/requests/\(request.id)/\(accept ? "accept" : "decline")")
  }
  private func mutate(_ path: String, body: [String: Any] = [:]) async {
    await perform {
      guard let client else { throw OnlineFailure.unavailable }
      let _: OnlineID = try await client.call(path, method: "POST", body: body)
      try await reload()
    }
  }
  func start(_ request: OnlineRequest) async {
    await perform {
      guard let client else { throw OnlineFailure.unavailable }
      let room: OnlineID = try await client.call(
        "v1/conversations", method: "POST", body: ["requestID": request.id])
      try await joinRoom(.init(id: room.id, peer: request.peer))
    }
  }
  func join(_ room: OnlineRoom) async { await perform { try await joinRoom(room) } }
  private func joinRoom(_ room: OnlineRoom) async throws {
    guard let client, activeRoom == nil else { throw OnlineFailure.unavailable }
    let ticket: OnlineTicket = try await client.call(
      "v1/conversations/\(room.id)/ticket", method: "POST", body: [:])
    let ws = try client.socket(room: room.id, ticket: ticket.ticket)
    activeRoom = room
    messages = []
    hasReconnectIntent = false
    socket = ws
    ws.resume()
    receiving = Task { [weak self] in
      do {
        while !Task.isCancelled {
          let event = try await ws.receive()
          guard let self, self.socket === ws else { return }
          if case .string(let raw) = event, let data = raw.data(using: .utf8), data.count <= 8192,
            let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any]
          {
            if frame["type"] as? String == "ready" {
              self.peerReady = true
              continue
            }
            guard let id = frame["id"] as? String else { continue }
            if frame["type"] as? String == "rejected" {
              self.messages.removeAll { $0.id == id }
              self.error = String(localized: "リンクや一部の不適切な内容は送信できません。")
            } else if frame["type"] as? String == "message", let text = frame["text"] as? String,
              !self.messages.contains(where: { $0.id == id })
            {
              self.messages.append(.init(id: id, text: text, isMe: false))
              self.trim()
            }
          }
        }
      } catch {
        guard let self, self.socket === ws else { return }
        self.clearConversation()
        self.error = String(localized: "会話は終了しました。メッセージは消去されました。")
        self.people = []
        self.requests = []
        self.connections = []
        self.rooms = []
        if UIApplication.shared.applicationState == .active { Task { await self.load() } }
      }
    }
    heartbeat = Task { [weak self] in
      while !Task.isCancelled {
        guard let self, self.socket === ws else { return }
        do {
          try await self.frame(["type": "heartbeat"])
          try await Task.sleep(for: .seconds(15))
        } catch {
          if self.socket === ws { self.clearConversation() }
          return
        }
      }
    }
  }
  func send(_ value: String) async {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.unicodeScalars.count <= 1000, text.utf8.count <= 4000,
      activeRoom != nil, peerReady
    else {
      return
    }
    let id = UUID().uuidString
    let ws = socket
    messages.append(.init(id: id, text: text, isMe: true))
    trim()
    do {
      try await frame(["type": "message", "id": id, "text": text])
    } catch {
      guard socket === ws else { return }
      clearConversation()
      self.error = error.localizedDescription
    }
  }
  private func trim() { if messages.count > 200 { messages.removeFirst(messages.count - 200) } }
  private func frame(_ fields: [String: Any]) async throws {
    guard let socket, let room = activeRoom else { throw OnlineFailure.unavailable }
    let data = try JSONSerialization.data(
      withJSONObject: fields.merging(["v": 1, "conversationID": room.id]) { _, new in new })
    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
  }
  func end() {
    let id = activeRoom?.id
    clearConversation()
    if let id, let client {
      Task {
        let _: OnlineOK? = try? await client.call(
          "v1/conversations/\(id)/end", method: "POST", body: [:])
      }
    }
  }
  private func clearConversation() {
    receiving?.cancel()
    heartbeat?.cancel()
    receiving = nil
    heartbeat = nil
    socket?.cancel(with: .normalClosure, reason: nil)
    socket = nil
    messages = []
    activeRoom = nil
    peerReady = false
    hasReconnectIntent = false
  }
  func reconnect() async {
    guard let id = activeRoom?.id else { return }
    await perform {
      guard let client else { throw OnlineFailure.unavailable }
      let _: OnlineOK = try await client.call(
        "v1/conversations/\(id)/reconnect-intent", method: "POST", body: [:])
      if activeRoom?.id == id { hasReconnectIntent = true }
    }
  }
  func block(_ peer: OnlinePerson, reason: String? = nil) async {
    // Clear local content immediately, even when the network is unavailable.
    if activeRoom?.peer.id == peer.id { end() }
    await perform {
      guard let client else { throw OnlineFailure.unavailable }
      var body: [String: Any] = ["peerID": peer.id]
      if let reason { body["reason"] = reason }
      let _: OnlineOK = try await client.call(
        reason == nil ? "v1/blocks" : "v1/reports", method: "POST", body: body)
      try await reload()
    }
  }
  func removeConnection(_ peer: OnlinePerson) async {
    await perform {
      guard let client else { throw OnlineFailure.unavailable }
      let _: OnlineOK = try await client.call("v1/connections/\(peer.id)", method: "DELETE")
      try await reload()
    }
  }
  func logout(delete: Bool) async {
    end()
    encounters.stop()
    await perform {
      guard let client else { throw OnlineFailure.unavailable }
      if delete {
        let _: OnlineOK = try await client.call("v1/me", method: "DELETE")
      } else {
        let _: OnlineOK? = try? await client.call("v1/auth/logout", method: "POST", body: [:])
      }
      revision += 1
      client.clear()
      signedIn = false
      profile = nil
      people = []
      requests = []
      connections = []
      rooms = []
      encounters.erase()
    }
  }
  func setEncounters(_ enabled: Bool) async {
    if !enabled { encounters.stop() }
    await perform {
      guard let client else { throw OnlineFailure.unavailable }
      let _: OnlineOK = try await client.call(
        "v1/me/consents", method: "PUT",
        body: ["adult": true, "consent": true, "ble": enabled, "version": "pilot-1"])
      if enabled {
        let key = try encounters.publicKey()
        let _: OnlineOK = try await client.call("v1/me/device", method: "PUT", body: ["key": key])
        let token: OnlineEncounterToken = try await client.call(
          "v1/encounter-tokens", method: "POST", body: [:])
        encounters.start(token: token)
      }
      try await reload()
    }
  }
  private func upload(_ receipt: OnlineEncounterReceipt) async {
    guard let client, signedIn, !uploading else { return }
    uploading = true
    defer { uploading = false }
    do {
      if activeRoom == nil { try await client.refreshIfNeeded() }
      let data = try JSONEncoder().encode(receipt)
      let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
      let _: OnlineOK = try await client.call("v1/encounter-receipts", method: "POST", body: body)
      encounters.acknowledge(receipt)
    } catch { /* Queue contains signed encounter proof only; never chat messages. */  }
  }
  func enableRecommended() async {
    await setEncounters(true)
    await enableNotifications()
  }
  func enableNotifications() async {
    await perform {
      let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound,
      ])
      if allowed { UIApplication.shared.registerForRemoteNotifications() }
    }
  }
  func registerPush(_ data: Data) async {
    guard let client, signedIn else { return }
    let token = data.map { String(format: "%02x", $0) }.joined()
    do {
      let _: OnlineOK = try await client.call("v1/me/push", method: "PUT", body: ["token": token])
    } catch { self.error = error.localizedDescription }
  }
  func becameActive() async {
    guard client != nil, signedIn else { return }
    await load()
    for receipt in encounters.pending { await upload(receipt) }
    if profile?.ble == true, encounters.needsFreshToken, let client {
      do {
        let token: OnlineEncounterToken = try await client.call(
          "v1/encounter-tokens", method: "POST", body: [:])
        encounters.start(token: token)
      } catch { /* Keep the previous unexpired token; no background polling. */  }
    }
  }
}
