#!/usr/bin/env swift
//
// App Store マーケティングパネル生成スクリプト（AirTalk）
//
// docs/screenshots/raw/<device>/ にある生スクショを読み込み、上部にキャッチコピー、
// 下部に角丸＋影付きの端末スクショを配置した「映える」App Store 画像を
// docs/screenshots/store/<device>/ に書き出す。iPhone・iPad の両サイズを生成する。
//
// macOS 標準の AppKit / CoreText のみ使用（外部依存なし）。日本語はヒラギノを使う。
//
// 使い方:  swift docs/make-store-panels.swift
//
import AppKit
import CoreText

// MARK: - パネル定義（生スクショ名・大コピー・小コピー・背景グラデ色）

struct Panel {
    let source: String      // raw 内のファイル名
    let headline: String    // 大きなキャッチコピー
    let subline: String     // 補足コピー
    let top: NSColor        // 背景グラデ上
    let bottom: NSColor     // 背景グラデ下
}

// 紫を基調に、画面ごとに少し色相を変えて単調さを避ける。
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}

// 出力対象のデバイスクラス。raw/<key>/ から読み、store/<key>/ に書き出す。
// outputSize は App Store の規定サイズ（縦）:
//   iPhone 6.5": 1242×2688 / 1284×2778
//   iPad 12.9":  2048×2732 / 2064×2752
struct DeviceClass {
    let key: String
    let outputSize: NSSize
    let deviceWidthFrac: CGFloat   // 端末スクショの幅（キャンバス幅比）
    let deviceTopFrac: CGFloat     // 端末スクショ上端の位置（下からの高さ比）
    let cornerFrac: CGFloat        // 角丸半径（端末幅比）
}
// iPad はステータスバー（9:41 やアイコン）が画面の隅に寄っているため、角丸が大きいと
// 削れて見切れる。iPad は角丸を小さめ・幅も控えめにして、隅の表示を残す。
let deviceClasses: [DeviceClass] = [
    DeviceClass(key: "iphone", outputSize: NSSize(width: 1284, height: 2778),
                deviceWidthFrac: 0.82, deviceTopFrac: 0.74, cornerFrac: 0.09),
    DeviceClass(key: "ipad",   outputSize: NSSize(width: 2048, height: 2732),
                deviceWidthFrac: 0.84, deviceTopFrac: 0.74, cornerFrac: 0.035),
]

// headline は \n で文節区切りの改行位置を明示し、全パネル2行に揃える。
// （自動折り返しだと「声を／かけよう」のように不自然な位置で割れるため）
let panels: [Panel] = [
    Panel(source: "01-discovery.png",
          headline: "近くの人と、\nすぐつながる",
          subline: "半径50m。アプリを開くだけ。",
          top: rgb(124, 58, 237), bottom: rgb(91, 33, 182)),
    Panel(source: "02-invite.png",
          headline: "気になる相手に、\n声をかけよう",
          subline: "チャットは承認制。安心して始められる。",
          top: rgb(217, 70, 160), bottom: rgb(147, 51, 180)),
    Panel(source: "03-chat.png",
          headline: "会話は、\nその場かぎり",
          subline: "離れたら、メッセージは自動で消える。",
          top: rgb(99, 102, 241), bottom: rgb(67, 56, 202)),
    Panel(source: "04-onboarding.png",
          headline: "アカウントも、\nネットも、いらない",
          subline: "ニックネームだけで、すぐ始められる。",
          top: rgb(139, 92, 246), bottom: rgb(76, 29, 149)),
]

// MARK: - パス

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let screenshotsDir = scriptURL.appendingPathComponent("screenshots")

// MARK: - 描画ヘルパー

func hiragino(weight: String, size: CGFloat) -> NSFont {
    // ヒラギノ角ゴシック（W3=Regular, W6=Bold, W8=Heavy 相当）
    let name: String
    switch weight {
    case "heavy": name = "HiraginoSans-W8"
    case "bold":  name = "HiraginoSans-W7"
    default:      name = "HiraginoSans-W4"
    }
    return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold)
}

func paragraphStyle(lineSpacing: CGFloat) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineSpacing = lineSpacing
    style.lineBreakMode = .byWordWrapping
    return style
}

// テキストの実描画高さを測る（中央寄せ配置の基準にする）
func measureHeight(_ text: String, font: NSFont, maxWidth: CGFloat, lineSpacing: CGFloat) -> CGFloat {
    let attr = NSAttributedString(string: text,
        attributes: [.font: font, .paragraphStyle: paragraphStyle(lineSpacing: lineSpacing)])
    let r = attr.boundingRect(with: NSSize(width: maxWidth, height: 100000),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
    return ceil(r.height)
}

// 折り返しつき中央寄せテキストを描く
func draw(_ text: String, font: NSFont, color: NSColor, in rect: NSRect, lineSpacing: CGFloat = 6) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 0, height: -2)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color,
        .paragraphStyle: paragraphStyle(lineSpacing: lineSpacing), .shadow: shadow,
    ]
    text.draw(in: rect, withAttributes: attrs)
}

func roundedRectPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

// MARK: - パネル1枚を生成

