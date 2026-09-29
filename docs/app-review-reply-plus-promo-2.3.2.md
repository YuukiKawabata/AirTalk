# App Review 返信メモ（AirTalk Plus プロモーション画像）

- 対象提出ID: 33ddeb23-4fb0-4771-b7db-c7ae44ed05e2（レビュー環境の提出ID: b5ed622a-5064-4564-8ec0-49093643edc8）
- 対象: サブスクリプショングループ `AirTalk Plus` (`22193555`)、月額 `com.yuuki.AirTalk.plus.monthly` (`6785129209`)、年額 `com.yuuki.AirTalk.plus.yearly` (`6785129341`)
- 指摘: Guideline 2.3.2 — Performance - Accurate Metadata
  「プロモーション画像がアプリのスクリーンショットになっている」（3件とも同じ指摘）
- 原因: プロモーション画像 `05-paywall-promo.jpg` は、Paywall 画面を再現した審査用スクリーンショット
  （`05-paywall-review.jpg`）を 1024×1024 に縮めただけのもので、アプリの画面そのものに見えていた。
- 対応:
  - UI（端末フレーム・ボタン・価格・ステータスバー）を一切含まない独自のアートワークを作成した
    （`docs/make-subscription-promo-images.mjs` で生成）。
  - 絵柄は Plus で解放される機能を表す: プレミアムフレーム付きのプロフィール、Host バッジ、
    プロフィールプリセット（重なったカード）、プレミアムテーマ（色見本）、追加リアクション（吹き出し）。
  - 月額と年額で配色とラベル（MONTHLY / YEARLY）を分け、どの商品の画像かが分かるようにした。
  - 価格は入れていない（地域ごとに価格が違い、変更すると画像が不正確になるため）。
  - 審査用スクリーンショット（`05-paywall-review.jpg`）はプロモーション画像とは別枠なので変更しない。

## 差し替え手順

```bash
node scripts/asc/fix-plus-promo-images.mjs
```

- 月額・年額の画像を差し替え（既存画像は削除）、Apple 側の処理完了を待ってから2商品を再提出する。
  アップロードの失敗は3回までやり直す（年額は 2026-06 に `500 UNEXPECTED_ERROR` が出たことがある）。
- 認証情報は `~/.appstoreconnect/asc.env`。無い環境では環境変数 `ASC_KEY_ID` / `ASC_ISSUER_ID` /
  `ASC_KEY_P8`（.p8 の中身）または `ASC_KEY_PATH` を読む。
- 画像を作り直す場合は先に `node docs/make-subscription-promo-images.mjs`。
- App Review への返信は ASC API に無いので、必要なら下の英文を ASC の App Review ページから送る
  （再提出だけでも審査は進む）。

## App Store Connect の App Review へ返信する英文

```
Hello,

Thank you for your feedback regarding Guideline 2.3.2.

We have replaced the promotional images for all AirTalk Plus subscriptions:

- AirTalk Plus Monthly (com.yuuki.AirTalk.plus.monthly)
- AirTalk Plus Yearly (com.yuuki.AirTalk.plus.yearly)

The previous images were derived from an app screenshot. The new images are original
artwork created specifically for promotion and contain no screenshots or app UI.
They illustrate what AirTalk Plus unlocks: a premium profile frame, the Host badge,
saved profile presets, premium profile themes, and extra reactions. Each image is
labeled "MONTHLY" or "YEARLY" so it matches the subscription it promotes. No prices
are shown in the images.

Nearby discovery, chat requests, one-to-one chat, reporting, and blocking remain free.

We have resubmitted both subscriptions for review. Thank you for your time.
```
