import UIKit

extension UIImage {
    /// P2P送信用に極小区矩形にリサイズし、高圧縮JPEGのDataを返す
    /// MultipeerConnectivityのdiscoveryInfoの上限(約400~500 bytes)に収めるための最適化
    func compressedThumbnailData(targetSize: CGFloat = 48.0) -> Data? {
        // 解像度を落とす
        let size = self.size
        let ratio = min(targetSize / size.width, targetSize / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Retina等を考慮せず実ピクセルにする
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        
        let resizedImage = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        // JPEGで高圧縮 (0.1〜0.05など)
        var quality: CGFloat = 0.1
        var data = resizedImage.jpegData(compressionQuality: quality)
        
        // 厳密なファイルサイズチェック (discoveryInfo全体のヘッダ等を考慮し300バイト以下を目標)
        // 300バイトに収まらなければさらに圧縮率を下げる
        while let currentData = data, currentData.count > 350 && quality > 0.0 {
            quality -= 0.02
            data = resizedImage.jpegData(compressionQuality: quality)
        }
        
        return data
    }
}
