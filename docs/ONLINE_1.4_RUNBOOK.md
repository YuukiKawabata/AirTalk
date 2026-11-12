# AirTalk 1.4 オンライン限定検証：実装・引き継ぎ

更新: 2026-11-07 / ブランチ `feature/1.4-growth`。
ユーザーの「できないことは後回しで最後まで進める」に従い、設計確認待ちを解除して実装した。
無料検証のみ。有料化、App Store審査提出・公開、ASCの商品／価格変更、git pushは別途確認する。

## 今回できたこと

- iOSの任意オンライン導線。既存オフラインのレーダー・招待・1対1・Plusは維持。
- Appleログインのクライアント／サーバー処理、同意・18歳以上自己申告、Keychainセッション、明示的アカウント削除。
- すれ違い一覧、申請、受信者による承認、オンライン1対1、双方が希望した場合だけつながりを保存。次回も承認が必要。
- CoreBluetoothによる双方のP-256署名付き交換。プロフィール・GPS・チャット本文をBLE配信しない。
- TLS/WSS中継。サーバー本文保存なし。アプリ内本文はメモリーのみ。退出・背景・接続終了で消去。E2EEではない。
- 通報理由の送信、双方方向のブロック、管理者による停止／削除、本文なしAPNsリクエスト通知のコード。
- 日英、Debug専用デモ、ローカルの実通信スモークテスト。

**一般公開できる完成版とはまだ扱わない。** 実機、Apple資格情報、APNs、無料プランの確認とクラウド配置、運営・ストア表示の更新が残る。未確認を成功とは記録しない。

## 設計からの具体化・変更

`ONLINE_1.4_DESIGN.md` は当初案。実装の現状は本書を優先する。

| 項目 | 限定検証の実装 |
|---|---|
| サーバー | Workers + **1個のSQLite-backed Durable Object**。最大50アカウント。D1は使わない |
| 理由 | 小規模では全認証・相互承認・ブロック・WS処理を同じオブジェクトで直列化し、別DBとの判定競合を避ける |
| 保存 | DOの `control` に会話以外の状態。WS attachmentはアカウント／ルーム／セッション識別子・制限・重複排除IDのみ。本文を入れない |
| 会話 | 参加者固定・使い捨てroom ID。終了roomは再開せず、次の承認で新IDを発行。独立epochフィールドは不要 |
| 送信確認 | `relayed` は相手ソケットへの中継成功。相手が読んだ／画面に表示した証明ではない。自動再送なし |
| 期限 | access 15分、refresh最大30日。更新／再ログインは古い接続を終了。会話中は15秒heartbeat、45秒で失効。15分を越す連続会話は初版では終了する |
| BLE token | 発行後最大24時間。前景復帰時に15分以上経過なら更新。背景で15分ごとの更新は保証しない。期限切れの証明は受け付けない |
| BLE検証 | token/challengeの正規化文字列を双方が署名し、サーバー登録鍵で検証。relay攻撃・実際の距離・正確な時刻は証明しない |
| すれ違いの期限 | サーバー受理から最大24時間かつ双方tokenの失効時刻まで。端末時刻の自己申告を信頼しない。実際の接触時刻と一致する保証なし |
| 保存関係 | つながりは片方が解除するかアカウント削除まで。通常会話本文は保存しない |
| バックアップ | SQLite DOのTime Travelは最大30日。論理削除とバックアップ消去は別。**この検証環境では過去状態の復元を運用禁止**。削除済みデータを復活させない復旧設計を完成してから解除する |
| 制限 | API全体20,000/日、利用者300/分、申請20/日、token100/日、通報等30/日。本文1,000 Unicode scalarかつ4,000 UTF-8 bytes。WS8KB、端末履歴200件 |
| リトライ | 申請は同じペアのpending/acceptedを再利用。その他は状態検証で二重処理を拒否。汎用Idempotency-Keyの保存基盤は未導入 |

[Cloudflare: SQLite storage / 30日復元](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/)

## ローカルで動かす

必要: Node、npm、Xcode。iOS本体に外部SDKは追加していない。サーバーではJWT処理の `jose` と開発用Wrangler/Miniflare等を使用。lockfileを共有する。

```bash
cd /Users/yuki/dev/AirTalk/server
npm ci
npm run check
npm test
npm run dev
```

