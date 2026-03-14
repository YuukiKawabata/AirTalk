import SwiftUI

struct ProfileCard: View {
    let profile: UserProfile
    var isConnected: Bool = false
    var isInviting: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.iconID)
                .font(.title2)
                .symbolRenderingMode(.monochrome)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(.medium))

                if isInviting {
                    Text("承認待ち...")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else if isConnected {
                    Text("チャット中")
                        .font(.caption)
                        .foregroundColor(.primary)
                } else if !profile.status.isEmpty {
                    Text(profile.status)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            if isInviting {
                ProgressView()
            } else if isConnected {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.primary, lineWidth: isConnected ? 2 : 1)
        )
    }
}
