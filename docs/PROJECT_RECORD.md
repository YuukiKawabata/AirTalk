# AirTalk プロジェクト完全記録

このドキュメントは、AirTalk の開発から App Store 審査提出までの**全作業・全情報**を1か所にまとめたものです。
（技術仕様の詳細は [SPEC.md](SPEC.md)、リリース手順は [RELEASE.md](RELEASE.md) を参照）

最終更新: 2026-08-01 / 状態: **1.2 公開中 / 1.2.1(8) 品質改善版を提出準備中**

---

## 1. アプリ概要

| 項目 | 内容 |
|------|------|
| アプリ名（表示名） | **AirTalk** |
| コンセプト | 半径50mの一期一会 — 近くにいる人とだけ話せるローカルP2Pチャット |
| 対象 | iOS 17.0+ |
| 言語/UI | Swift / SwiftUI |
| 通信 | MultipeerConnectivity（Wi-Fi + Bluetooth、暗号化 `.required`） |
| 永続化 | なし（メッセージは非永続・切断で自動消去）。プロフィールのみ UserDefaults |
| 外部依存 | なし（純正フレームワークのみ） |
| デザイン | Aurora カラー UI（テーマカラー選択・ガラス質感）。当初はモノクロ設計だったが進化 |

---

## 2. App Store Connect 情報（最重要）

| 項目 | 値 |
|------|-----|
| **Apple ID（アプリID）** | `6760606408` |
| **Bundle ID** | `com.yuuki.AirTalk` |
| SKU | `com.yuuki.AirTalks` |
| Team ID | `976WT2WW6X` |
| 主要言語 | 日本語 |
| 価格 | 無料 |
| カテゴリ | ソーシャルネットワーキング |
| 直接URL | https://appstoreconnect.apple.com/apps/6760606408 |
| 現在のビルド | **1.2(7)** が公開中 / **1.2.1(8)** を提出準備中 |

### AirTalk Plus / サブスクリプション

| 項目 | 値 |
|------|-----|
| サブスクリプショングループ | `AirTalk Plus` (`22193555`) |
| 月額商品 | `com.yuuki.AirTalk.plus.monthly` (`6785129209`) |
| 年額商品 | `com.yuuki.AirTalk.plus.yearly` (`6785129341`) |
| 価格 | 月額 300円 / 年額 2,900円を基準に、全 App Store 地域へ等価価格を設定 |
| 導入オファー | 月額のみ 1週間無料トライアル |
| 提供国 | 全 App Store 地域（基準テリトリ: 日本 `JPN`） |
| 2026-08-01 時点のASC状態 | アプリ本体 `1.2(7)` およびサブスクリプション2商品は承認・公開済み |

> ⚠️ 注意: 作業途中、ログの混線で「AirWish(6740192837) という別アプリを作った」と誤認した時期があったが、**それは誤り**。Bundle ID が同一のため同じアプリで、全成果は `6760606408` に入っている。

---

## 3. 実装した機能

- **オンボーディング**: プロフィール作成（ニックネーム・SF Symbolsアイコン/カスタム写真・テーマカラー・ひとこと）、利用規約同意（EULA）
- **レーダー画面**: 周囲のピアを波紋アニメ付きで円形表示、タップで接続リクエスト
- **1対1チャット**: メッセージ送受信、絵文字リアクション、相手アバター表示、接続状態インジケーター
- **通報・ブロック**: チャットの「…」メニュー。ブロックは表示名を UserDefaults に永続化し、発見・招待から除外（ガイドライン1.2対応）
- **プロフィール画像のP2P交換**: 接続後に型安全な `NetworkPacket` でフルプロフィールを交換
- **自動シュレッダー**: 切断・バックグラウンド移行でメッセージを即時消去
- **権限拒否ハンドリング**: ローカルネットワーク/Bluetooth 権限拒否時に案内＋設定誘導
- **AirTalk Plus**: StoreKit 2 の月額/年額サブスクリプション。Hostバッジ、プロフィールフレーム、プロフィールプリセット、アイスブレイク、追加リアクション、プレミアムテーマを解放。発見・招待・1対1チャット・通報/ブロックは無料のまま維持。

