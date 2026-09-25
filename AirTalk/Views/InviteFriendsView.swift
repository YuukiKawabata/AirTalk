import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

enum AppLinks {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6760606408")!
}

/// 近くに AirTalk ユーザーがいないときに、目の前の相手へアプリを入れてもらうためのシート。
/// その場で見せる QR コードと、メッセージアプリ等へ送る共有リンクを用意する。
struct InviteFriendsView: View {
    let themeColor: ThemeColor
    @Environment(\.dismiss) private var dismiss

    private var shareMessage: String {
        String(localized: "AirTalkで話そう！インターネットなしで、近くの人とだけチャットできるアプリです。")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackgroundView(themeColor: themeColor)

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Text("近くの友だちを誘う")
                                .font(.title2.bold())
                            Text("AirTalkは、同じアプリを入れた人が近くにいるとつながります。このQRコードを相手のカメラで読み取ってもらいましょう。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let qr = QRCode.image(for: AppLinks.appStoreURL.absoluteString) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .padding(20)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
                                .accessibilityLabel(Text("App StoreのAirTalkページへのQRコード"))
                        }

                        ShareLink(item: AppLinks.appStoreURL, message: Text(shareMessage)) {
                            Label("リンクを送る", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(themeColor.color, in: RoundedRectangle(cornerRadius: 16))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            tip(icon: "wifi", text: "おたがいにWi-FiとBluetoothをオンにしてください（インターネット接続は不要です）")
                            tip(icon: "iphone.radiowaves.left.and.right", text: "アプリを開いたままにすると、レーダーに相手が表示されます")
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func tip(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
