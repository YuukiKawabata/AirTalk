import CryptoKit
import Foundation
import Security

struct OnlineConfiguration {
  let baseURL: URL
  let local: Bool
  static var current: Self? {
    #if DEBUG
      if let raw = UserDefaults.standard.string(forKey: "onlineURL"), let url = URL(string: raw),
        ["127.0.0.1", "localhost"].contains(url.host ?? ""), url.scheme == "http"
      {
        return .init(baseURL: url, local: true)
      }
    #endif
    guard Bundle.main.object(forInfoDictionaryKey: "AirTalkOnlinePilotEnabled") as? Bool == true,
      let raw = Bundle.main.object(forInfoDictionaryKey: "AirTalkOnlineBaseURL") as? String,
      let url = URL(string: raw), url.scheme == "https", url.host != nil,
      url.user == nil, url.password == nil, url.query == nil
    else { return nil }
    return .init(baseURL: url, local: false)
  }
}

enum OnlineFailure: LocalizedError {
  case unavailable
  case server(String)
  case keychain, invalidResponse
  var errorDescription: String? {
    switch self {
    case .unavailable: return String(localized: "オンライン検証環境が設定されていません。")
    case .keychain: return String(localized: "端末の安全な保存領域を利用できません。")
    case .invalidResponse: return String(localized: "通信を確認して、もう一度お試しください。")
    case .server(let code):
      switch code {
      case "pilot_full": return String(localized: "現在、新規登録の受付数が上限に達しています。しばらくしてからお試しください。")
      case "unauthorized", "apple_auth_failed": return String(localized: "もう一度サインインしてください。")
      case "conversation_ended": return String(localized: "会話は終了しました。メッセージは消去されました。")
      case "rate_limited": return String(localized: "しばらく待ってからお試しください。")
      case "approval_required", "unavailable", "encounter_expired":
        return String(localized: "相手の承認または新しいすれ違いが必要です。")
      default: return String(localized: "通信を確認して、もう一度お試しください。")
      }
    }
  }
}

enum OnlineVault {
  static func read(_ key: String) -> Data? {
    var result: CFTypeRef?
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "AirTalk.online.v1",
      kSecAttrAccount as String: key, kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    return SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
  }
  static func write(_ data: Data?, key: String) throws {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "AirTalk.online.v1",
      kSecAttrAccount as String: key,
    ]
    guard let data else {
      SecItemDelete(q as CFDictionary)
      return
    }
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      guard
        SecItemAdd(q.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
      else { throw OnlineFailure.keychain }
    } else if status != errSecSuccess {
      throw OnlineFailure.keychain
    }
  }
}

struct OnlineCredentials: Codable {
  let accessToken: String
  let refreshToken: String
  let expiresAt: Double
  let accountID: String
}
struct OnlinePerson: Codable, Identifiable {
  let id: String
  let name: String
  let intro: String
  let icon: String
  var expiresAt: Double?
}
struct OnlineProfile: Codable {
  let id: String
  let name: String
  let intro: String
  let icon: String
  let adult: Bool
  let consent: Bool
  let ble: Bool
}
struct OnlineRequest: Codable, Identifiable {
  let id: String
  let from: String
  let to: String
  let status: String
  let until: Double
  let peer: OnlinePerson
}
struct OnlineRoom: Codable, Identifiable {
  let id: String
  let peer: OnlinePerson
}
struct OnlineMessage: Identifiable {
  let id: String
  let text: String
  let isMe: Bool
}
struct OnlineChallenge: Codable {
  let id: String
  let nonce: String
}
struct OnlineEncounterToken: Codable {
  let token: String
  let expiresAt: Double
}
struct OnlinePeopleResponse: Decodable { let people: [OnlinePerson] }
struct OnlineRequestsResponse: Decodable { let requests: [OnlineRequest] }
struct OnlineRoomsResponse: Decodable { let rooms: [OnlineRoom] }
struct OnlineOK: Decodable { let ok: Bool }
struct OnlineID: Decodable { let id: String }
struct OnlineTicket: Decodable { let ticket: String }

@MainActor
final class OnlineClient {
  let configuration: OnlineConfiguration
  private(set) var credentials: OnlineCredentials?
  private let session: URLSession
  private let vaultKey: String
  private var generation = 0
  init(configuration: OnlineConfiguration) {
    self.configuration = configuration
    vaultKey =
      "session."
      + SHA256.hash(data: Data(configuration.baseURL.absoluteString.utf8)).map {
        String(format: "%02x", $0)
      }.joined()
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.httpCookieStorage = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 20
    session = URLSession(configuration: config)
    if let data = OnlineVault.read(vaultKey) {
      credentials = try? JSONDecoder().decode(OnlineCredentials.self, from: data)
    }
  }
  func clear() {
    generation += 1
    credentials = nil
    try? OnlineVault.write(nil, key: vaultKey)
  }
  func install(_ value: OnlineCredentials) throws {
    try OnlineVault.write(JSONEncoder().encode(value), key: vaultKey)
    credentials = value
  }
  func call<T: Decodable>(
    _ path: String, method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true
  ) async throws -> T {
    let revision = generation
    var req = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if authenticated {
      guard let credentials else { throw OnlineFailure.server("unauthorized") }
      req.setValue("Bearer " + credentials.accessToken, forHTTPHeaderField: "Authorization")
    }
    if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await session.data(for: req)
    guard revision == generation else { throw CancellationError() }
    guard let http = response as? HTTPURLResponse, data.count <= 1_048_576 else {
      throw OnlineFailure.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let code =
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String
        ?? "service_error"
      throw OnlineFailure.server(code)
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
  func refreshIfNeeded() async throws {
    guard let c = credentials, c.expiresAt < Date().timeIntervalSince1970 * 1000 + 60_000 else {
      return
    }
    let updated: OnlineCredentials = try await call(
      "v1/auth/refresh", method: "POST", body: ["refreshToken": c.refreshToken],
      authenticated: false)
    try install(updated)
  }
  func socket(room: String, ticket: String) throws -> URLSessionWebSocketTask {
    guard let credentials else { throw OnlineFailure.server("unauthorized") }
    var components = URLComponents(
      url: configuration.baseURL.appendingPathComponent("v1/conversations/\(room)/socket"),
      resolvingAgainstBaseURL: false)!
    components.scheme = configuration.local ? "ws" : "wss"
    var request = URLRequest(url: components.url!)
    request.setValue("Bearer " + credentials.accessToken, forHTTPHeaderField: "Authorization")
    request.setValue(ticket, forHTTPHeaderField: "X-AirTalk-Ticket")
    request.timeoutInterval = 15
    return session.webSocketTask(with: request)
  }
}