---

## 4. アーキテクチャ

```
AirTalkApp (@main)
├── MultipeerManager (@StateObject) … 全P2Pロジック・状態
├── PurchaseManager (@StateObject) … StoreKit 2 商品取得・購入・復元・権利状態
└── Views (@EnvironmentObject)
    ├── OnboardingView      初回起動・プロフィール作成・EULA同意
    ├── DiscoveryView       レーダー(RadarView)・プロフィール編集
    │   └── AvatarView
    ├── ChatView            チャット・通報/ブロック
    └── Components/
        ├── AuroraBackgroundView
        └── MessageBubble   リアクション付き吹き出し
```

- データモデル: `AirMessage` / `UserProfile` / `ThemeColor` / `NetworkPacket`(P2Pエンベロープ) / `ReactionEvent`
- 画像処理: `UIImage+Resize.swift`（512px・JPEG品質0.85・中央クロップ・向き補正）

---

## 5. 本プロジェクトの作業ログ（主要マイルストーン）

1. **起動クラッシュ修正** — `discoveryInfo` にプロフィール画像を載せ400バイト制限を超過していたのを除外
2. **リリース品質改修** — 権限ハンドリング・空状態UI・プロフィール画像P2P交換・入力制限・UX磨き込み
3. **画質改善** — 壊れていた `UIImage+Resize` を書き直し（品質0.5→0.85, 200px→512px）
4. **App Store 提出パイプライン構築** — fastlane 導入、API Key 検証、アプリ枠・暗号化申告
5. **アプリ名の確定** — 一時 AirWish にしたが、最終的に **AirTalk** に統一
6. **通報・ブロック・EULA実装** — ガイドライン1.2対応
7. **スクリーンショット作成** — 実機2台が要る画面はデモデータ(`DEMO_SCREEN`)で撮影
8. **メタデータ・スクショ登録、サポートページ公開**
9. **実機2台で動作確認**（ユーザー実施）
10. **ビルド 1.0(3) を審査提出**
11. **AirTalk Plus 実装** — StoreKit 2、Paywall、Plusプロフィール装飾、追加リアクション/アイスブレイク、ASC商品作成
12. **AirTalk Plus 1.2 初回提出** — `1.2(6)` を App Store Connect にアップロードし、アプリ本体を提出。初回サブスクリプションを同時提出できず、2商品とも `READY_TO_SUBMIT` のままだったため 2.1(b) で却下。
13. **AirTalk Plus 1.2 再提出対応** — Paywall に正式なプラン名・期間・価格・利用規約/プライバシーポリシーリンクを明示。App Store 説明文に EULA / Privacy URL を追加し、キーワードから `匿名` を削除。`1.2(7)` をアップロードし、App Store version 1.2 に紐づけ。
14. **1.2 公開** — AirTalk Plus とアプリ本体が承認され、App Store で公開。
15. **1.2.1 品質改善** — P2P受信データ検証、入力サイズ制限、送信失敗時の表示修正、履歴上限、購入再読み込み、プライバシーマニフェストを整備。

### コミット履歴（メインリポジトリ）
| コミット | 内容 |
|---------|------|
| `80b5e75` | リリース品質改修・画質改善 |
| `3a1f9c2` | 提出パイプライン構築（一時 AirWish 改名） |
| `4c2f8e1` | 通報・ブロック・EULA |
| `5d3e9f2` | アプリ名を AirTalk に統一 |
| `6e8a1c4` | ビルド番号を 3 に |
| `7f3a2d9` | 審査提出用 submit lane 追加 |

---

## 6. リポジトリ・公開ページ

| 対象 | 場所 | 公開設定 |
|------|------|---------|
| メインリポジトリ | `YuukiKawabata/AirTalk` | **private** |
| サポートページ用リポジトリ | `YuukiKawabata/airwish-support` | **public** |
| サポート/プライバシー/利用規約ページ | https://yuukikawabata.github.io/airwish-support/ | 公開中 |

