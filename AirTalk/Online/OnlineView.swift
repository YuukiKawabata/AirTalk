import AuthenticationServices
import SwiftUI

struct OnlineView: View {
  @EnvironmentObject private var store: OnlineStore
  @Environment(\.scenePhase) private var phase
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var intro = ""
  @State private var adult = false
  @State private var consent = false
  @State private var showingPolicy = false
  @State private var draft = ""
  @State private var tab = 0
  @State private var confirmDelete = false
  @State private var reportPeer: OnlinePerson?

  var body: some View {
    NavigationStack {
      Group {
        if store.activeRoom != nil {
          chat
        } else if !store.signedIn {
          login
        } else if store.profile?.consent != true {
          onboarding
        } else {
          directory
        }
      }
      .navigationTitle("すれ違い")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("閉じる") {
            draft = ""
            store.end()
            dismiss()
          }
        }
        if store.signedIn {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Button("更新") { Task { await store.load() } }
              if store.profile?.consent == true {
                Button(LocalizedStringKey(store.profile?.ble == true ? "すれ違い検出を停止" : "すれ違い検出を開始")) {
                  Task { await store.setEncounters(store.profile?.ble != true) }
                }
                Button("リクエスト通知を許可") { Task { await store.enableNotifications() } }
              }
              Button("オンライン利用条件と問い合わせ") { showingPolicy = true }
              Button("サインアウト") { Task { await store.logout(delete: false) } }
              Button("アカウントを削除", role: .destructive) { confirmDelete = true }
            } label: {
              Image(systemName: "gearshape")
            }
          }
        }
      }
      .sheet(isPresented: $showingPolicy) { OnlinePolicyView() }
      .overlay {
        if store.busy {
          ProgressView().padding().background(
            .regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
      }
      .alert(
        "お知らせ",
        isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
      ) {
        Button("OK") { store.error = nil }
      } message: {
        Text(store.error ?? "")
      }
      .alert("すれ違い検出とリクエスト通知をオンにしますか？", isPresented: $store.offerSetup) {
        Button("オンにする") { Task { await store.enableRecommended() } }
        Button("あとで", role: .cancel) {}
      } message: {
        Text("近くですれ違った参加者を記録し、会話のリクエストが届いたときにお知らせします。右上の歯車ボタンからいつでも変更できます。通知はiPhoneの設定アプリでもオフにできます。")
      }
      .confirmationDialog(
        "アカウントとつながりを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible
      ) {
        Button("アカウントを削除", role: .destructive) { Task { await store.logout(delete: true) } }
      } message: {
        Text("プロフィールとつながりが削除され、会話も終了します。通報対応の記録は所定の期間保持されます。")
      }
      .confirmationDialog(
        "通報する理由",
        isPresented: Binding(get: { reportPeer != nil }, set: { if !$0 { reportPeer = nil } }),
        titleVisibility: .visible
      ) {
        ForEach(["harassment", "sexual", "spam", "underage", "other"], id: \.self) { reason in
          Button(reasonTitle(reason)) {
            if let peer = reportPeer { Task { await store.block(peer, reason: reason) } }
            reportPeer = nil
          }
        }
      } message: {
        Text("理由を送信してブロックします。会話本文は送信しません。")
      }
    }
    .task {
      #if DEBUG
        if store.client?.configuration.local == true,
          let name = UserDefaults.standard.string(forKey: "onlineTestName")
        {
          await store.localSignIn(name: name)
          if UserDefaults.standard.bool(forKey: "onlineTestJoin"),
            let request = store.requests.first(where: { $0.status == "accepted" })
          {
            await store.start(request)
          }
        } else {
          await store.load()
        }
      #else
        await store.load()
      #endif
    }
    .onChange(of: store.activeRoom?.id) { _, _ in draft = "" }
    .onChange(of: phase) { _, value in
      if value != .active {
        draft = ""
        store.end()
      }
    }
    .onAppear { store.screenVisible = true }
    .onDisappear {
      store.screenVisible = false
      draft = ""
      store.end()
    }
  }
  private var login: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Image(systemName: "person.2.wave.2").font(.largeTitle)
        Text("すれ違いから、もう一度話そう。").font(.title2.bold())
        Text("Appleでサインインすると、近くで出会った相手と、お互いが承認したときだけ話せます。")
        privacy
        if store.client == nil {
          Text("オンライン検証環境が設定されていません。").foregroundStyle(.secondary)
        } else if store.client?.configuration.local == true {
          #if DEBUG
            Text("ローカル開発環境：Apple認証を使用しません。").font(.caption)
            TextField("検証用の名前", text: $name).textFieldStyle(.roundedBorder)
            Button("ローカル検証に入る") { Task { await store.localSignIn(name: name) } }.buttonStyle(
              .borderedProminent
            ).disabled(name.isEmpty || store.busy)
          #endif
        } else {
          if let challenge = store.challenge {
            SignInWithAppleButton(.signIn) { request in
              request.requestedScopes = []
              request.nonce = challenge.nonce
            } onCompletion: { result in
              Task { await store.signIn(result) }
            }.frame(height: 48).disabled(store.busy)
          } else {
            Button("Appleでサインインする準備") { Task { await store.prepareLogin() } }.buttonStyle(
              .borderedProminent
            ).disabled(store.busy)
          }
        }
      }.padding(24)
    }
    // Fetch a fresh challenge on open and after every failed attempt.
    .task(id: store.challenge == nil) {
      if store.challenge == nil, store.client?.configuration.local == false { await store.prepareLogin() }
    }
  }
  private var privacy: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("近くのチャットは、これまでどおり登録不要です。")
      Text("オンラインではプロフィール・申請・つながりをサーバーに保存します。会話本文は保存しません。通信路は暗号化しますが、E2EEではありません。")
      Text("通報理由は90日保持します。アカウント削除後もバックアップには一定期間残る場合があります。")
      Text("Bluetooth検出は任意です。位置情報を取得せず、常時の発見や距離は保証しません。強制終了中は検出できません。")
      Button("オンライン利用条件と問い合わせ") { showingPolicy = true }
    }.font(.footnote).foregroundStyle(.secondary)
  }
  private var onboarding: some View {
    Form {
      Section {
        TextField("ニックネーム", text: $name)
        TextField("ひとこと", text: $intro)
      }
      Section {
        privacy
        Toggle("18歳以上です", isOn: $adult)
        Toggle("オンラインで共有される情報に同意します", isOn: $consent)
      }
      Section {
        Button("オンライン機能を始める") { Task { await store.consent(name: name, intro: intro) } }.disabled(
          !adult || !consent || name.trimmingCharacters(in: .whitespaces).isEmpty
            || name.utf8.count > 48 || intro.utf8.count > 120 || store.busy)
      }
    }.onAppear {
      name = store.profile?.name ?? ""
      intro = store.profile?.intro ?? ""
    }
  }
  private var directory: some View {
    VStack(spacing: 0) {
      Picker("表示", selection: $tab) {
        Text("すれ違い").tag(0)
        Text("リクエスト").tag(1)
        Text("つながり").tag(2)
      }.pickerStyle(.segmented).padding()
      List {
        if !store.rooms.isEmpty {
          Section("進行中の会話") {
            ForEach(store.rooms) { room in
              Button {
                Task { await store.join(room) }
              } label: {
                Label(room.peer.name, systemImage: "bubble.left.and.bubble.right")
              }
            }
          }
        }
        if tab == 0 {
          Section {
            ForEach(store.people) { person in
              personRow(person) { Button("話してみたい") { Task { await store.request(person) } } }
            }
          }
          if store.people.isEmpty { emptyState }
          Section {
            Text("すれ違いは24時間で消えます。検出を有効にして、友だちとアプリを開いてみましょう。").font(.footnote).foregroundStyle(
              .secondary)
          }
        } else if tab == 1 {
          ForEach(store.requests.filter { $0.status == "pending" || $0.status == "accepted" }) {
            request in
            personRow(request.peer) {
              if request.status == "accepted" {
                Button("会話を始める") { Task { await store.start(request) } }
              } else if request.to == store.profile?.id {
                HStack {
                  Button("承認する") { Task { await store.respond(request, accept: true) } }
                  Button("見送る") { Task { await store.respond(request, accept: false) } }
                }
              } else {
                Text("承認を待っています").font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          if store.requests.isEmpty { emptyState }
        } else {
          ForEach(store.connections) { person in
            personRow(person) {
              HStack {
                Button("話してみたい") { Task { await store.request(person) } }
                Button("つながりを解除", role: .destructive) {
                  Task { await store.removeConnection(person) }
                }
              }
            }
          }
          if store.connections.isEmpty { Text("会話中に双方が「また話したい」を選ぶと、ここにつながりが残ります。") }
        }
      }.listStyle(.insetGrouped).refreshable { await store.load() }
    }
  }
  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("まだ相手がいません").font(.headline)
      Text("近くの友だちと試したり、あとで更新してみましょう。").foregroundStyle(.secondary)
    }.padding(.vertical)
  }
  private func personRow<Actions: View>(_ person: OnlinePerson, @ViewBuilder actions: () -> Actions)
    -> some View
  {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: person.icon)
        Text(person.name).font(.headline)
        Spacer()
        safetyMenu(person)
      }
      if !person.intro.isEmpty { Text(person.intro).font(.subheadline) }
      actions().buttonStyle(.bordered)
    }.padding(.vertical, 6)
  }
  private func safetyMenu(_ person: OnlinePerson) -> some View {
    Menu {
      Button("ブロック", role: .destructive) { Task { await store.block(person) } }
      Button("通報してブロック", role: .destructive) { reportPeer = person }
    } label: {
      Image(systemName: "ellipsis.circle")
    }.accessibilityLabel("安全メニュー")
  }
  private var chat: some View {
    VStack(spacing: 12) {
      if let room = store.activeRoom {
        HStack {
          Text(room.peer.name).font(.headline)
          Spacer()
          safetyMenu(room.peer)
          Button("会話を終了", role: .destructive) {
            draft = ""
            store.end()
          }
        }.padding(.horizontal)
      }
      if !store.peerReady {
        Text("相手が会話を開くのを待っています").font(.subheadline).foregroundStyle(.secondary)
      }
      Text("画面を離れると会話は終了し、メッセージが消えます。").font(.caption).foregroundStyle(.secondary)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(store.messages) { message in
              HStack {
                if message.isMe { Spacer(minLength: 40) }
                Text(message.text).padding(12).background(
                  message.isMe ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                  in: RoundedRectangle(cornerRadius: 16))
                if !message.isMe { Spacer(minLength: 40) }
              }.id(message.id)
            }
          }.padding()
        }.onChange(of: store.messages.count) { _, _ in
          if let id = store.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
        }
      }
      Button(LocalizedStringKey(store.hasReconnectIntent ? "相手の希望も一致するとつながります" : "また話したい")) {
        Task { await store.reconnect() }
      }.disabled(store.hasReconnectIntent || store.busy).font(.footnote)
      HStack {
        TextField("メッセージ", text: $draft, axis: .vertical).lineLimit(1...4).textFieldStyle(
          .roundedBorder)
        Button {
          let text = draft
          draft = ""
          Task { await store.send(text) }
        } label: {
          Image(systemName: "arrow.up.circle.fill").font(.title)
        }.disabled(
          !store.peerReady || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.utf8.count > 4000
            || draft.unicodeScalars.count > 1000)
      }.padding()
    }
  }
  private func reasonTitle(_ code: String) -> String {
    switch code {
    case "harassment": return String(localized: "嫌がらせ")
    case "sexual": return String(localized: "性的な内容")
    case "spam": return String(localized: "迷惑行為・宣伝")
    case "underage": return String(localized: "年齢に関する懸念")
    default: return String(localized: "その他")
    }
  }
}
