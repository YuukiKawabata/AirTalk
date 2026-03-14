import SwiftUI
import MultipeerConnectivity

struct DiscoveryView: View {
    @EnvironmentObject var multipeerManager: MultipeerManager
    @State private var showingProfileEditor = false
    @State private var showSwitchAlert = false
    @State private var switchTargetPeerID: MCPeerID?
    @State private var showInvitationAlert = false
    @State private var showDeclinedAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if multipeerManager.discoveredPeers.isEmpty {
                    VStack {
                        Spacer()
                        Text("周囲にユーザーがいません")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(multipeerManager.discoveredPeers, id: \.peerID) { peer in
                            let connected = multipeerManager.connectedPeers.contains(peer.peerID)
                            let inviting = multipeerManager.invitingPeerID == peer.peerID
                            ProfileCard(profile: peer.profile, isConnected: connected, isInviting: inviting)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .onTapGesture {
                                    handlePeerTap(peer.peerID)
                                }
                                .transition(.opacity)
                        }
                    }
                    .listStyle(.plain)
                    .animation(.default, value: multipeerManager.discoveredPeers.map(\.peerID))
                }
            }
            .navigationTitle("AirTalk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingProfileEditor = true
                    } label: {
                        Image(systemName: "gear")
                            .symbolRenderingMode(.monochrome)
                    }
                }
            }
            .fullScreenCover(item: $multipeerManager.activeChatPeerID) { peerID in
                ChatView(peerID: peerID)
                    .environmentObject(multipeerManager)
            }
        }
        .sheet(isPresented: $showingProfileEditor) {
            ProfileEditorSheet()
                .environmentObject(multipeerManager)
        }
        .alert("チャット相手を切り替えますか？", isPresented: $showSwitchAlert) {
            Button("切り替える") {
                if let target = switchTargetPeerID {
                    for peer in multipeerManager.connectedPeers {
                        multipeerManager.disconnect(from: peer)
                    }
                    multipeerManager.invitePeer(target)
                }
            }
            Button("キャンセル", role: .cancel) {
                switchTargetPeerID = nil
            }
        } message: {
            Text("現在のチャットは終了し、メッセージは破棄されます。")
        }
        .alert("チャットリクエスト", isPresented: $showInvitationAlert) {
            Button("承認") {
                multipeerManager.acceptInvitation()
            }
            Button("拒否", role: .cancel) {
                multipeerManager.declineInvitation()
            }
        } message: {
            if let invitation = multipeerManager.pendingInvitation {
                Text("\(invitation.name) さんがチャットを開始したいです")
            }
        }
        .onChange(of: multipeerManager.pendingInvitation?.peerID) { _, newValue in
            showInvitationAlert = newValue != nil
        }
        .alert("リクエスト拒否", isPresented: $showDeclinedAlert) {
            Button("OK") {
                multipeerManager.declinedByPeerName = nil
            }
        } message: {
            if let name = multipeerManager.declinedByPeerName {
                Text("\(name) さんにリクエストが拒否されました")
            }
        }
        .onChange(of: multipeerManager.declinedByPeerName) { _, newValue in
            showDeclinedAlert = newValue != nil
        }
    }

    private func handlePeerTap(_ peerID: MCPeerID) {
        if multipeerManager.connectedPeers.contains(peerID) {
            multipeerManager.openChat(with: peerID)
        } else if multipeerManager.connectedPeers.isEmpty {
            multipeerManager.invitePeer(peerID)
        } else {
            switchTargetPeerID = peerID
            showSwitchAlert = true
        }
    }
}

// MARK: - MCPeerID + Identifiable

extension MCPeerID: @retroactive Identifiable {
    public var id: String { displayName }
}

// MARK: - Profile Editor Sheet

struct ProfileEditorSheet: View {
    @EnvironmentObject var multipeerManager: MultipeerManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var status: String = ""
    @State private var selectedIconID: String = "person.fill"

    private let iconOptions = [
        "person.fill", "star.fill", "flame.fill", "heart.fill", "bolt.fill",
        "leaf.fill", "moon.fill", "sun.max.fill", "cloud.fill", "music.note"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("ニックネーム", text: $name)
                    .textFieldStyle(.plain)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.primary, lineWidth: 1)
                    )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(iconOptions, id: \.self) { iconID in
                            Image(systemName: iconID)
                                .font(.title2)
                                .frame(width: 48, height: 48)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 0)
                                        .stroke(Color.primary, lineWidth: selectedIconID == iconID ? 2 : 1)
                                )
                                .background(selectedIconID == iconID ? Color.primary.opacity(0.1) : Color.clear)
                                .onTapGesture {
                                    selectedIconID = iconID
                                }
                        }
                    }
                    .padding(.horizontal, 1)
                }

                TextField("ひとこと", text: $status)
                    .textFieldStyle(.plain)
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.primary, lineWidth: 1)
                    )

                Spacer()
            }
            .padding()
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let profile = UserProfile(name: name, status: status, iconID: selectedIconID)
                        profile.save()
                        multipeerManager.updateProfile(profile)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let profile = UserProfile.load() {
                name = profile.name
                status = profile.status
                selectedIconID = profile.iconID
            }
        }
    }
}
