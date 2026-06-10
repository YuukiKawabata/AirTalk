import SwiftUI

struct MessageBubble: View {
    let message: AirMessage
    var onReaction: ((AirMessage, String) -> Void)?

    @State private var showReactionPicker = false
    private let reactions = ["❤️", "👍", "😂", "😮", "😢", "👏"]

    var body: some View {
        HStack {
            if message.isMe { Spacer() }

            ZStack(alignment: message.isMe ? .bottomTrailing : .bottomLeading) {
                VStack(alignment: message.isMe ? .trailing : .leading, spacing: 2) {
                    ZStack(alignment: message.isMe ? .bottomTrailing : .bottomLeading) {
                        Text(message.text)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundColor(message.isMe ? .white : .primary)
                            .background(
                                message.isMe ? Color.primary : Color.clear
                            )
                            .background(.ultraThinMaterial)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(message.isMe ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                            .onTapGesture(count: 2) {
                                if !message.isMe {
                                    withAnimation {
                                        showReactionPicker.toggle()
                                    }
                                }
                            }
                        
                        // リアクションの表示（バブル自体にはみ出るように配置）
                        if let reaction = message.reaction {
                            Text(reaction)
                                .font(.caption)
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                .offset(x: message.isMe ? -10 : 10, y: 15)
                        }
                    }

                    // タイムスタンプ（リアクションがある場合は上に少し余白を開ける）
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, message.reaction != nil ? 14 : 2)
                }
                
                // リアクションピッカー
                if showReactionPicker {
                    HStack(spacing: 8) {
                        ForEach(reactions, id: \.self) { reaction in
                            Text(reaction)
                                .font(.title3)
                                .onTapGesture {
                                    onReaction?(message, reaction)
                                    withAnimation { showReactionPicker = false }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .offset(y: -50)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isMe ? .trailing : .leading)
            .padding(.bottom, 4)

            if !message.isMe { Spacer() }
        }
    }
}