`npm test` はdry-run bundleと9件の自動テストを実行する。`npm run dev` は127.0.0.1:8787だけで待ち受ける。
local設定の `/v1/dev/login` と `/v1/dev/encounter` はApple認証／BLEの代替テスト用。productionモードで拒否することをテスト済み。local設定をクラウドにデプロイしない。

iOSの動作確認ではKeychainが必要なので署名付きシミュレータビルドを使う。署名なしビルドはコンパイル確認には使えるが、ログイン動作確認には使わない。

```bash
cd /Users/yuki/dev/AirTalk
xcodebuild -project AirTalk.xcodeproj -scheme AirTalk -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
xcrun simctl launch <SIMULATOR_UDID> com.yuuki.AirTalk \
  -demo NO -onlineURL http://127.0.0.1:8787 -onlinePilot YES
```

ローカル画面でテスト名を入力して入る。通常の起動では `onlineURL` がなくオンライン導線は表示しない。
`-onlineTestName <name> -onlineTestJoin YES` はDebug＋loopback限定の自動確認用。署名・同意の本番経路を置き換えない。

実通信スモークテスト（ローカルサーバーとシミュレータを起動済みにする）:

```bash
cd /Users/yuki/dev/AirTalk/server
SIMULATOR_UDID=<UDID> AIRTALK_SIM_APP=<Debug-iphonesimulator/AirTalk.appの絶対パス> \
  node test/simulator-smoke.mjs
```

検証用2アカウントを作り、iOSから会話を開始、別のWSクライアントから送信・ブロックし、画像を保存してテストアカウントを削除する。実在ユーザーを使わない。

## Cloudflareへの接続準備

今回の環境にはWranglerの既存ログインがあった。アカウントのサブスクリプション一覧APIは403で、**Workers無料プランであることを確認できなかったためデプロイしなかった**。契約・プラン変更はしていない。

1. Cloudflare管理画面で対象アカウントのWorkersプランがFreeであることを確認。既存Paidなら追加利用を無料とみなさず、費用確認を挟む。
2. `server/wrangler.jsonc` はproduction、オンライン停止、workers.dev非公開が初期値。既存Workerを上書きせず `airtalk-online-pilot` の名前の重複を確認する。
3. 以下をWrangler secretとして登録。リポジトリやアプリに埋め込まない。
   - `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`: Sign in with Appleの専用設定。
   - `TOKEN_ENCRYPTION_KEY`: 32ランダムbyteのbase64url。Apple refresh tokenのAES-GCM暗号化用。変更は再ログインが必要で、保持中の失効ジョブを先に処理する。
   - `INVITE_CODE`: 限定検証の招待コード。公開ストア文言に書かない。
   - `ADMIN_TOKEN`: 32文字以上のランダム秘密値。アプリには配布しない。
   - 通知を使う場合: `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`。`APNS_ENVIRONMENT` はsandboxまたはproductionをビルドと合わせる。
4. 初回は `ONLINE_ENABLED=false` のままdry-run→配置し、ログ・経路・秘密値・上限・管理者アクセスを確認する。
5. 18歳以上の検証協力者だけに案内できる状態でHTTPS経路と `ONLINE_ENABLED=true` を設定する。審査提出／一般公開は別途確認。
6. `ONLINE_ENABLED=false` で新規APIを止める。既存WSも次のイベント／alarmで閉じる。即時の運営停止は対象アカウントのsuspendで遮断する。

## AppleとiOSの設定

- Sign in with AppleをApp IDに設定し、鍵をサーバーへ登録する。既存ASC APIキーをAppleログインやAPNsキーとして流用しない。
- `Config/OnlinePilot-Info.plist` / `Config/OnlinePilot.entitlements` は限定検証用のテンプレート。通常のプロジェクト設定には適用していない。
- 限定実機ビルドでは `INFOPLIST_FILE=Config/OnlinePilot-Info.plist`、`CODE_SIGN_ENTITLEMENTS=Config/OnlinePilot.entitlements`、`AIRTALK_ONLINE_BASE_URL=https://...` を設定。署名プロファイルも更新する。
- `aps-environment` は開発端末でdevelopment、配布でproduction。通知の登録・受信・無効token処理は実機で確認する。
- 通知の許可はオンライン設定から明示的に求める。通知には「リクエストがあります」という定型文だけを入れ、本文・名前・距離は入れない。失効期限0で配達できなかった通知は再送しない。
- 初期検証は18歳以上自己申告。本人／年齢確認済みとは表示しない。未成年向けの分離・保護は未実装。

