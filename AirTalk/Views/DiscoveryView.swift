import SwiftUI
import MultipeerConnectivity
import PhotosUI

struct DiscoveryView: View {
    @EnvironmentObject var multipeerManager: MultipeerManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @State private var showingProfileEditor = false
    @State private var showSwitchAlert = false
    @State private var switchTargetPeerID: MCPeerID?
    @State private var showInvitationAlert = false
    @State private var showDeclinedAlert = false
    
    @State private var myProfile: UserProfile?

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackgroundView(themeColor: ThemeColor(rawValue: myProfile?.themeColor ?? "purple") ?? .purple)
                
                RadarView(
                    peers: multipeerManager.discoveredPeers,
                    myProfile: myProfile,
                    permissionDenied: multipeerManager.permissionDenied,
                    onPeerTap: handlePeerTap,
                    onRescan: { multipeerManager.restartDiscovery() }
                )
            }
            .navigationTitle("AirTalk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingProfileEditor = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .fullScreenCover(item: $multipeerManager.activeChatPeerID) { peerID in
                ChatView(peerID: peerID)
                    .environmentObject(multipeerManager)
                    .environmentObject(purchaseManager)
            }
        }
        .onAppear {
            myProfile = DemoMode.isEnabled ? DemoData.myProfile : UserProfile.load()
            if DemoMode.isEnabled {
                // デモデータを注入（レーダー／チャット／着信）
                multipeerManager.loadDemoData(scene: DemoMode.scene)
                // 着信シーンはリクエストのアラートを確実に表示する
                if DemoMode.scene == .invite {
                    showInvitationAlert = true
                }
            }
        }
        .sheet(isPresented: $showingProfileEditor) {
            ProfileEditorSheet()
                .environmentObject(multipeerManager)
                .environmentObject(purchaseManager)
                .onDisappear {
                    myProfile = UserProfile.load()
                }
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

// MARK: - Avatar View (Helper)
struct AvatarView: View {
    let profile: UserProfile?
    let size: CGFloat
    let themeColor: Color

    private var frame: ProfileFrame {
        ProfileFrame(rawValue: profile?.profileFrameID ?? ProfileFrame.none.rawValue) ?? .none
    }

    private var ringColor: Color {
        frame == .none ? themeColor : frame.color
    }
    
    var body: some View {
        Group {
            if let data = profile?.imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: profile?.iconID ?? "person.fill")
                    .font(.system(size: size * 0.45))
                    .frame(width: size, height: size)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .overlay(
            Circle().stroke(ringColor, lineWidth: frame == .none ? 2 : 3)
        )
        .overlay {
            if frame != .none {
                Circle()
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    .padding(-5)
            }
        }
        .shadow(color: ringColor.opacity(0.35), radius: size * 0.18)
    }
}

struct HostBadge: View {
    var body: some View {
        Text("HOST")
            .font(.system(size: 9, weight: .black))
            .foregroundColor(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.16), lineWidth: 1)
            )
    }
}

// MARK: - Radar View

struct RadarView: View {
    let peers: [DiscoveredPeer]
    let myProfile: UserProfile?
    var permissionDenied: Bool = false
    let onPeerTap: (MCPeerID) -> Void
    var onRescan: () -> Void = {}

    @State private var rippleScale: CGFloat = 0.5
    @State private var rippleOpacity: Double = 1.0
    /// 一定時間ピアが見つからないときに「近くに誰もいない」案内へ切り替えるフラグ。
    /// 永久に回り続けるスピナーが「ハング」に見えるのを避けるための表示制御。
    @State private var searchTimedOut = false

