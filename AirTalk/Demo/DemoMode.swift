import Foundation

/// デモモードの有効判定と、表示する画面の選択。
///
/// 起動引数（Launch Arguments）で制御するため、本番のリリースビルドでは一切作動しない。
/// スクショ撮影時だけ Xcode の Scheme か `xcrun simctl launch ... -demo YES` で有効化する。
///
/// 使い方の例:
/// - レーダー画面: 起動引数に `-demo YES`
/// - チャット画面: 起動引数に `-demo YES -demoScene chat`
///
/// `-demoScene chat` のように `-キー 値` 形式で渡すと UserDefaults から読めるため、
/// `UserDefaults.standard.string(forKey:)` で値を取得している。
enum DemoMode {

    enum Scene: String {
        case discovery   // レーダー（周囲のピア一覧）
        case chat        // 1対1チャット
        case invite      // チャットリクエスト着信
        case onboarding  // 初回プロフィール設定
    }

    /// デモモードが有効か。`-demo YES` で true になる。
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "demo")
    }

    /// 表示する画面。指定が無ければレーダー。
    static var scene: Scene {
        guard let raw = UserDefaults.standard.string(forKey: "demoScene"),
              let scene = Scene(rawValue: raw) else {
            return .discovery
        }
        return scene
    }
}
