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

## 差し替え手順（Mac で実行）

```bash
node docs/make-subscription-promo-images.mjs        # 画像を作り直す場合のみ（生成済みの JPG はコミット済み）
node scripts/asc/upload-subscription-images.mjs docs/screenshots/promo/airtalk-plus-monthly.jpg 6785129209
node scripts/asc/upload-subscription-images.mjs docs/screenshots/promo/airtalk-plus-yearly.jpg 6785129341
node scripts/asc/submit-subscriptions.mjs           # 2商品を再提出
```

- `upload-subscription-images.mjs` は既存の画像を削除してから新しい画像を上げる。
- 年額で `500 UNEXPECTED_ERROR` が返った場合（2026-06 に発生）は、ASC の Web 画面
  （サブスクリプション > AirTalk Plus 年間プラン > App Store プロモーション > 画像）から手動で差し替える。
- 画像の差し替え後、ASC の App Review ページで下の英文を返信する。

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