## データと運営

| データ | 稼働データの保持 |
|---|---|
| Apple subject、プロフィール、公開同意、公開鍵 | アカウント削除まで。メール／実名scopeは要求しない |
| 検出token、署名照合の重複排除ID、すれ違い、申請 | 最大24時間。期限は読み取り時とalarmで適用 |
| 端末の署名証明待ちキュー | Keychain、この端末のみ、最大100件・24時間。本文・GPSなし |
| つながり、ブロック | 関係解除／アカウント削除まで |
| 通報 | 理由カテゴリ・報告者ID・対象IDのみ90日。本文添付なし |
| 運営停止の照合ハッシュ | 180日。アカウント削除後の再登録対策。鍵の変更時は移行設計が必要 |
| Apple失効処理用の暗号化refresh token | 削除時に失効ジョブへ。成功時消去、失敗再試行は最大35日。失敗を放置せず管理者が確認する |
| API制限カウンター | 最長24時間。ログイン制限ではIPのハッシュを使用。生IPをDBに保存しないが匿名データとは呼ばない |
| メッセージ | 永続化しない。サーバー中継・端末表示のメモリーだけ |

`GET /admin/reports` は通報一覧と未完了失効件数。`POST /admin/suspend` / `/admin/delete` は `{accountID}`。管理者Bearerが必要。
管理者は通報を毎日確認し、停止・誤判定の問い合わせ・削除依頼を扱う。アカウント停止中も有効なセッションで `DELETE /v1/me` は可能。本人がサインインできない場合は運営対応が必要。
ログは無効化している。`console.log` やエラー収集SDKへ本文／トークンを出さない。Cloudflare自体のネットワーク・セキュリティログまで「一切ない」とは説明しない。

## 公開前に残っている項目（後回し）

| 項目 | 状態／次の確認 |
|---|---|
| BLE実機2台・前景／背景／ロック・復元・強制終了・省電力 | 未実施。GROWTH_1.4の測定表を使う。特に両背景で署名交換が10秒以内に収まるか |
| BLE長時間のtoken更新 | 背景の15分ローテーションは未実装。最大24時間で失効。常時検出・短時間すれ違いを約束しない |
| 無料プラン・クラウド配置 | 課金API403で確認不可。管理画面で確認後に配置。Apple設定がないため外部利用はまだ不可 |
| Apple実ログイン・失効・削除 | コード／失敗時の拒否は実装。鍵・entitlements・実アカウントの統合確認は未実施 |
| APNs | コード実装。鍵・環境・端末の実配達は未確認 |
| 自動コンテンツフィルタ、問い合わせ先、通報運営 | リンク・メールアドレス・連続文字・明示的脅迫の簡易フィルタを実装。文脈・全言語を判定するものではない。限定検証でも運営を用意し、公開前に範囲・誤判定対応を確認する |
| バックアップ復元 | 検証環境では禁止。復旧後に削除／停止を再適用する外部台帳と検証が必要 |
| 非機能 | 実インターネット切断・遅延・サーバー障害・負荷・費用実測が未実施 |
| ストアとプライバシー | 現行ストア／PrivacyInfoは変更していない。オンライン有効版配布前に収集内容・目的・関連付け・規約を更新。「収集しない」をそのまま使わない |

審査提出・公開、ASC商品／価格変更、git pushはいずれも未実施。

## 実行済みの確認結果

- `scripts/check-online.sh`: TypeScript、dry-run bundle、9サーバーテスト、BLE policy／オンライン画面試作テスト、diffチェック成功。
- Debug署名付きシミュレータ／Release実機向け署名なしビルド成功。通常Releaseのオンライン有効フラグ・BLE背景モードは未設定。
- 最新コードでiOSのURLSession APIとWebSocketをローカルWorkerに接続。受信画像と遠隔ブロック後の本文／カード消去を確認。実機通信ではない。
- `npm audit`: 検査時点で指摘0件。新規オンライン文字列に英訳漏れなし。
- クラウド配置・Apple実認証・APNs実配達・BLE実機測定は未実施。

### 2026-11-07 外部設定と運営準備の更新

対象Bundle IDのApple ID認証（primary app）とPush Notificationsを登録し、APIの再取得で両方を確認した。次のApple設定は各サービス用の鍵と署名プロファイル。秘密鍵本文はチャットに送らず、手元のファイルから設定する。

