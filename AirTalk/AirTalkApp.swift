import SwiftUI

@main
struct AirTalkApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var multipeerManager = MultipeerManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
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
            if newPhase == .background {
                multipeerManager.clearAll()
            } else if newPhase == .active && hasCompletedOnboarding {
                if let profile = UserProfile.load() {
                    multipeerManager.configure(with: profile)
                    multipeerManager.start()
                }
            }
        }
    }
}