    /// この秒数ピアが0件のままなら、探索中スピナーから空状態案内へ切り替える。
    private let noPeersTimeout: Duration = .seconds(12)

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // Ripple Effects
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        .scaleEffect(rippleScale + CGFloat(i) * 0.5)
                        .opacity(rippleOpacity - Double(i) * 0.3)
                }

                // My Avatar in Center
                VStack(spacing: 8) {
                    let theme = ThemeColor(rawValue: myProfile?.themeColor ?? "purple")?.color ?? .purple
                    AvatarView(profile: myProfile, size: 64, themeColor: theme)

                    VStack(spacing: 4) {
                        Text("あなた")
                            .font(.caption)
                            .fontWeight(.bold)
                        if myProfile?.isHostBadgeEnabled == true {
                            HostBadge()
                        }
                    }
                }
                .position(center)
                .zIndex(10)

                // 状態メッセージ（権限拒否 / 探索中）— ピアがいない時のみ
                if peers.isEmpty {
                    statusOverlay
                        .position(x: center.x, y: geometry.size.height - 80)
                        .zIndex(20)
                }

                // Peers
                ForEach(Array(peers.enumerated()), id: \.element.peerID) { index, peer in
                    let angle = Double(index) * (360.0 / Double(peers.count == 0 ? 1 : peers.count))
                    let radius = geometry.size.width * 0.35
                    let position = getPosition(center: center, radius: radius, angle: angle)
                    let theme = ThemeColor(rawValue: peer.profile.themeColor) ?? .purple
                    
                    VStack(spacing: 8) {
                        AvatarView(profile: peer.profile, size: 56, themeColor: theme.color)
                        
                        VStack(spacing: 4) {
                            Text(peer.profile.name)
                                .font(.caption)
                                .bold()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                            if peer.profile.isHostBadgeEnabled {
                                HostBadge()
                            }
                        }
                    }
                    .position(position)
                    .onTapGesture {
                        onPeerTap(peer.peerID)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: peers.map(\.peerID))
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    rippleScale = 1.5
                    rippleOpacity = 0.0
                }
            }
            // ピアの有無が変わるたびにタイマーをリセットする。
            // 0件のまま noPeersTimeout 経過したら空状態案内へ切り替える。
            .task(id: peers.isEmpty) {
                guard peers.isEmpty else {
                    searchTimedOut = false
                    return
                }
                searchTimedOut = false
                try? await Task.sleep(for: noPeersTimeout)
                if !Task.isCancelled {
                    searchTimedOut = true
                }
            }
        }
    }
    
    @ViewBuilder
    private var statusOverlay: some View {
        if permissionDenied {
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.title2)
                Text("近くのデバイスに接続できません")
                    .font(.subheadline.weight(.semibold))
                Text("「設定」でローカルネットワークと\nBluetoothの許可をオンにしてください")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("設定を開く")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(20)
            .frame(maxWidth: 300)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        } else if searchTimedOut {
            // 近くに誰もいない状態。探索は継続中だがハングに見えないよう案内を出す。
            VStack(spacing: 12) {
                Image(systemName: "person.2.slash")
                    .font(.title2)
                Text("近くにAirTalkユーザーがいません")
                    .font(.subheadline.weight(.semibold))
                Text("AirTalkは半径50m以内にいる相手とつながります。\n2台以上の端末で近くにいる人とお試しください。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    searchTimedOut = false
                    onRescan()
                } label: {
                    Label("もう一度さがす", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(20)
            .frame(maxWidth: 300)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text("周囲のユーザーを探しています…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func getPosition(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let x = center.x + radius * CGFloat(cos(angle * .pi / 180))
        let y = center.y + radius * CGFloat(sin(angle * .pi / 180))
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Profile Editor Sheet

struct ProfileEditorSheet: View {
    @EnvironmentObject var multipeerManager: MultipeerManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasAcceptedEULA") private var hasAcceptedEULA = false

    @State private var name: String = ""
    @State private var status: String = ""
    @State private var selectedIconID: String = "person.fill"
    @State private var selectedTheme: ThemeColor = .purple
    @State private var isHostBadgeEnabled = false
    @State private var selectedFrame: ProfileFrame = .none
    @State private var savedPresets: [ProfilePreset] = []
    @State private var showDeleteConfirm = false
    @State private var showDeleteComplete = false
    @State private var showingPaywall = false
    
    // カスタム画像用
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var customImageData: Data?

    private let iconOptions = [
        "person.fill", "star.fill", "flame.fill", "heart.fill", "bolt.fill",
        "leaf.fill", "moon.fill", "sun.max.fill", "cloud.fill", "music.note"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackgroundView(themeColor: selectedTheme)
                
                ScrollView {
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
                                            customImageData = nil
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
                            ForEach(ThemeColor.allCases) { theme in
                                let isLocked = AirTalkPlus.isPremiumTheme(theme) && !purchaseManager.isPlusActive
                                ZStack {
                                    Circle()
                                        .fill(theme.color)
                                        .frame(width: 44, height: 44)
                                        .opacity(isLocked ? 0.45 : 1)
                                    if isLocked {
                                        Image(systemName: "lock.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(.primary)
                                    }
                                }
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedTheme == theme ? 3 : 0)
                                        .padding(-4)
                                )
                                .onTapGesture {
                                    guard !isLocked else {
                                        showingPaywall = true
                                        return
                                    }
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

                    plusSection

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("アカウントを削除", systemImage: "trash")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }

                        Text("プロフィール、ブロックリスト、現在の会話など、この端末内のAirTalkデータを完全に削除します。AirTalkはサーバーアカウントを作成しません。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    }
                    .padding()
                    .padding(.top, 20)
                }
            }
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let profile = buildProfileForSave()
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
                customImageData = profile.imageData
                isHostBadgeEnabled = purchaseManager.isPlusActive && profile.isHostBadgeEnabled
                selectedFrame = purchaseManager.isPlusActive ? profile.selectedFrame : .none
                if let theme = ThemeColor(rawValue: profile.themeColor) {
                    selectedTheme = purchaseManager.isPlusActive || !AirTalkPlus.isPremiumTheme(theme) ? theme : .purple
                }
            }
            savedPresets = ProfilePresetStore.load()
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .environmentObject(purchaseManager)
        }
        .onChange(of: purchaseManager.isPlusActive) { _, isPlusActive in
            if !isPlusActive {
                if AirTalkPlus.isPremiumTheme(selectedTheme) {
                    selectedTheme = .purple
                }
                isHostBadgeEnabled = false
                selectedFrame = .none
            }
        }
        .alert("アカウントを削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) {
                multipeerManager.deleteLocalAccountData()
                showDeleteComplete = true
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("プロフィールとローカルデータを完全に削除します。この操作は取り消せません。")
        }
        .alert("アカウント削除が完了しました", isPresented: $showDeleteComplete) {
            Button("OK") {
                hasAcceptedEULA = false
                hasCompletedOnboarding = false
                dismiss()
            }
        } message: {
            Text("端末内のプロフィールとAirTalkデータを削除しました。")
        }
    }

    private var plusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("AirTalk Plus", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if purchaseManager.isPlusActive {
                    Text("有効")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                } else {
                    Button("詳細") {
                        showingPaywall = true
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if purchaseManager.isPlusActive {
                Toggle(isOn: $isHostBadgeEnabled) {
                    Label("Hostバッジ", systemImage: "person.crop.circle.badge.checkmark")
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 8) {
                    Text("フレーム")
                        .font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ProfileFrame.allCases) { frame in
                                Button {
                                    selectedFrame = frame
                                } label: {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .stroke(frame == .none ? Color.primary.opacity(0.25) : frame.color, lineWidth: 3)
                                            .frame(width: 34, height: 34)
                                            .overlay {
                                                if selectedFrame == frame {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption.weight(.bold))
                                                }
                                            }
                                        Text(frame.displayName)
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("プリセット")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            saveCurrentPreset()
                        } label: {
                            Label("保存", systemImage: "plus")
                                .font(.caption.weight(.semibold))
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(savedPresets) { preset in
                                Button {
                                    applyPreset(preset)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.name)
                                            .font(.caption.weight(.bold))
                                            .lineLimit(1)
                                        Text(preset.status.isEmpty ? "ひとことなし" : preset.status)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 120, alignment: .leading)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deletePreset(preset)
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }

                            if savedPresets.isEmpty {
                                Text("未保存")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 10)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Hostバッジ、フレーム、プリセットを使う")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func buildProfileForSave() -> UserProfile {
        let profile = UserProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status.trimmingCharacters(in: .whitespacesAndNewlines),
            iconID: selectedIconID,
            themeColor: selectedTheme.rawValue,
            imageData: customImageData,
            isHostBadgeEnabled: isHostBadgeEnabled,
            profileFrameID: selectedFrame.rawValue
        )

        return purchaseManager.isPlusActive ? profile : profile.removingPlusFeatures()
    }

    private func saveCurrentPreset() {
        let preset = ProfilePreset(profile: buildProfileForSave())
        var next = savedPresets.filter {
            $0.name != preset.name || $0.status != preset.status || $0.iconID != preset.iconID
        }
        next.insert(preset, at: 0)
        ProfilePresetStore.save(next)
        savedPresets = ProfilePresetStore.load()
    }

    private func applyPreset(_ preset: ProfilePreset) {
        let profile = purchaseManager.isPlusActive ? preset.profile : preset.profile.removingPlusFeatures()
        name = profile.name
        status = profile.status
        selectedIconID = profile.iconID
        selectedTheme = profile.selectedTheme
        customImageData = profile.imageData
        isHostBadgeEnabled = profile.isHostBadgeEnabled
        selectedFrame = profile.selectedFrame
        selectedPhotoItem = nil
    }

    private func deletePreset(_ preset: ProfilePreset) {
        let next = savedPresets.filter { $0.id != preset.id }
        ProfilePresetStore.save(next)
        savedPresets = ProfilePresetStore.load()
    }
}
