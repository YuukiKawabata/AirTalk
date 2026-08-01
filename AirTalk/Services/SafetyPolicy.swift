import Foundation
import MultipeerConnectivity

enum SafetyPolicy {
    static let supportEmail = "kakabata.man@gmail.com"
    static let supportURL = URL(string: "https://yuukikawabata.github.io/airwish-support/")!
    static let privacyURL = URL(string: "https://yuukikawabata.github.io/airwish-support/#privacy")!
    static let termsURL = URL(string: "https://yuukikawabata.github.io/airwish-support/#terms")!
}

enum SafetyReportKind {
    case message
    case block

    var subject: String {
        switch self {
        case .message:
            return "AirTalk objectionable content report"
        case .block:
            return "AirTalk abusive user block report"
        }
    }
}

struct SafetyReport {
    static func mailURL(
        kind: SafetyReportKind,
        peerID: MCPeerID,
        message: AirMessage?,
        recentMessages: [AirMessage]
    ) -> URL? {
        var body = """
        AirTalk Safety Report

        Action: \(kind.subject)
        Reported user: \(peerID.displayName)
        Report date: \(Date())

        """

        if let message {
            body += """
            Reported message:
            Sender: \(message.sender)
            Time: \(message.timestamp)
            Text: \(message.text)

            """
        }

        if !recentMessages.isEmpty {
            body += "Recent chat context:\n"
            for item in recentMessages.suffix(10) {
                body += "- [\(item.timestamp)] \(item.sender): \(item.text)\n"
            }
        }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = SafetyPolicy.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: kind.subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}
