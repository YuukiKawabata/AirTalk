#if DEBUG
import SwiftUI

struct EncounterPrototypeView: View {
    @ObservedObject var manager: EncounterManager
    @State private var confirmEnable = false
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("バックグラウンドBLEの実機検証用です。オンライン接続やプロフィール交換は行いません。")
                    Toggle("すれ違い検出", isOn: Binding(
                        get: { manager.enabled },
                        set: { if $0 { confirmEnable = true } else { manager.setEnabled(false) } }
                    ))
                    .disabled(DemoMode.isEnabled)
                    Text(manager.status)
                        .foregroundStyle(.secondary)
                } header: { Text("技術試作") }

                Section {
                    LabeledContent("探索", value: manager.scanning ? String(localized: "動作中") : String(localized: "停止中"))
                    LabeledContent("広告", value: manager.advertising ? String(localized: "動作中") : String(localized: "停止中"))
                    LabeledContent("低電力モード", value: manager.lowPower ? String(localized: "オン") : String(localized: "オフ"))
                    LabeledContent("読み取り成功", value: "\(manager.completedReads)")
                    LabeledContent("バックグラウンドで成功", value: "\(manager.backgroundReads)")
                    LabeledContent("読み取り失敗", value: "\(manager.failedReads)")
                    if let date = manager.startedAt {
                        LabeledContent("今回の開始") { Text(date, style: .time) }
                    }
                    Text("件数は人物数ではありません。識別子の更新で同じ端末が別件になります。診断カウンターは再起動でリセットされます。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("診断") }

                Section {
                    if manager.records.isEmpty {
                        Text("まだ検出記録はありません")
                    }
                    ForEach(manager.records) { record in
                        VStack(alignment: .leading) {
                            Text("一時識別子を検出")
                            Text(record.firstSeen, style: .time).foregroundStyle(.secondary)
                        }
                    }
                    Button("記録とカウンターを消去", role: .destructive) { confirmErase = true }
                } header: { Text("過去24時間の検出") }

                Section {
                    Text("双方の端末で検出をオンにしてください。ロック中の探索頻度はiOSが調整するため、短いすれ違いは検出できない場合があります。強制終了後はアプリを開き直してください。")
                    Text("記録はこの端末内だけに保持し、24時間後の次回動作時に削除します。検出をオフにしても既存の記録は残ります。位置情報・名前・会話本文は記録しません。")
                    Text("試作の識別子交換は本人確認や暗号化を実装していません。検証協力者の端末だけで利用してください。")
                } header: { Text("検証時の注意") }
            }
            .navigationTitle("すれ違い検証")
            .toolbar {
                Button("表示を更新") { manager.refresh() }
            }
            .confirmationDialog("すれ違い検出を有効にしますか？", isPresented: $confirmEnable, titleVisibility: .visible) {
                Button("同意して有効にする") { manager.setEnabled(true) }
            } message: {
                Text("画面ロック中もBluetoothで一時識別子を交換し、検出時刻とともに端末内へ保存します。いつでも停止・削除できます。サーバーには送信しません。")
            }
            .confirmationDialog("検出記録を消去しますか？", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("消去", role: .destructive) { manager.eraseObservations() }
            } message: {
                Text("検出がオンの場合、新しい記録は引き続き追加されます。")
            }
        }
    }
}
#endif
