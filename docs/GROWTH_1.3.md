# AirTalk 1.3 改善記録（ASO・使い始めの体験）

2〜4週間後に効果を比べるための記録。数値は App Store Connect のアナリティクスから取得した。

- 作業日: 2026-09-25
- ブランチ: `feature/1.3-growth`
- 対象バージョン: 1.3 (build 9)
- 比較する日: 1.3 公開の2週間後と4週間後（公開日が決まったらここに書く）

## 1. ベースライン（2026-06-25〜09-23、90日）

| 指標 | 値 |
|---|---|
| 表示回数 | 3,242（週次 109 → 351） |
| ページ閲覧 | 423 |
| 新規DL | 94（8月下旬以降は週11〜13件） |
| 表示→DL率（ASC conversionRate） | 1.8%（6月）→ 7.1%（9月） |
| 閲覧→DL率 | 約22% |
| 削除 | 21（日本 6 / DL 18 = 33%） |
| クラッシュ | 0 |
| 課金者 / 売上 | 0 / 0円 |
| レビュー | 0件 |
| リテンション | データ不足で表示されない |
| 流入元 | App Store 検索が 97%（表示 3,137 / DL 86） |

### 国別（90日）

| | 表示 | 閲覧 | DL |
|---|---|---|---|
| 日本 | 491（15%） | 89 | 18（19%） |
| 海外合計 | 2,751（85%） | 334 | 76（81%） |
| インド | 557 | 74 | 13 |
| インドネシア | 225 | 43 | 6 |
| アルジェリア | 148 | 22 | 5 |
| フィリピン | 146 | 24 | 3 |
| トルコ | 100 | 19 | 7 |
| UAE | 75 | 10 | 6 |

### 1.3 以前の問題

- ストアページもアプリの UI も日本語だけ。ビルドには ja のローカライズが無く（`developmentRegion = en`）、App Store の対応言語が「EN」だけと表示されていた。
- 検索順位（iTunes Search API で見た目安）: 「近距離 チャット」11位、「オフライン チャット」「bluetooth チャット」圏外、米国の「offline chat」「bluetooth chat」「nearby chat」圏外。
- 「airtalk」の検索では米国の通信会社 AirTalk Wireless などが上位に並ぶ。海外の流入には、別のサービスを探している人が混ざっている可能性がある。
- 近くに誰もいないと「2台以上の端末でお試しください」と表示されるだけで、先に進めなかった。

## 2. 1.3 の変更内容

| # | 変更 | 狙う指標 |
|---|---|---|
| A | ストアに英語（en-US）のローカライズを追加。名前・サブタイトル・キーワード・説明文・プロモーションテキスト | 海外の閲覧→DL率、英語の検索語での表示回数 |
| B | アプリ本体を英語と日本語に対応（`Localizable.xcstrings` / `InfoPlist.xcstrings`、knownRegions に ja を追加）。対応言語が正しく「日本語・英語」になる | 海外の削除率、セッション数 |
| C | 日本語の名前・サブタイトル・キーワードを見直し（下記） | 日本の表示回数と検索順位 |
| D | 近くに誰もいないときの画面とツールバーに「友だちを誘う」を追加（QRコードと共有リンク） | 参照元（Web・アプリ・参照元なし）からのDL、アクティブ端末 |
| E | 初回起動時に説明を1画面追加（近くの人とだけ話せる／会話は残らない／友だちと始めよう＋権限を求める理由） | 削除率、権限拒否の減少 |
| F | プロモーションテキストを追加（日本語・英語） | 閲覧→DL率 |
| G | 成立した会話（自分と相手がそれぞれ2通以上送った会話）が終わった直後にレビューを依頼（1バージョンにつき1回） | レビュー数 |
| H | アイスブレイクを無料にした（Plus は Host バッジ、フレーム、プリセット、追加リアクション、プレミアムテーマ） | 最初の会話が成立する率（レビュー数から推測） |
| I | 英語版のストア用スクリーンショット（`docs/screenshots/en/store/`） | 海外の閲覧→DL率 |

アプリの表示名（ホーム画面の名前）は「AirTalk」のまま。ストア名は、同じ名前の通信会社と紛れないよう「AirTalks」を維持する。

## 3. ストアのメタデータ案

### 日本語（ja）

