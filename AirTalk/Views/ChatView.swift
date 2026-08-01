import SwiftUI
import MultipeerConnectivity
import UIKit

struct ChatView: View {
    let peerID: MCPeerID
    @EnvironmentObject var multipeerManager: MultipeerManager
    @EnvironmentObject var purchaseManager: PurchaseManager

    @State private var inputText = ""
    @State private var showDisconnectBanner = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var myProfile: UserProfile?
    @State private var reportTargetMessage: AirMessage?
    @State private var showBlockAlert = false
    @State private var showingPaywall = false

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

    private var availableReactions: [String] {
        purchaseManager.isPlusActive ? AirTalkPlus.allReactions : AirTalkPlus.freeReactions
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected, !text.isEmpty else { return }
        if multipeerManager.send(text: text, to: peerID) {
            inputText = ""
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func openReportMail(kind: SafetyReportKind, message: AirMessage? = nil) {
        guard let url = SafetyReport.mailURL(
            kind: kind,
            peerID: peerID,
            message: message,
            recentMessages: peerMessages
        ) else { return }
        UIApplication.shared.open(url)
    }

    private func blockAndReportPeer() {
        let recentMessages = peerMessages
        multipeerManager.block(peerID)
        if let url = SafetyReport.mailURL(
            kind: .block,
            peerID: peerID,
            message: nil,
            recentMessages: recentMessages
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                UIApplication.shared.open(url)
            }
        }
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
                                    MessageBubble(
                                        message: message,
                                        availableReactions: availableReactions,
                                        onReaction: { msg, reaction in
                                            multipeerManager.sendReaction(reaction, for: msg.id, to: peerID)
                                        },
                                        onReport: { msg in
                                            reportTargetMessage = msg
                                        }
                                    )
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
                        if purchaseManager.isPlusActive {
                            Menu {
                                ForEach(AirTalkPlus.icebreakers, id: \.self) { phrase in
                                    Button(phrase) {
                                        inputText = phrase
                                    }
                                }
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 34, height: 34)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        } else {
                            Button {
                                showingPaywall = true
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.primary)
                                            .offset(x: 10, y: 10)
                                    )
                            }
                        }

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
                        HStack(spacing: 5) {
                            Text(peerID.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            if peerProfile?.isHostBadgeEnabled == true {
                                HostBadge()
                            }
                        }
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
                    HStack(spacing: 8) {
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

                        Menu {
                            Button(role: .destructive) {
                                showBlockAlert = true
                            } label: {
                                Label("このユーザーをブロックして通報", systemImage: "hand.raised.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .onAppear {
            myProfile = DemoMode.isEnabled ? DemoData.myProfile : UserProfile.load()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .environmentObject(purchaseManager)
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
        .alert("メッセージを通報しますか？", isPresented: Binding(
            get: { reportTargetMessage != nil },
            set: { if !$0 { reportTargetMessage = nil } }
        )) {
            Button("通報する", role: .destructive) {
                if let message = reportTargetMessage {
                    openReportMail(kind: .message, message: message)
                }
                reportTargetMessage = nil
            }
            Button("キャンセル", role: .cancel) {
                reportTargetMessage = nil
            }
        } message: {
            Text("開発者へ不適切な内容を通知するメール作成画面を開きます。")
        }
        .alert("このユーザーをブロックしますか？", isPresented: $showBlockAlert) {
            Button("ブロックして通報", role: .destructive) {
                blockAndReportPeer()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("このユーザーとの会話をすぐに削除し、今後レーダーと招待に表示しません。開発者へ通報メールも作成します。")
        }
    }
}
