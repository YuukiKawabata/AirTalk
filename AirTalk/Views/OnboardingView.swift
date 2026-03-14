import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var multipeerManager: MultipeerManager

    @State private var name = ""
    @State private var status = ""
    @State private var selectedIconID = "person.fill"

    private let iconOptions = [
        "person.fill", "star.fill", "flame.fill", "heart.fill", "bolt.fill",
        "leaf.fill", "moon.fill", "sun.max.fill", "cloud.fill", "music.note"
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("AirTalk")
                .font(.system(size: 42, weight: .bold))

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
            }
            .padding(.horizontal)

            Button {
                let profile = UserProfile(name: name, status: status, iconID: selectedIconID)
                profile.save()
                multipeerManager.updateProfile(profile)
                hasCompletedOnboarding = true
            } label: {
                Text("はじめる")
                    .font(.headline)
                    .foregroundColor(Color(UIColor.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        Capsule().fill(Color.primary)
                    )
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1.0)
            .padding(.horizontal)

            Spacer()
        }
    }
}