func render(_ panel: Panel, device: DeviceClass) -> Bool {
    let rawDir = screenshotsDir.appendingPathComponent("raw/\(device.key)")
    let outDir = screenshotsDir.appendingPathComponent("store/\(device.key)")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let srcURL = rawDir.appendingPathComponent(panel.source)
    guard let shot = NSImage(contentsOf: srcURL),
          let shotRep = NSBitmapImageRep(data: shot.tiffRepresentation ?? Data()) else {
        print("  ✗ 読み込み失敗: \(device.key)/\(panel.source)")
        return false
    }
    let shotW = CGFloat(shotRep.pixelsWide)
    let shotH = CGFloat(shotRep.pixelsHigh)

    // 出力は App Store 規定サイズ。端末スクショは縦横比を保ったまま中に収める。
    let W = device.outputSize.width, H = device.outputSize.height

    // Retina 倍率に影響されないよう、ピクセル数を厳密に指定したビットマップへ直接描画する。
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(W), pixelsHigh: Int(H),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
    bitmap.size = NSSize(width: W, height: H)
    guard let gctx = NSGraphicsContext(bitmapImageRep: bitmap) else { return false }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    defer { NSGraphicsContext.restoreGraphicsState() }
    let ctx = gctx.cgContext

    // 背景グラデーション
    let gradient = NSGradient(starting: panel.top, ending: panel.bottom)!
    gradient.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // レイアウト方針: 上部をテキスト領域、その下に端末を大きく置き下端は画面外へブリード。
    // テキスト（headline + subline）は領域の上下中央にまとめて配置し、天井貼り付きを避ける。
    let deviceTopY = H * device.deviceTopFrac   // 端末スクショの上端（visual）
    let areaTop = H             // テキスト領域の上端（visual）
    let areaBottom = deviceTopY // テキスト領域の下端（visual）

    let headW = W * 0.88
    let subW  = W * 0.84
    let headFont = hiragino(weight: "heavy", size: W * 0.068)
    let subFont  = hiragino(weight: "bold",  size: W * 0.032)
    let headLS: CGFloat = 10
    let subLS:  CGFloat = 4
    let gap = W * 0.04   // headline と subline の間隔

    // 実高を測ってブロック全体を領域中央に置く
    let headH = measureHeight(panel.headline, font: headFont, maxWidth: headW, lineSpacing: headLS)
    let subH  = measureHeight(panel.subline,  font: subFont,  maxWidth: subW,  lineSpacing: subLS)
    let blockH = headH + gap + subH
    // 領域中央から少し端末寄り（下）にずらし、天井の余白を広めに取る
    let bias = (areaTop - areaBottom) * 0.06
    let blockTop = (areaTop + areaBottom) / 2 + blockH / 2 - bias   // ブロックの visual 上端

    // headline（領域中央寄せの上側）
    draw(panel.headline, font: headFont, color: .white,
         in: NSRect(x: (W - headW) / 2, y: blockTop - headH, width: headW, height: headH),
         lineSpacing: headLS)
    // subline（headline の直下）
    let subTop = blockTop - headH - gap
    draw(panel.subline, font: subFont, color: NSColor.white.withAlphaComponent(0.88),
         in: NSRect(x: (W - subW) / 2, y: subTop - subH, width: subW, height: subH),
         lineSpacing: subLS)

    // 端末スクショ: キャンバス幅の 82% に収め、縦横比は維持。上端を deviceTopY に合わせ、
    // 下端は画面外へブリードさせる。
    let fw = W * device.deviceWidthFrac
    let fh = fw * (shotH / shotW)   // アスペクト比を保つ
    let fx = (W - fw) / 2
    let fy = deviceTopY - fh   // 上端 = fy + fh = deviceTopY
    let frameRect = NSRect(x: fx, y: fy, width: fw, height: fh)
    let radius = fw * device.cornerFrac

    // 影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    let clip = roundedRectPath(frameRect, radius: radius)
    NSColor.black.setFill()
    clip.fill()
    ctx.restoreGState()

    // 角丸クリップしてスクショを描画。
    // from に .zero を渡すと「画像全体」を意味し、DPI メタデータに左右されず確実に描ける
    // （ピクセル寸法を渡すと iPad 等の高 DPI スクショで描画範囲がずれる）。
    ctx.saveGState()
    clip.addClip()
    shot.draw(in: frameRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    ctx.restoreGState()

    // 端末枠の縁（うっすら白）
    let border = roundedRectPath(frameRect, radius: radius)
    border.lineWidth = W * 0.004
    NSColor.white.withAlphaComponent(0.18).setStroke()
    border.stroke()

    // PNG 書き出し（厳密なピクセル数のビットマップから直接生成。context は defer で復帰）
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
    let outName = panel.source.replacingOccurrences(of: ".png", with: "-store.png")
    let outURL = outDir.appendingPathComponent(outName)
    do { try png.write(to: outURL); print("  ✓ \(device.key)/\(outName)"); return true }
    catch { print("  ✗ 書き込み失敗: \(device.key)/\(outName) \(error)"); return false }
}

// MARK: - 実行

print("▶ マーケティングパネル生成...")
var ok = 0, total = 0
for device in deviceClasses {
    let rawDir = screenshotsDir.appendingPathComponent("raw/\(device.key)")
    guard FileManager.default.fileExists(atPath: rawDir.path) else {
        print("  – \(device.key): 生スクショ未取得（\(rawDir.lastPathComponent) なし）。スキップ")
        continue
    }
    for panel in panels {
        total += 1
        if render(panel, device: device) { ok += 1 }
    }
}
print("✅ \(ok)/\(total) 枚を生成: \(screenshotsDir.appendingPathComponent("store").path)")