オンライン利用条件・削除・通報保持期間・問い合わせメールを日英で追加。サインイン前、同意画面、オンライン設定から開ける。一般向けサポートサイトの更新案はローカルの別チェックアウト `/Users/yuki/dev/airwish-support-airtalk-pilot/index.html` に用意した。公開に使うgit pushはユーザー確認が必要。

### オンライン有効版のApp Privacy回答案（ASC入力前）

用途はアプリ機能。アカウントに紐づけて保持するデータは「ユーザーに関連付けられる」として扱う。広告目的のトラッキングは行わない。以下は公開用回答の下書きで、現行1.3のストア表示はそのまま。

| 実際のデータ | 回答案／確認点 |
|---|---|
| Apple subject、内部アカウントID | Identifiers → User ID |
| APNs token、登録端末の公開鍵 | Identifiers → Device ID。任意の通知・すれ違いも対象に含めて評価 |
| ニックネーム、自己紹介 | User Content → Other User Content。実名・メールのAppleスコープは要求しない |
| すれ違い記録、申請、承認、つながり、ブロック | Usage Data → Product Interaction。正確な場所・座標を保存する設計ではない |
| 通報理由、サポートメール | User Content → Customer Support。メールで受け取る返信先はContact Info → Email Addressの要否も、実際の保管方法に合わせて確定 |
| 年齢の自己申告、認証時のIPハッシュ | Other Data Typesを候補に、保持方法とAppleの定義を照合 |
| 通常のチャット本文 | 中継の間だけ処理。本文をログ・通報・バックアップに含める変更をした場合は回答を見直す |

