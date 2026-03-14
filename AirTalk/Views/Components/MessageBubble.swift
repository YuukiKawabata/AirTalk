import SwiftUI

struct MessageBubble: View {
    let message: AirMessage

    var body: some View {
        HStack {
            if message.isMe { Spacer() }

            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundColor(message.isMe ? Color(UIColor.systemBackground) : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(message.isMe ? Color.primary : Color(UIColor.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(message.isMe ? Color.clear : Color.primary, lineWidth: 1)
                    )

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: message.isMe ? .trailing : .leading)

            if !message.isMe { Spacer() }
        }
    }
}
