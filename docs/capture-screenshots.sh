#!/bin/bash
#
# App Store スクリーンショット撮影スクリプト（AirTalk）
#
# デモモード（起動引数 -demo YES）でアプリを立ち上げ、4つの画面を iPhone と iPad の
# 両方で撮影する。MultipeerConnectivity は実機2台が必要だが、デモモードは架空のピア・
# 会話を注入するためシミュレータ単体で見栄えの良いスクショが撮れる。
#
# 生スクショは screenshots/raw/<device>/ に保存し、続けて make-store-panels.swift で
# キャッチコピー付きの App Store 用パネルを screenshots/store/<device>/ に生成する。
# 英語版は screenshots/en/raw/<device>/ → screenshots/en/store/<device>/ に出力する。
#
# 使い方:
#   ./docs/capture-screenshots.sh                              # 既定機種で iPhone+iPad、日本語+英語
#   IPHONE="iPhone 17 Pro" IPAD="iPad Pro 13-inch (M5)" ./docs/capture-screenshots.sh
#   LANGS="en" ./docs/capture-screenshots.sh                   # 英語だけ撮り直す
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BID="com.yuuki.AirTalk"
IPHONE_NAME="${IPHONE:-iPhone 17 Pro Max}"     # App Store 6.5/6.9 インチ枠
IPAD_NAME="${IPAD:-iPad Pro 13-inch (M5)}"     # App Store 12.9/13 インチ枠
LANGS="${LANGS:-ja en}"                        # 撮影する言語（ja / en）
WAIT="${WAIT:-3}"                              # 描画済みか確かめる間隔（秒）
TRIES="${TRIES:-20}"                           # 描画済みになるまで撮り直す最大回数

# 言語ごとの出力先ルート（ja は従来どおり screenshots/ 直下）
lang_root() {
  if [ "$1" = "ja" ]; then echo "$HERE/screenshots"; else echo "$HERE/screenshots/$1"; fi
}

cd "$HERE/.."

# 描画済み判定ツールを一度だけコンパイルする（起動直後の白画面・ホーム画面を保存しないため）
CHECKER="$(mktemp -d)/is-rendered"
swiftc -O "$HERE/is-rendered.swift" -o "$CHECKER"

echo "▶ ビルド中..."
xcodebuild -project AirTalk.xcodeproj -scheme AirTalk -configuration Debug \
  -destination "generic/platform=iOS Simulator" build >/dev/null

# シミュレータ用（iphonesimulator SDK）のビルド成果物パス。iPhone/iPad 共通バイナリ。
# -sdk を指定しないと iphoneos（実機）パスが返り、実機バイナリをシミュレータに入れて起動失敗する。
APP="$(xcodebuild -project AirTalk.xcodeproj -scheme AirTalk -sdk iphonesimulator -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ TARGET_BUILD_DIR =/{d=$2} / FULL_PRODUCT_NAME =/{n=$2} END{print d"/"n}')"

# 名前 → UDID（同名デバイスが複数あるため先頭の1件）
resolve_udid() {
  xcrun simctl list devices available | grep -F "$1 (" | head -1 \
    | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

# 1デバイスで4シーンを撮影し <lang_root>/raw/<class>/ に保存する
capture_device() {  # $1=クラス名(iphone/ipad)  $2=デバイス表示名  $3=言語(ja/en)
  local class="$1" name="$2" lang="$3"
  local udid out locale
  udid="$(resolve_udid "$name")"
  if [ -z "$udid" ]; then echo "✗ デバイスが見つかりません: $name（スキップ）"; return 0; fi
  out="$(lang_root "$lang")/raw/$class"
  mkdir -p "$out"
  if [ "$lang" = "ja" ]; then locale="ja_JP"; else locale="en_US"; fi

  echo "▶ [$lang/$class] $name ($udid)"
  xcrun simctl boot "$udid" 2>/dev/null || true
  open -a Simulator
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true

  # 各シーンごとにクリーンに入れ直す（再 launch の SBMainWorkspace 拒否を避ける）
  shot() {  # $1=scene  $2=ファイル名
    xcrun simctl terminate "$udid" "$BID" 2>/dev/null || true
    xcrun simctl uninstall "$udid" "$BID" 2>/dev/null || true
    xcrun simctl install "$udid" "$APP"
    sleep 2
    xcrun simctl launch "$udid" "$BID" -demo YES -demoScene "$1" \
      -AppleLanguages "($lang)" -AppleLocale "$locale" >/dev/null
    # マシンが重いと描画に時間がかかるため、紫の背景が出るまで撮り直す
    local i
    for i in $(seq "$TRIES"); do
      sleep "$WAIT"
      xcrun simctl io "$udid" screenshot "$out/$2" >/dev/null 2>&1 || continue
      if "$CHECKER" "$out/$2"; then
        sleep 1   # アニメーションが落ち着くのを待って撮り直す
        xcrun simctl io "$udid" screenshot "$out/$2" >/dev/null
        echo "  ✓ $lang/$class/$2"
        return 0
      fi
    done
    echo "  ✗ $lang/$class/$2（描画を確認できませんでした）"
  }
  shot discovery  01-discovery.png
  shot invite     02-invite.png
  shot chat       03-chat.png
  shot onboarding 04-onboarding.png
  xcrun simctl terminate "$udid" "$BID" 2>/dev/null || true
}

echo "▶ 撮影..."
for lang in $LANGS; do
  capture_device iphone "$IPHONE_NAME" "$lang"
  capture_device ipad   "$IPAD_NAME"   "$lang"
done
echo "▶ 生スクショ完了"

# キャッチコピー付き App Store パネルを生成（iPhone/iPad 両サイズ・言語ごと）
echo "▶ パネル生成..."
for lang in $LANGS; do
  swift "$HERE/make-store-panels.swift" "$lang"
done

echo "✅ すべて完了"
