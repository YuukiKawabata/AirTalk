import SwiftUI

@main
struct AirTalkApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasAcceptedEULA") private var hasAcceptedEULA = false
    @StateObject private var multipeerManager = MultipeerManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if DemoMode.isEnabled {
                // スクショ撮影用デモ。onboarding シーンだけ初回画面、それ以外はメイン画面を表示する。
                // デモデータの注入は DiscoveryView 側の onAppear に集約している。
                if DemoMode.scene == .onboarding {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .environmentObject(multipeerManager)
                } else {
                    DiscoveryView()
                        .environmentObject(multipeerManager)
                }
            } else if hasCompletedOnboarding && hasAcceptedEULA {
                DiscoveryView()
                    .environmentObject(multipeerManager)
                    .onAppear {
                        if !multipeerManager.isRunning, let profile = UserProfile.load() {
                            multipeerManager.configure(with: profile)
                            multipeerManager.start()
                        }
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(multipeerManager)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // デモモードではバックグラウンド遷移でデータを消さない（再起動なしで撮り直せるように）
            guard !DemoMode.isEnabled else { return }

            if newPhase == .background {
                multipeerManager.clearAll()
            } else if newPhase == .active && hasCompletedOnboarding && hasAcceptedEULA {
                if let profile = UserProfile.load() {
                    multipeerManager.configure(with: profile)
                    multipeerManager.start()
                }
            }
        }
    }
}
