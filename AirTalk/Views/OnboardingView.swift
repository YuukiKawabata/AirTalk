import SwiftUI
import PhotosUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var multipeerManager: MultipeerManager
    @AppStorage("hasAcceptedEULA") private var hasAcceptedEULA = false

    @State private var name = ""
    @State private var status = ""
    @State private var selectedIconID = "person.fill"
    @State private var selectedTheme: ThemeColor = .purple
    @State private var hasCheckedEULA = false
    @State private var showingTerms = false
    
    // カスタム画像用
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var customImageData: Data?

    private let iconOptions = [
        "person.fill", "star.fill", "flame.fill", "heart.fill", "bolt.fill",
        "leaf.fill", "moon.fill", "sun.max.fill", "cloud.fill", "music.note"
    ]

    var body: some View {
        ZStack {
            AuroraBackgroundView(themeColor: selectedTheme)
            
            VStack(spacing: 32) {
                Spacer()

                Text("AirTalk")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.primary)

                VStack(spacing: 24) {
                    // 名前の入力
                    TextField("ニックネーム", text: $name)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )

                    // アイコン選択 & カスタム画像
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            // PhotosPicker
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                if let data = customImageData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle().stroke(selectedIconID.isEmpty ? selectedTheme.color : Color.clear, lineWidth: selectedIconID.isEmpty ? 2 : 0)
                                        )
                                } else {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.title2)
                                        .frame(width: 56, height: 56)
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                        )
                                        .foregroundColor(.primary)
                                }
                            }
                            .onChange(of: selectedPhotoItem) { _, newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data) {
                                        await MainActor.run {
                                            customImageData = image.compressedThumbnailData()
                                            selectedIconID = "" // カスタム画像選択時はシステムアイコン選択を解除
                                        }
                                    }
                                }
                            }
                        
                            ForEach(iconOptions, id: \.self) { iconID in
                                Image(systemName: iconID)
                                    .font(.title2)
                                    .frame(width: 56, height: 56)
                                    .background(selectedIconID == iconID ? selectedTheme.color.opacity(0.2) : Color.clear)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(selectedIconID == iconID ? selectedTheme.color : Color.primary.opacity(0.1), lineWidth: selectedIconID == iconID ? 2 : 1)
                                    )
                                    .onTapGesture {
                                        withAnimation { 
                                            selectedIconID = iconID 
                                            customImageData = nil // システムアイコン選択時はカスタム画像を解除
                                            selectedPhotoItem = nil
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }

                    // テーマカラー選択
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(AirTalkPlus.freeThemes) { theme in
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedTheme == theme ? 3 : 0)
                                            .padding(-4)
                                    )
                                    .onTapGesture {
                                        withAnimation { selectedTheme = theme }
                                    }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    }

                    // ステータス入力
                    TextField("ひとこと", text: $status)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Toggle(isOn: $hasCheckedEULA) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("利用規約 / EULA に同意します")
                                .font(.subheadline.weight(.semibold))
                            Text("不適切な内容や迷惑行為を許容しないポリシーを含みます。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkboxLike(theme: selectedTheme.color))

                    Button {
                        showingTerms = true
                    } label: {
                        Text("利用規約を確認")
                            .font(.caption.weight(.semibold))
                            .underline()
                    }
                    .foregroundColor(.primary)
                }
                .padding(.horizontal, 24)

                Button {
                    let profile = UserProfile(name: name, status: status, iconID: selectedIconID, themeColor: selectedTheme.rawValue, imageData: customImageData)
                    profile.save()
                    multipeerManager.updateProfile(profile)
                    hasAcceptedEULA = true
                    hasCompletedOnboarding = true
                } label: {
                    Text("はじめる")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedTheme.color)
                        .cornerRadius(16)
                        .shadow(color: selectedTheme.color.opacity(0.5), radius: 10, x: 0, y: 5)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !hasCheckedEULA)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || !hasCheckedEULA ? 0.4 : 1.0)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .onAppear {
            // スクショ撮影用: 空フォームではなくデモプロフィールを入れて見栄えを良くする
            if DemoMode.isEnabled {
                let demo = DemoData.myProfile
                name = demo.name
                status = demo.status
                selectedIconID = demo.iconID
                selectedTheme = ThemeColor(rawValue: demo.themeColor) ?? .purple
                hasCheckedEULA = true
            } else if let profile = UserProfile.load(), name.isEmpty {
                name = profile.name
                status = profile.status
                selectedIconID = profile.iconID
                selectedTheme = ThemeColor(rawValue: profile.themeColor) ?? .purple
                customImageData = profile.imageData
            }
        }
        .sheet(isPresented: $showingTerms) {
            TermsOfUseView()
        }
    }
}

private struct CheckboxToggleStyle: ToggleStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(configuration.isOn ? tint : .secondary)
                configuration.label
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private extension ToggleStyle where Self == CheckboxToggleStyle {
    static func checkboxLike(theme: Color) -> CheckboxToggleStyle {
        CheckboxToggleStyle(tint: theme)
    }
}
