import AppKit

let outputDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("screenshots/raw/iphone")
let pngOutputURL = outputDirectory.appendingPathComponent("05-paywall-review.png")
let jpegOutputURL = outputDirectory.appendingPathComponent("05-paywall-review.jpg")

let width: CGFloat = 1290
let height: CGFloat = 2796

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: height - y - h, width: w, height: h)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func drawText(
    _ text: String,
    at frame: NSRect,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = .labelColor,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    text.draw(in: frame, withAttributes: attributes)
}

func rounded(_ frame: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Failed to create bitmap")
}
bitmap.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
NSGraphicsContext.current?.shouldAntialias = true

let bg = NSGradient(colors: [
    color(0.47, 0.15, 0.92),
    color(0.34, 0.38, 0.94),
    color(0.92, 0.72, 0.98),
])!
bg.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

drawText("AirTalk Plus", at: rect(110, 150, 1070, 90), size: 58, weight: .bold, color: .white, alignment: .center)
drawText("その場で、もっと見つけてもらう", at: rect(110, 250, 1070, 72), size: 38, weight: .bold, color: .white, alignment: .center)

let phone = rect(105, 410, 1080, 2140)
rounded(phone, radius: 88, fill: color(0.96, 0.90, 1.0, 0.94), stroke: color(1, 1, 1, 0.55), lineWidth: 4)
rounded(rect(475, 462, 340, 86), radius: 43, fill: .black)

drawText("AirTalk Plus", at: rect(170, 620, 950, 68), size: 42, weight: .bold, color: .black, alignment: .center)
drawText("基本の発見・招待・1対1チャットは無料のまま。Plusではイベントや場づくりに便利なプロフィール機能を解放します。", at: rect(210, 720, 870, 120), size: 30, weight: .medium, color: color(0.22, 0.18, 0.28), alignment: .center)

let featureY: CGFloat = 910
let features = [
    ("HOST", "Hostバッジ", "イベントや場の主催者として見つけてもらいやすくする"),
    ("◎", "プレミアムフレーム", "レーダーとチャットでプロフィールを少し目立たせる"),
    ("▣", "プロフィールプリセット", "イベント用、作業用、旅先用などをすぐ切り替える"),
    ("✦", "アイスブレイク", "最初の一言に使える定型文と追加リアクション"),
]

for (index, item) in features.enumerated() {
    let y = featureY + CGFloat(index) * 170
    rounded(rect(190, y, 910, 130), radius: 34, fill: color(1, 1, 1, 0.58), stroke: color(0.55, 0.35, 0.75, 0.22), lineWidth: 2)
    rounded(rect(225, y + 32, 76, 66), radius: 24, fill: color(0.48, 0.18, 0.72, 0.16))
    drawText(item.0, at: rect(225, y + 45, 76, 36), size: item.0 == "HOST" ? 18 : 28, weight: .black, color: color(0.38, 0.08, 0.64), alignment: .center)
    drawText(item.1, at: rect(330, y + 24, 720, 38), size: 30, weight: .bold, color: .black)
    drawText(item.2, at: rect(330, y + 68, 720, 42), size: 22, weight: .regular, color: color(0.26, 0.22, 0.30))
}

let monthly = rect(190, 1660, 910, 144)
rounded(monthly, radius: 34, fill: color(1, 1, 1, 0.78), stroke: color(0.45, 0.12, 0.72, 0.55), lineWidth: 4)
drawText("月額プラン", at: rect(230, 1690, 380, 40), size: 30, weight: .bold, color: .black)
drawText("1週間の無料トライアル後、自動更新", at: rect(230, 1736, 520, 32), size: 21, color: color(0.30, 0.25, 0.35))
drawText("¥300", at: rect(835, 1699, 210, 52), size: 36, weight: .bold, color: .black, alignment: .right)

let yearly = rect(190, 1840, 910, 144)
rounded(yearly, radius: 34, fill: color(1, 1, 1, 0.58), stroke: color(0.55, 0.35, 0.75, 0.22), lineWidth: 2)
drawText("年額プラン", at: rect(230, 1870, 380, 40), size: 30, weight: .bold, color: .black)
drawText("月額よりお得に継続", at: rect(230, 1916, 520, 32), size: 21, color: color(0.30, 0.25, 0.35))
drawText("¥2,900", at: rect(835, 1879, 210, 52), size: 36, weight: .bold, color: .black, alignment: .right)

drawText("購入を復元", at: rect(190, 2045, 910, 34), size: 24, weight: .semibold, color: color(0.23, 0.14, 0.34), alignment: .center)
drawText("サブスクリプションは自動更新されます。解約はApp Storeのアカウント設定からいつでも行えます。", at: rect(220, 2110, 850, 80), size: 21, color: color(0.32, 0.28, 0.36), alignment: .center)
drawText("利用規約   プライバシー", at: rect(220, 2204, 850, 34), size: 22, weight: .semibold, color: color(0.22, 0.12, 0.38), alignment: .center)

drawText("Review screenshot for App Store Connect", at: rect(110, 2600, 1070, 42), size: 24, color: color(1, 1, 1, 0.75), alignment: .center)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]),
      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
    fatalError("Failed to render images")
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try png.write(to: pngOutputURL)
try jpeg.write(to: jpegOutputURL)
print(pngOutputURL.path)
print(jpegOutputURL.path)
