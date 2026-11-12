import SwiftUI

@main
struct AirTalkApp: App {
    @UIApplicationDelegateAdaptor(OnlineAppDelegate.self) private var onlineAppDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasAcceptedEULA") private var hasAcceptedEULA = false
    @StateObject private var multipeerManager = MultipeerManager()
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var onlineStore = OnlineStore()
#if DEBUG
    @StateObject private var encounterManager = EncounterManager()
#endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if OnlineConfiguration.current?.local == true && UserDefaults.standard.bool(forKey: "onlinePilot") {
                    OnlineView()
                } else if OnlinePreviewView.isSelected {
                    OnlinePreviewView()
                } else if EncounterManager.isAvailable {
                    EncounterPrototypeView(manager: encounterManager)
                } else {
                    standardContent
                }
#else
                standardContent
#endif
            }
            .environmentObject(multipeerManager)
            .environmentObject(purchaseManager)
            .environmentObject(onlineStore)
            .onReceive(NotificationCenter.default.publisher(for: OnlineAppDelegate.tokenReceived)) { notification in
                guard !DemoMode.isEnabled, let data=notification.object as? Data else { return }
                Task { await onlineStore.registerPush(data) }
            }
            .task {
#if DEBUG
                guard !EncounterManager.isAvailable else { return }
#endif
                guard !DemoMode.isEnabled else { return }
                await purchaseManager.configure()
                removeExpiredPlusFeaturesIfNeeded()
            }
            .onChange(of: purchaseManager.isPlusActive) { _, isPlusActive in
#if DEBUG
                guard !EncounterManager.isAvailable else { return }
#endif
                if !isPlusActive { removeExpiredPlusFeaturesIfNeeded() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
#if DEBUG
            guard !EncounterManager.isAvailable else { return }
#endif
            guard !DemoMode.isEnabled else { return }
            if newPhase == .background {
                multipeerManager.clearAll()
                onlineStore.end()
            } else if newPhase == .active && hasCompletedOnboarding && hasAcceptedEULA {
                Task { await onlineStore.becameActive() }
                if !onlineStore.screenVisible, let profile = UserProfile.load() {
                    multipeerManager.configure(with: profile)
                    multipeerManager.start()
                }
            }
        }
    }

    private var standardContent: some View {
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
