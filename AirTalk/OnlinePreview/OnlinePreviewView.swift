#if DEBUG
import SwiftUI

@MainActor
final class OnlinePreviewStore: ObservableObject {
    @Published var state = OnlinePreviewState()

    init() {
        if DemoMode.scene != .online { state.optedIn = true }
        if DemoMode.scene == .onlineChat || DemoMode.scene == .onlineConnections {
            state.request("demo-aoi")
            state.simulatePeerAcceptance("demo-aoi")
            state.startChat("demo-aoi")
            state.send(String(localized: "こんにちは。旅行の話、私も好きです！"))
            state.send(String(localized: "こんにちは！最近よかった場所はありますか？"), isMe: false)
        }
        if DemoMode.scene == .onlineConnections {
            state.wantReconnect("demo-aoi")
            state.wantReconnect("demo-aoi", fromPeer: true)
            state.endChat()
        }
    }
}

struct OnlinePreviewView: View {
    static var isSelected: Bool {
        DemoMode.isEnabled && [.online, .onlinePeople, .onlineInbox, .onlineChat, .onlineConnections].contains(DemoMode.scene)
    }
    @StateObject private var store = OnlinePreviewStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    @State private var agreesAge = false
    @State private var agreesProfile = false
    @State private var showSettings = false
    @State private var showRadar = false
    @State private var input = ""
    @State private var reportTarget: String?
    @State private var deleteConfirmation = false
    @State private var reportedNotice = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackgroundView(themeColor: .purple)
                VStack(spacing: 0) {
                    Text("画面試作・すべて架空のデータです。通信・登録・送信は行いません。")
                        .font(.caption).foregroundStyle(.primary)
                        .padding(12).frame(maxWidth: .infinity).background(.ultraThinMaterial)
                    if !store.state.optedIn { introduction }
                    else if let id = store.state.activePeer { conversation(id) }
                    else { peopleList }
                }
            }
            .navigationTitle(store.state.activePeer == nil ? String(localized: "すれ違い") : (person(store.state.activePeer!)?.name ?? "AirTalk"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("近くで話す") { showRadar = true }
                        .disabled(store.state.activePeer != nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(Text("オンライン設定"))
                }
            }
            .sheet(isPresented: $showRadar) { DiscoveryView() }
            .sheet(isPresented: $showSettings) { settings }
            .confirmationDialog("この相手を通報・ブロックしますか？", isPresented: Binding(get: { reportTarget != nil }, set: { if !$0 { reportTarget = nil } }), titleVisibility: .visible) {
                Button("迷惑行為", role: .destructive) { report() }
                Button("不適切な内容", role: .destructive) { report() }
            } message: {
                Text("デモでは通報を送信せず、この相手との接続を解除します。会話本文は添付しません。")
            }
            .alert("デモ内でブロックしました", isPresented: $reportedNotice) {
                Button("閉じる", role: .cancel) { }
            } message: { Text("実際の通報は送信されていません。") }
            .onAppear {
                selection = DemoMode.scene == .onlineConnections ? 2 : (DemoMode.scene == .onlineInbox ? 1 : 0)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { store.state.endChat(); input = "" }
            }
        }
    }

    private var introduction: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "person.2.wave.2.fill").font(.system(size: 48)).symbolRenderingMode(.monochrome)
                Text("すれ違った、その先も。") .font(.largeTitle.bold())
                Text("近くで出会った人と、お互いが望んだときだけオンラインで話せます。今までのオフラインチャットは、そのまま無料です。")
                Label("相手を選んで、双方が承認", systemImage: "checkmark.shield")
                Label("会話の本文は、終了時に消去", systemImage: "bubble.left.and.bubble.right")
                Label("また話したい気持ちが一致したら、つながりを保存", systemImage: "person.crop.circle.badge.checkmark")
                Text("オンライン機能ではプロフィールと接続関係をサーバーで扱います。すれ違い検出は別途オンにする方式を検討しています。")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("18歳以上です（初版の提案）", isOn: $agreesAge)
                Toggle("オンラインで共有する情報を確認しました", isOn: $agreesProfile)
                Button("同意後の画面を試す") { store.state.optedIn = true }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!agreesAge || !agreesProfile)
                Text("これは同意画面の試作です。Appleでのサインインやアカウント作成はまだ行いません。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }

    private var peopleList: some View {
        VStack {
            Picker("表示する一覧", selection: $selection) {
                Text("すれ違い").tag(0)
                Text("リクエスト").tag(1)
                Text("つながり").tag(2)
            }.pickerStyle(.segmented).padding()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text(LocalizedStringKey(selection == 0 ? "過去24時間のすれ違い（デモ）" : (selection == 1 ? "会話は、承認してから" : "お互いに、また話したい人")))
                        .font(.headline)
                    let visible = store.state.people.filter { p in
                        let relation = store.state.relationship(p.id)
                        if selection == 2 { return store.state.connections.contains(p.id) }
                        if selection == 1 { return relation == .incoming || relation == .outgoing || relation == .accepted }
                        return relation == .encountered
                    }
                    if visible.isEmpty {
                        Text("まだ表示する相手はいません。近くでの会話から始めてみましょう。")
                            .foregroundStyle(.secondary).padding(.vertical)
                    }
                    ForEach(visible) { profile in profileCard(profile) }
                    Text("正確な場所・時刻・すれ違い回数は相手に表示しません。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
    }

    private func profileCard(_ profile: OnlinePreviewPerson) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: profile.symbol).font(.title).frame(width: 52, height: 52)
                    .background(.white.opacity(0.3), in: Circle())
                VStack(alignment: .leading) {
                    Text(profile.name).font(.title3.bold())
                    Text(LocalizedStringKey(profile.topic)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("ブロック", role: .destructive) { store.state.block(profile.id) }
                    Button("通報・ブロック", role: .destructive) { reportTarget = profile.id }
                } label: { Image(systemName: "ellipsis.circle").padding(8) }
                    .accessibilityLabel(Text("相手への操作"))
            }
            Text(LocalizedStringKey(profile.introduction))
            switch store.state.relationship(profile.id) {
            case .encountered:
                Button("話してみたい") { store.state.request(profile.id); selection = 1 }.buttonStyle(.borderedProminent)
            case .outgoing:
                Label("相手の承認を待っています", systemImage: "clock")
                Button("相手の承諾を再現（デモ）") { store.state.simulatePeerAcceptance(profile.id) }.font(.caption)
            case .incoming:
                HStack {
                    Button("承認する") { store.state.accept(profile.id) }.buttonStyle(.borderedProminent)
                    Button("見送る") { store.state.decline(profile.id) }.buttonStyle(.bordered)
                }
            case .connected:
                Button("もう一度話したい") { store.state.request(profile.id); selection = 1 }.buttonStyle(.borderedProminent)
            case .accepted:
                Button("会話を始める") { store.state.startChat(profile.id) }.buttonStyle(.borderedProminent)
            default: EmptyView()
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private func conversation(_ id: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("終了・バックグラウンド移行で本文が消えます")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("会話を終える", role: .destructive) { store.state.endChat(); input = "" }
            }.padding(.horizontal).padding(.top, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.state.messages) { message in
                            HStack {
                                if message.isMe { Spacer(minLength: 40) }
                                Text(message.text).padding(14)
                                    .background(message.isMe ? Color.purple.opacity(0.2) : Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
                                if !message.isMe { Spacer(minLength: 40) }
                            }.id(message.id)
                        }
                    }.padding()
                }.onChange(of: store.state.messages.count) { _, _ in
                    if let last = store.state.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if store.state.connections.contains(id) {
                    Label("お互いの希望が一致しました。つながりを保存しました。", systemImage: "checkmark.circle")
                } else {
                    Button(LocalizedStringKey(store.state.myReconnect.contains(id) ? "あなたの希望を受け付けました" : "また話したい")) { store.state.wantReconnect(id) }
                        .disabled(store.state.myReconnect.contains(id))
                    if store.state.myReconnect.contains(id) {
                        Button("相手の「また話したい」を再現（デモ）") { store.state.wantReconnect(id, fromPeer: true) }.font(.caption)
                    }
                }
                HStack {
                    Button("相手の返信を再現（デモ）") { store.state.send(String(localized: "いいですね。またお話ししましょう！"), isMe: false) }
                    Spacer()
                    Button("通報・ブロック", role: .destructive) { reportTarget = id }
                }.font(.caption)
            }.padding(.horizontal)
            HStack {
                TextField("メッセージ（デモ）", text: $input, axis: .vertical).lineLimit(1...4)
                    .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .onChange(of: input) { _, value in input = String(value.prefix(1000)) }
                Button { if store.state.send(input) { input = "" } } label: { Image(systemName: "arrow.up.circle.fill").font(.largeTitle) }
                    .accessibilityLabel(Text("デモで送信"))
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding()
        }
    }

    private var settings: some View {
        NavigationStack {
            List {
                Section("共有するもの（提案）") {
                    Text("ニックネーム・アイコン・興味・承認した接続関係")
                    Text("通常の会話本文はサーバーに保存しません。通報で送る情報は別途確認します。")
                }
                Section {
                    Button("デモのオンラインデータを削除", role: .destructive) { deleteConfirmation = true }
                    Text("この操作はデモの状態だけを消します。既存のプロフィール・購入情報には影響しません。")
                        .font(.caption)
                }
            }.navigationTitle("オンライン設定")
                .toolbar { Button("閉じる") { showSettings = false } }
                .confirmationDialog("デモのオンラインデータを削除しますか？", isPresented: $deleteConfirmation, titleVisibility: .visible) {
                    Button("削除", role: .destructive) { store.state.deleteAccount(); input = ""; showSettings = false }
                }
        }
    }

    private func person(_ id: String) -> OnlinePreviewPerson? { store.state.people.first { $0.id == id } }
    private func report() {
        if let id = reportTarget { store.state.reportAndBlock(id) }
        input = ""
        reportTarget = nil
        reportedNotice = true
    }
}
#endif