- 名前（22/30）: `AirTalks: オフライン近距離チャット`
- サブタイトル（19/30）: `ネット不要・半径50mの一期一会トーク`
- キーワード（95/100）: `ブルートゥース,トランシーバー,すれ違い,圏外,機内モード,メッセンジャー,イベント,ローカル通信,近く,会話,友達,勉強会,プライバシー,無線,P2P,サーバーレス,旅行,フェス,キャンプ`
  - 名前・サブタイトルに入っている語（オフライン・近距離・チャット・一期一会・ネット・トーク）は重複させない。
  - 英語の語（offline, bluetooth など）は en-US 側のキーワードで日本のストアでも検索対象になるため、ここには入れない。
- プロモーションテキスト（93/170。審査なしで今すぐ変更できる）:
  `圏外でも、機内モードでも。Wi-FiとBluetoothで、半径50mにいる人とだけ話せるチャットです。アカウント登録は不要、会話は離れると自動で消えます。イベントや旅先での一期一会に。`
- 説明文: 現行の文に次の段落を追加する。
  ```
  ■ 近くに誰もいないときは
  QRコードを見せれば、友だちがその場でAirTalkを入れられます。
  ```
- 新機能:
  ```
  ・初回起動時に使い方の説明を追加しました
  ・近くに誰もいないとき、QRコードやリンクで友だちを誘えるようになりました
  ・英語に対応しました
  ・アイスブレイク（最初の一言の定型文）を無料で使えるようにしました
  ・細かな表示を改善しました
  ```

### 英語（en-US）

- Name（29/30）: `AirTalks: Offline Nearby Chat`
- Subtitle（30/30）: `Bluetooth & Wi-Fi, no internet`
- Keywords（95/100）: `mesh,messenger,p2p,local,walkie,talkie,airplane,signal,festival,travel,event,proximity,wireless`
- Promotional text（154/170）:
  `Chat with people within 50 m (160 ft), no internet or account needed. AirTalks connects over Wi-Fi and Bluetooth, and messages vanish when you move apart.`
- Description:
  ```
  AirTalks lets you chat with the people right around you, and only them.

  No internet, no servers, no account. AirTalks uses Wi-Fi and Bluetooth to find people within about 50 m (160 ft) and connects you directly, one-on-one.

  ■ Conversations that don't last
  Messages live only in your device's memory. When you move apart or close the app, every message is deleted automatically. No history is ever kept.

  ■ Offline and serverless
  Messages travel directly from device to device, encrypted. Nothing goes through the internet, so it works where there's no signal, even in airplane mode with Wi-Fi and Bluetooth on.

  ■ Privacy first
  No sign-up. No personal data is collected or sent. Your profile (nickname, icon, and status) is stored only on your device.

  ■ Great for
  ・Meetups, conferences, and festivals
  ・Cafés and coworking spaces
  ・Travel, hostels, and places with no signal

  ■ Nobody nearby? Invite a friend
  Show a QR code and your friend can install AirTalks on the spot.

  Say hi, chat, and let it go when you part ways.

  Terms of Use (EULA): https://yuukikawabata.github.io/airwish-support/#terms
  Privacy Policy: https://yuukikawabata.github.io/airwish-support/#privacy
  ```
- What's New:
  ```
  • Added a quick intro on first launch
  • Invite friends nearby with a QR code or link
  • Now available in English
  • Icebreakers are now free for everyone
  • Minor UI improvements
  ```

### 主要言語の変更（提案）

主要言語を「日本語」から「英語（米国）」に変える。英語のローカライズが無いストアでは主要言語の内容が表示されるため、日本語のままだとインドネシアやトルコなどでは日本語のページが出る。英語にすれば、日本以外はすべて英語で表示される。日本には ja のローカライズがあるので影響しない。

## 4. 効果の見方

1.3 公開の2週間後と4週間後に、同じ API（`/analytics/api/v1/data/timeseries`）で公開前の同じ日数と比べる。

- 海外（日本以外）の閲覧→DL率と、DLに対する削除の割合
- 日本の表示回数と、「オフライン チャット」「bluetooth チャット」での順位
- 米国・インドで「offline chat」「bluetooth chat」「nearby chat」に表示されるか
- 流入元「参照元Web／参照元アプリ／参照元なし」からのDL（QR・リンクによる招待の効果）
- レビュー数
