import SwiftUI
import MultipeerConnectivity

struct ChatView: View {
    let peerID: MCPeerID
    @EnvironmentObject var multipeerManager: MultipeerManager

    @State private var inputText = ""
    @State private var showDisconnectBanner = false
    @State private var dismissTask: Task<Void, Never>?

    private var isConnected: Bool {
        multipeerManager.connectedPeers.contains(peerID)
    }

    private var peerMessages: [AirMessage] {
        multipeerManager.messages[peerID] ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showDisconnectBanner {
                    Text("通信が途絶えました。メッセージは破棄されます。")
                        .font(.caption)
                        .foregroundColor(Color(UIColor.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.primary)
                        .transition(.move(edge: .top))
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(peerMessages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                                    .transition(.scale)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: peerMessages.count) { _, _ in
                        if let lastID = peerMessages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("メッセージ", text: $inputText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.primary, lineWidth: 1)
                        )

                    Button {
                        let text = inputText.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        multipeerManager.send(text: text, to: peerID)
                        inputText = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.monochrome)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle(peerID.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !showDisconnectBanner {
                        Button {
                            multipeerManager.closeChat()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("戻る")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Text("●")
                            .font(.caption2)
                        Text(isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                    }
                    .foregroundColor(.primary)
                }
            }
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
