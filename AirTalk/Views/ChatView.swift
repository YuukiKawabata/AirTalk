import SwiftUI
import MultipeerConnectivity

struct ChatView: View {
    let peerID: MCPeerID
    @EnvironmentObject var multipeerManager: MultipeerManager

    @State private var inputText = ""
    @State private var showDisconnectBanner = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var myProfile: UserProfile?

    private var isConnected: Bool {
        multipeerManager.connectedPeers.contains(peerID)
    }

    private var peerMessages: [AirMessage] {
        multipeerManager.messages[peerID] ?? []
    }

    /// 接続後に相手から受信したフルプロフィール（画像・テーマ含む）
    private var peerProfile: UserProfile? {
        multipeerManager.connectedPeerProfiles[peerID]
    }

    private var peerThemeColor: Color {
        ThemeColor(rawValue: peerProfile?.themeColor ?? "purple")?.color ?? .purple
    }

    private var canSend: Bool {
        isConnected && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected, !text.isEmpty else { return }
        multipeerManager.send(text: text, to: peerID)
        inputText = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackgroundView(themeColor: ThemeColor(rawValue: myProfile?.themeColor ?? "purple") ?? .purple)
                
                VStack(spacing: 0) {
                    if showDisconnectBanner {
                        Text("通信が途絶えました。メッセージは破棄されます。")
                            .font(.caption)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.7))
                            .background(.ultraThinMaterial)
                            .transition(.move(edge: .top))
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(peerMessages) { message in
                                    MessageBubble(message: message) { msg, reaction in
                                        multipeerManager.sendReaction(reaction, for: msg.id, to: peerID)
                                    }
                                    .id(message.id)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding()
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: peerMessages.count) { _, _ in
                            if let lastID = peerMessages.last?.id {
                                withAnimation {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                        }
                    }

                    // 入力エリア
                    HStack(spacing: 12) {
                        TextField("メッセージ", text: $inputText, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .disabled(!isConnected)
                            .onChange(of: inputText) { _, newValue in
                                if newValue.count > AirMessage.maxTextLength {
                                    inputText = String(newValue.prefix(AirMessage.maxTextLength))
                                }
                            }

                        Button {
                            sendMessage()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(canSend ? .primary : .gray)
                        }
                        .disabled(!canSend)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(
                        Color(UIColor.systemBackground).opacity(0.3)
                            .background(.ultraThinMaterial)
                            .ignoresSafeArea(edges: .bottom)
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        AvatarView(profile: peerProfile, size: 30, themeColor: peerThemeColor)
                        Text(peerID.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !showDisconnectBanner {
                        Button {
                            multipeerManager.closeChat()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("戻る")
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isConnected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                            .shadow(color: isConnected ? Color.green.opacity(0.5) : .clear, radius: 4)
                        Text(isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
            }
        }
        .onAppear {
            myProfile = UserProfile.load()
        }
        .onChange(of: isConnected) { _, connected in
            if !connected && !showDisconnectBanner {
                withAnimation {
                    showDisconnectBanner = true
                }
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        multipeerManager.closeChat()
                    }
                }
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }
}
