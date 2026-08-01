import SwiftUI

@main
struct AirTalkApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasAcceptedEULA") private var hasAcceptedEULA = false
    @StateObject private var multipeerManager = MultipeerManager()
    @StateObject private var purchaseManager = PurchaseManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if DemoMode.isEnabled {
                    // スクショ撮影用デモ。onboarding シーンだけ初回画面、それ以外はメイン画面を表示する。
                    // デモデータの注入は DiscoveryView 側の onAppear に集約している。
                    if DemoMode.scene == .onboarding {
                        OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    } else {
                        DiscoveryView()
                    }
                } else if hasCompletedOnboarding && hasAcceptedEULA {
                    DiscoveryView()
                        .onAppear {
                            if !multipeerManager.isRunning, let profile = UserProfile.load() {
                                multipeerManager.configure(with: profile)
                                multipeerManager.start()
                            }
                        }
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .environmentObject(multipeerManager)
            .environmentObject(purchaseManager)
            .task {
                guard !DemoMode.isEnabled else { return }
                await purchaseManager.configure()
                removeExpiredPlusFeaturesIfNeeded()
            }
            .onChange(of: purchaseManager.isPlusActive) { _, isPlusActive in
                if !isPlusActive {
                    removeExpiredPlusFeaturesIfNeeded()
                }
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

    private func removeExpiredPlusFeaturesIfNeeded() {
        guard !purchaseManager.isPlusActive,
              let profile = UserProfile.load(),
              profile.usesPlusFeatures else { return }

        let freeProfile = profile.removingPlusFeatures()
        freeProfile.save()

        if hasCompletedOnboarding && hasAcceptedEULA {
            multipeerManager.updateProfile(freeProfile)
        }
    }
}
