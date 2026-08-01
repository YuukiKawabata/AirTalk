# AirTalk リリース準備ガイド

App Store 提出に必要な情報・手順をまとめる。`docs/SPEC.md` が技術仕様、本書が**ストア提出物**を扱う。

---

## 1. App Store Connect 入力情報

### アプリ名 / サブタイトル

- **名前**: AirTalk
- **サブタイトル**: 半径50mの一期一会チャット

### プロモーションテキスト（170字以内）

> すれ違った“いま近くにいる人”とだけ話せる。インターネットもアカウントも不要。会話は離れた瞬間に消える、一期一会のチャット。

### 説明文（App Store 用）

> **AirTalk は「いま、近くにいる人」とだけつながるローカルチャットです。**
>
> インターネットもサーバーもアカウントも使いません。Wi-Fi と Bluetooth を使って、半径数十メートルにいる相手を直接見つけ、1対1で会話します。
>
> ■ 一期一会
> 会話はあなたの端末のメモリ上にのみ存在します。相手と離れたり、アプリを閉じたりした瞬間に、メッセージはすべて自動で消えます。履歴は一切残りません。
>
> ■ サーバーレス・オフライン
> メッセージは端末から端末へ暗号化して直接届きます。通信はインターネットを経由しません。圏外でも、機内モード＋Wi-Fi/Bluetooth でも動きます。
>
> ■ プライバシーファースト
> アカウント登録不要。個人情報の収集・送信は一切ありません。プロフィール（ニックネーム・アイコン・ひとこと）はあなたの端末内にのみ保存されます。
>
> ■ こんな場面で
> ・イベントや勉強会で隣の人と
> ・カフェやコワーキングで近くの人と
> ・旅先で同じ宿の人と
>
> 名乗って、話して、離れたら忘れる。AirTalk は、その場かぎりの軽やかな会話のためのアプリです。
>
> 利用規約（EULA）: https://yuukikawabata.github.io/airwish-support/#terms
> プライバシーポリシー: https://yuukikawabata.github.io/airwish-support/#privacy

### キーワード（100字以内・カンマ区切り）

```
近距離,チャット,P2P,オフライン,ローカル通信,Bluetooth,Wi-Fi,イベント,会話,プライバシー,サーバーレス
```

### カテゴリ

- プライマリ: ソーシャルネットワーキング
- セカンダリ: ユーティリティ

### サポートURL / マーケティングURL

- **サポートURL**: https://yuukikawabata.github.io/airwish-support/
- サポート、プライバシーポリシー、利用規約（UGC無許容ポリシー）、アカウント削除手順を1ページに収録。

### AirTalk Plus / サブスクリプション

| 項目 | 値 |
|------|-----|
| グループ | `AirTalk Plus` (`22193555`) |
| 月額 | `com.yuuki.AirTalk.plus.monthly` (`6785129209`) / 300円基準 |
| 年額 | `com.yuuki.AirTalk.plus.yearly` (`6785129341`) / 2,900円基準 |
| 導入オファー | 月額のみ 1週間無料トライアル |
| 提供国 | 全 App Store 地域（基準テリトリ: 日本 `JPN`） |
| 審査用スクリーンショット | `docs/screenshots/raw/iphone/05-paywall-review.jpg` |

AirTalk Plus は任意のプロフィール表現機能のみを解放する。近くのユーザー発見、招待、1対1チャット、通報、ブロックは無料のまま維持する。

ASC のサブスクリプション設定を再作成/確認する場合:

```bash
node scripts/asc/setup-subscriptions.mjs
node scripts/asc/configure-subscription-commerce.mjs
node scripts/asc/configure-subscription-equalized-prices.mjs
swift docs/make-subscription-review-screenshot.swift
node scripts/asc/upload-subscription-review-screenshots.mjs docs/screenshots/raw/iphone/05-paywall-review.jpg 6785129209 6785129341
```

プロモーション画像を更新する場合:

```bash
sips -z 1024 1024 -s format jpeg docs/screenshots/raw/iphone/05-paywall-review.jpg --out docs/screenshots/raw/iphone/05-paywall-promo.jpg
node scripts/asc/upload-subscription-images.mjs docs/screenshots/raw/iphone/05-paywall-promo.jpg 6785129209
```

> 2026-06-28 時点で、月額のプロモーション画像は登録済み。年額のプロモーション画像は Apple API が `500 UNEXPECTED_ERROR` を返すため未登録だが、プロモーション画像は審査用スクリーンショットとは別枠。
>
> 2026-08-01 時点で、サブスクリプション2商品とアプリ本体 1.2 は承認・公開済み。通常のアプリ更新でサブスクリプションを再提出する必要はない。

---

## 2. プライバシー（App Privacy）設定

App Store Connect の「アプリのプライバシー」では **「データを収集していません（Data Not Collected）」** を選択できる。

- トラッキング: なし
- 収集データ: なし
- 同梱の `AirTalk/PrivacyInfo.xcprivacy` がこれを宣言済み（UserDefaults を Required Reason API `CA92.1` で宣言）