公開直前にCloudflare側の実際のログ設定、既存オフライン通報で利用者がメールに添付できる内容、サポート受信箱の運用も含めて確定する。[AppleのApp Privacy定義](https://developer.apple.com/app-store/app-privacy-details/)

2026-11-07、対象アカウントの請求画面で「Workers Free アクティブ」を確認。既存Workerとの名前重複がないことを確認し、airtalk-online-pilot と SQLite Durable Object の初回配置を完了した。バージョンは 10b673d8-e523-4113-8e0c-dcbdd5305e18。公開経路なし、ONLINE_ENABLED=false。次はApple Developerの鍵一覧で用途と対象を照合して秘密値を設定する。

2026-11-07、AirTalk専用Appleログイン鍵 NV7G67JAD5 を対象WorkerのSecretに登録。APPLE_PRIVATE_KEY、APPLE_KEY_ID、APPLE_TEAM_ID、TOKEN_ENCRYPTION_KEY、INVITE_CODE、ADMIN_TOKENの6件を一覧で確認した。生成した運営用3値の控えはMacの ~/.config/airtalk-pilot/pilot-secrets.json（所有者のみ読み書き）。APNsの資格情報と外部接続の有効化は別工程。

2026-11-07、AirTalk Pilot Push（Key ID A2V29RW3V6）をSandbox、Topic Specific、com.yuuki.AirTalk限定で作成した。対象WorkerにAPNS_PRIVATE_KEY、APNS_KEY_ID、APNS_TEAM_ID、APNS_ENVIRONMENTを登録し、Secret一覧で4件を確認。実端末への通知配達は未検証。

### 限定検証の接続先と開発署名ビルド（2026-11-07）

招待制APIをWorkers Freeで有効化。接続先は https://airtalk-online-pilot.yorozu-works.workers.dev 、配置版は 0b9749c5-240b-4f00-9128-f46fb4483dd4。healthから稼働応答を確認。招待コードは既存の所有者限定ファイルから取得する。起動停止はONLINE_ENABLEDをfalseにして再配置する。

登録済みiPhone向けビルドは次で再作成できる。

```bash
xcodebuild -project AirTalk.xcodeproj -scheme AirTalk -configuration Debug -destination 'generic/platform=iOS' -xcconfig Config/OnlinePilot.xcconfig -derivedDataPath build/online-pilot -allowProvisioningUpdates build
```

成果物は build/online-pilot/Build/Products/Debug-iphoneos/AirTalk.app。端末を用意できたらXcodeのDevices and Simulatorsからインストールする。実機でのAppleログイン・通知受信・BLE・消費電力の確認は保留。

### 1.4限定検証版に同梱するプライバシー宣言

OnlinePilot.xcconfig は Config/Pilot/PrivacyInfo.xcprivacy を指定する。申告はアプリ機能に使用する利用者ID、端末ID、ユーザーコンテンツ、利用状況、サポート対応、メールアドレス、その他のデータの7分類。通報とサポートメールは保守的にアカウントに関連付けられる情報として含めた。トラッキングは行わない。通常版は AirTalk/PrivacyInfo.xcprivacy を使用する。このファイルとASCの公開回答は別途管理する。

登録済み端末で限定検証に参加するときは、次のコマンドで招待コードだけをMacのクリップボードにコピーできる。

```bash
python3 -c 'import json,pathlib,sys; sys.stdout.write(json.loads((pathlib.Path.home()/".config/airtalk-pilot/pilot-secrets.json").read_text())["INVITE_CODE"])' | pbcopy
```

### 限定検証の通報を確認する

AirTalkリポジトリで `node scripts/pilot-admin.mjs reports` を実行する。数値は90日の保持期間内の通報総数で、対応済みも含む。Apple認証の失効処理待ち件数も同時に表示する。対象ID・理由・期限は担当者の端末で扱う。

通報理由を確認し、停止が必要と判断したときは `node scripts/pilot-admin.mjs suspend <対象のUUID>` を実行する。対象IDを再入力すると進行中の会話を終了し、利用を停止する。誤停止の問い合わせはサポート窓口で受け付ける。誤停止を確認した場合は `node scripts/pilot-admin.mjs restore <対象のUUID>` を実行し、対象IDを再入力する。解除後もブロックは有効で、終了した会話は復元されない。

### 2026-11-12 一般公開化（招待コード廃止）と登録後の案内

- サーバー：`/v1/auth/apple` の招待コード照合を削除。1.4のアプリが送る `inviteCode` は無視する。
- 保存方式：全状態を1つの値（`control`）に入れて毎回丸ごと書き直す方式から、Durable ObjectのSQLiteテーブル（アカウント・セッション・すれ違い等ごと、利用者IDで索引）に変更。1リクエストの処理量は登録者数に比例しない。旧 `control` は初回起動時に一度だけ自動でテーブルへ移す（`tables-v2` が移行済みの目印。旧版へ戻せるよう `control` 自体は凍結して残す。ログイン状態・すれ違い・申請・通報・停止情報を保持。進行中の会話とチケットは引き継がない）。旧版で作ったデータを新版で読むローカル検証済み。
- 登録上限：既定なし。緊急時は環境変数 `MAX_ACCOUNTS` で上限を設定でき、到達時は `pilot_full`（503）。全体の1日上限は `GLOBAL_DAILY_LIMIT`（既定500万リクエスト）。毎分・毎時・全体の流量制限はメモリ上で数え、通常の読み取りでは行を書き込まない。
- Apple認証・Appleトークン確認・APNs送信・Apple失効処理は、直列化された処理の外で行う（1件の遅い通信で全員が待たない）。リクエスト本文も直列化の前に読む。
- 計測（ローカルWorker、5000人登録時）：登録0.4ms、すれ違い一覧0.3〜0.5ms/件。
- 運用：`node scripts/pilot-admin.mjs reports` で登録者数も表示する。
- Cloudflare無料プランの1日上限（Workers 10万リクエスト、Durable Objects 10万リクエスト・書き込み10万行など）が先に上限になる。アプリを1回開くと約6リクエスト。利用が増えたらWorkers Paid（月5ドル〜）へ切り替える。
- アプリ（1.4.1 / ビルド11）：招待コード欄を削除。サインイン用challengeは画面表示時と失敗後に自動で取り直す（以前は一度失敗すると同じchallengeを再利用して失敗し続けた）。登録完了直後に「すれ違い検出とリクエスト通知をオンにしますか？」を表示し、オンにすると検出開始とOSの通知許可を要求する。設定（歯車）から変更できることも案内する。
- ローカル検証：シミュレータで登録 → 案内表示 → オンにする → OS通知許可 → 歯車メニューで検出オンを確認。実機・Apple実ログイン・BLE実測は未確認。
- `INVITE_CODE` のSecretは使わなくなったが削除していない。
- 2026-11-12 1.4.1(11)をアップロードし審査提出（承認後に自動公開）。説明文・新機能・審査メモ（ja/en）から招待コードの記載を削除済み。
