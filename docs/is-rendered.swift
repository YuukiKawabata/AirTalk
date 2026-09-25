// スクショがアプリの描画済み画面かを判定する（capture-screenshots.sh から使う）。
// デモ画面はどれも紫のオーロラ背景なので、画面左側の中央付近の平均色が紫寄りなら描画済みとみなす。
// 白画面（起動直後）・黒画面（ブート中）・ホーム画面を弾くための簡易判定。
// 使い方: is-rendered <png>   終了コード 0 = 描画済み / 1 = 未描画
import AppKit

guard CommandLine.arguments.count > 1,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let data = cg.dataProvider?.data,
      let ptr = CFDataGetBytePtr(data) else { exit(1) }

let bpp = cg.bitsPerPixel / 8, bpr = cg.bytesPerRow
var r = 0.0, g = 0.0, b = 0.0, n = 0.0
for yi in stride(from: 0.40, through: 0.60, by: 0.02) {
    for xi in stride(from: 0.04, through: 0.20, by: 0.02) {
        let o = Int(Double(cg.height) * yi) * bpr + Int(Double(cg.width) * xi) * bpp
        r += Double(ptr[o]); g += Double(ptr[o + 1]); b += Double(ptr[o + 2]); n += 1
    }
}
r /= n; g /= n; b /= n
exit(b > g + 25 && r > g ? 0 : 1)