> メッセージもプロフィールも端末外に送信されない（P2P 相手にのみ直接届く）ため、Apple の定義上「収集」に該当しない。

---

## 3. 審査メモ（App Review Information → Notes）★最重要

MultipeerConnectivity は **シミュレータでは安定動作せず、物理デバイス2台が必須**。審査者が1台／シミュレータでテストすると「相手が見つからない＝機能しない」と誤解され、リジェクトされうる。以下を必ず Notes に記載する（英語推奨）。

> AirTalk uses MultipeerConnectivity (Wi-Fi + Bluetooth) for peer-to-peer chat with nearby devices. **It requires TWO physical iOS devices in close proximity to function** — it cannot be tested on a single device or in the Simulator.
>
> Steps to test:
> 1. Install and launch the app on two physical devices placed next to each other.
> 2. Complete onboarding (enter a nickname) on each.
> 3. Each device shows the other as an avatar on the radar screen.
> 4. Tap the other user's avatar to send a chat request; accept it on the other device.
> 5. Exchange messages. Moving the devices apart or backgrounding the app clears the conversation (by design).
>
> On first launch, iOS will ask for **Local Network** and **Bluetooth** permission — both must be allowed for discovery to work.
>
> No server-side account or login is required. Users create only a local profile on their device. No data is collected or sent to our server.
>
> AirTalk Plus is an optional auto-renewable subscription. It unlocks profile presentation features only: Host badge, profile frames, saved profile presets, icebreakers, extra reactions, and premium profile themes. Nearby discovery, chat requests, one-to-one chat, reporting, and blocking remain available for free.
>
> Safety / UGC controls:
> - On first launch, users must agree to the EULA before creating their local profile.
> - The EULA states that AirTalk has no tolerance for objectionable content or abusive users.
> - Users can long-press an incoming chat message and choose "メッセージを通報" to report objectionable content.
> - Users can open the chat menu and choose "このユーザーをブロックして通報" to block an abusive user. Blocking immediately removes the chat/user from the app and opens a prefilled report email to notify the developer.
> - Users can delete their local AirTalk account/profile from the gear icon → "アカウントを削除" → confirm → completion screen.

### デモアカウント

- 不要（ログインなし）。Notes に "No login required" と明記。

---

## 4. 必要権限と Info.plist

`AirTalk/Info.plist` に設定済み（MultipeerConnectivity 動作に必須）:

| キー | 用途 |
|------|------|
| `NSLocalNetworkUsageDescription` | 近くのユーザー発見・通信 |
| `NSBluetoothAlwaysUsageDescription` | 近くのデバイス発見 |
| `NSBonjourServices` (`_airtalk._tcp` / `_airtalk._udp`) | Bonjour サービス公開 |

アプリ内では、権限が拒否された場合にレーダー画面で案内と「設定を開く」導線を表示する（`RadarView.statusOverlay`）。

---

## 5. スクリーンショット戦略

実機2台が必要なため、**2台を並べた実機キャプチャ**が映える。最低 6.7" と 6.5"（または App Store の必須サイズ）を用意。

| # | 画面 | 訴求コピー案 |
|---|------|--------------|
| 1 | レーダー画面（周囲に複数アバター） | いま、近くにいる人が見える |
| 2 | チャット画面（吹き出し＋リアクション） | 名乗って、すぐ話せる |
| 3 | オンボーディング（プロフィール作成） | アカウント不要。30秒で開始 |
| 4 | 切断バナー（メッセージ破棄） | 離れたら、すべて消える |
| 5 | 権限・オフライン訴求 | サーバーなし・インターネット不要 |

> Aurora 背景＋ガラス質感のUIが映えるので、ライト/ダーク両方で撮って良い方を採用。

---

## 6. リリース前チェックリスト

- [x] `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` を確認（1.2.1 / 8）
- [x] Bundle ID `com.yuuki.AirTalk` で App Store Connect にアプリ登録
- [x] 配布用 App Icon が 1024×1024（アルファなし）であることを確認
- [ ] 実機2台で発見 → 接続 → 送受信 → 切断（自動消去）を通しでテスト
- [ ] 権限を「許可しない」にした場合の案内表示を確認
- [ ] プロフィール画像が相手側にも鮮明に表示されることを確認（接続後にP2P交換）
- [ ] ダーク/ライト両モードで表示崩れがないか確認
- [x] Archive → Validate → App Store Connect へアップロード
- [x] App Privacy「データを収集していません」を維持
- [x] 審査メモに「物理デバイス2台必須」を記載（§3）
- [x] `1.2(7)` とサブスクリプション2商品は承認・公開済み
- [x] `1.2.1(8)` をアップロードし、手動公開で審査提出済み

---

## 7. 既知の制約・今後の検討

- **バックグラウンドで接続維持不可**: iOS の制約。仕様として受容（離れたら終わり）。
- **同名ユーザーの区別**: 現状 displayName のみ。将来、識別子の付加を検討。
- **実機確認**: 近距離通信の発見・招待・送受信・切断消去は、物理 iPhone 2台でリリースごとに確認する。
- **テキストのみ**: 画像・スタンプ送信は未対応。
