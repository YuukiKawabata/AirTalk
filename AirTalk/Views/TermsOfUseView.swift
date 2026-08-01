import SwiftUI

struct TermsOfUseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("AirTalk 利用規約 / EULA")
                        .font(.title2.bold())

                    section(
                        title: "1. No tolerance policy",
                        body: "AirTalk does not tolerate objectionable content or abusive users. Harassment, threats, hate speech, sexual content involving minors, spam, impersonation, and any unlawful or harmful conduct are prohibited."
                    )

                    section(
                        title: "2. 通報とブロック",
                        body: "ユーザーは不適切なメッセージを通報できます。また、迷惑行為を行うユーザーをブロックできます。ブロックすると、そのユーザーとの会話は端末上から直ちに削除され、そのユーザーはレーダーや招待に表示されなくなります。通報またはブロック時には、開発者へ内容を通知するためのメール作成画面が開きます。"
                    )

                    section(
                        title: "3. User-generated content",
                        body: "AirTalk is a peer-to-peer chat app. You are responsible for the messages and profile text you share with nearby users. Do not share content that violates these terms or another person's rights."
                    )

                    section(
                        title: "4. プライバシーとデータ",
                        body: "AirTalk はサーバーアカウントを作成せず、チャット履歴をサーバーに保存しません。プロフィールは端末内に保存され、相手と直接接続した場合にのみ相手の端末へ送信されます。設定画面からプロフィールとローカルデータを削除できます。"
                    )

                    section(
                        title: "5. Support",
                        body: "Questions, abuse reports, and support requests can be sent to \(SafetyPolicy.supportEmail). Support information is available at \(SafetyPolicy.supportURL.absoluteString). Terms of Use: \(SafetyPolicy.termsURL.absoluteString). Privacy Policy: \(SafetyPolicy.privacyURL.absoluteString)."
                    )

                    Text("Last updated: June 13, 2026")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding(24)
            }
            .navigationTitle("利用規約")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