> サポートページは App Store のサポートURL・プライバシーポリシーURL として使用。サポート・プライバシーポリシー・利用規約（無寛容ポリシー）を1ページに収録。

---

## 7. fastlane の使い方

`fastlane/Fastfile` に定義。認証は App Store Connect API Key。実行前に環境変数を設定する:

```bash
export ASC_KEY_ID=<Key ID>
export ASC_ISSUER_ID=<Issuer ID>
export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<KeyID>.p8
```

> 🔑 API Key（`.p8`）は `~/.appstoreconnect/private_keys/` に配置（リポジトリ外）。`.gitignore` で `*.p8` を除外済み。Key ID / Issuer ID の実値はこのリポジトリには記載しない（手元で管理）。

### lane 一覧

| lane | 用途 |
|------|------|
| `verify` | API Key 疎通確認・最新ビルド番号の取得 |
| `create_app` | App Store Connect にアプリ枠を新規作成（作成済みなので通常不要） |
| `upload_meta` | メタデータ・スクショをアップロード（審査提出はしない） |
| `beta` | アーカイブ → TestFlight アップロード |
| `submit` | 既存ビルドで審査提出（ビルド・メタ再送なし・手動公開） |
| `release` | アーカイブから審査提出まで一括 |

> アーカイブ時は `GYM_XCARGS="-allowProvisioningUpdates"` を併用（自動署名のプロファイル取得のため）。

### 新ビルドを上げて再提出する手順（リジェクト対応時など）
```bash
# 1. ビルド番号を上げる（pbxproj の CURRENT_PROJECT_VERSION）
# 2. TestFlight へアップロード
GYM_XCARGS="-allowProvisioningUpdates" fastlane beta
# 3. 処理完了を待って審査提出（Fastfile の submit の build_number を更新）
fastlane submit
```

---

## 8. 提出時の重要設定

- **暗号化申告**: `Info.plist` の `ITSAppUsesNonExemptEncryption = false`（標準暗号化のみ・独自暗号化なし）
- **App プライバシー**: 「データを収集していません」。`AirTalk/PrivacyInfo.xcprivacy` で宣言
- **審査メモ（重要）**: MultipeerConnectivity は**実機2台が必須**。これを審査メモに明記しないとリジェクトされやすい（英文は [RELEASE.md](RELEASE.md) §3）
- **年齢レーティング**: ユーザー間通信あり＋モデレーション（通報・ブロック）ありで正直に回答

---

## 9. 遭遇したトラブルと解決

| トラブル | 原因 | 解決 |
|---------|------|------|
| 起動直後にクラッシュ | `discoveryInfo` に画像を載せ400バイト制限超過 | 画像を除外し、接続後のP2P交換に変更 |
| 2つのアプリがあるように見えた | ログ混線で存在しない「AirWish」を誤認 | Bundle ID 一致を確認し、提出先 AirTalk(6760606408) で確定 |
| ドキュメントが Git に出ない | `.gitignore` が `*.md` を無視していた | `*.md` 除外を解除 |
| 画像の画質が悪い | 圧縮設定が低く、ファイルが壊れていた | 512px・品質0.85で書き直し |

---

## 10. 今後の流れ

```
現在: 1.2(7) 公開中 / 1.2.1(8) 品質改善版を提出準備中
   ↓
Archive / Validate / App Store Connect へアップロード
   ↓
1.2.1 を審査提出 → 手動公開
```

- ガイドライン1.2系（通報・ブロック・EULA）は対策済みのためリジェクトリスクは低減済み
- AirTalk Plus は任意機能の解放に限定し、無料のコア体験を維持している
- サブスクリプション2商品は承認済みのため、1.2.1 での再提出は不要

---

## 11. 関連ドキュメント

- [README.md](../README.md) — プロジェクト概要
- [docs/SPEC.md](SPEC.md) — 技術仕様
- [docs/RELEASE.md](RELEASE.md) — App Store リリース手順・審査メモ英文・チェックリスト
- [CLAUDE.md](../CLAUDE.md) — 開発ガイド
