import SwiftUI

struct OnlinePolicyView: View {
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section("利用できる方") {
          Text("オンライン機能は18歳以上が対象です。相手が承認すると会話できます。嫌がらせ、脅迫、性的搾取、なりすまし、迷惑な勧誘は禁止です。")
        }
        Section("保存する情報") {
          Text(
            "Appleの利用者識別子、ニックネーム、ひとこと、同意状態を保存します。Bluetooth検出を選ぶと、署名の照合に必要な情報とすれ違いを最大24時間保持します。通知を許可すると配信用の端末トークンを登録します。"
          )
          Text(
            "オンラインの会話は暗号化した通信路でサーバーが中継します。中継中はサーバーで本文を読めます。本文は保存せず、双方が「また話したい」を選んだ場合につながりを保存します。")
        }
        Section("通報・停止・削除") {
          Text("相手のメニューから理由を選んで通報すると、その相手をブロックします。通報理由と当事者の識別子は90日、利用停止後の再登録を防ぐ照合情報は最大180日保持します。")
          Text(
            "設定の「アカウントを削除」でプロフィールとつながりを削除できます。バックアップは最大30日、Appleの認証を取り消すための暗号化された資格情報は処理完了まで最大35日残る場合があります。"
          )
        }
        Link("削除・利用停止について問い合わせる", destination: URL(string: "mailto:" + SafetyPolicy.supportEmail)!)
      }
      .navigationTitle("オンライン利用条件と問い合わせ")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("閉じる") { dismiss() } }
    }
  }
}
