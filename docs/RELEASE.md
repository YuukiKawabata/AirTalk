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
> 名乗って、話して、離れたら忘れる。AirTalk は、その場かぎりの軽やかな出会いのためのアプリです。

### キーワード（100字以内・カンマ区切り）

```
近く,チャット,P2P,オフライン,匿名,一期一会,ローカル,すれ違い,Bluetooth,イベント,会話,プライバシー
```

### カテゴリ

- プライマリ: ソーシャルネットワーキング
- セカンダリ: ユーティリティ

### サポートURL / マーケティングURL

- **サポートURL**: https://yuukikawabata.github.io/airwish-support/
- サポート、プライバシーポリシー、利用規約（UGC無許容ポリシー）、アカウント削除手順を1ページに収録。

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

- [ ] `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` を確認（現状 1.0 / 3）
- [ ] Bundle ID `com.yuuki.AirTalk` で App Store Connect にアプリ登録
- [ ] 配布用 App Icon が 1024×1024（アルファなし）であることを確認
- [ ] 実機2台で発見 → 接続 → 送受信 → 切断（自動消去）を通しでテスト
- [ ] 権限を「許可しない」にした場合の案内表示を確認
- [ ] プロフィール画像が相手側にも鮮明に表示されることを確認（接続後にP2P交換）
- [ ] ダーク/ライト両モードで表示崩れがないか確認
- [ ] Archive → Validate → App Store Connect へアップロード
- [ ] App Privacy「データを収集していません」を選択
- [ ] 審査メモに「物理デバイス2台必須」を記載（§3）

---

## 7. 既知の制約・今後の検討

- **バックグラウンドで接続維持不可**: iOS の制約。仕様として受容（離れたら終わり）。
- **同名ユーザーの区別**: 現状 displayName のみ。将来、識別子の付加を検討。
- **ブロック/通報機能**: 現状なし。招待は手動承認制（知らない相手を拒否可能）だが、Apple ガイドライン 1.2（UGC）対応として、将来的に通報・ブロックの導入を検討（審査で求められる可能性あり）。
- **テキストのみ**: 画像・スタンプ送信は未対応。
