import SwiftUI

struct AuroraBackgroundView: View {
    @State private var rotation: Double = 0
    
    var themeColor: ThemeColor = .purple
    
    var body: some View {
        ZStack {
            // 背景の暗いベース（ダークモード・ライトモード対応）
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            // ゆったりと動くオーロラグラデーション（切り返しのない無限回転）
            LinearGradient(
                colors: themeColor.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .scaleEffect(1.5) // 回転時に隅が切れないように拡大
            .rotationEffect(.degrees(rotation))
            .opacity(0.5)
            .blur(radius: 60)
            .ignoresSafeArea()
            .onAppear {
                withAnimation(
                    .linear(duration: 30)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
        }
    }
}
