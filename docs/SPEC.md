# AirTalk 技術仕様書

## 1. コンセプト

**「半径50mの一期一会」** — インターネットを使わず、物理的に近くにいる人とだけ会話できるローカルP2Pチャット。会話はメモリ上にのみ存在し、離れた瞬間にすべて消える。

---

## 2. デザインガイドライン

**テーマ: High-Contrast Minimalism（モノクロ）**

| 要素 | 指定 |
|------|------|
| カラーパレット | `#000000`（黒）, `#FFFFFF`（白）, `#8E8E93`（グレー）のみ |
| タイポグラフィ | San Francisco。見出しは Bold、本文は Regular |
| ボーダー | 1px 実線。角丸は `0`（シャープ）または `Capsule`（完全丸） |
| アイコン | SF Symbols `.monochrome` バリアント |
| ダークモード | 完全対応（黒白を反転） |

---

## 3. データモデル

### AirMessage

チャットメッセージを表す。ディスクへの永続化は禁止。

```swift
import Foundation

struct AirMessage: Identifiable, Codable {
    let id: UUID
    let sender: String    // MCPeerID.displayName
    let text: String
    let timestamp: Date
    let isMe: Bool        // 送信者が自分かどうか（UIの塗り分けに使用）
}
```

### UserProfile

ユーザーのプロフィール情報。`discoveryInfo` として Advertiser に載せる。

```swift
import Foundation

struct UserProfile: Codable {
    var name: String      // ニックネーム
    var status: String    // ステータス（一言メッセージ）
    var iconID: String    // プリセットアイコンの識別子（SF Symbols名）

    /// MCNearbyServiceAdvertiser の discoveryInfo 用
    var asDiscoveryInfo: [String: String] {
        ["name": name, "status": status, "iconID": iconID]
    }

    /// discoveryInfo から復元
    static func from(discoveryInfo: [String: String]) -> UserProfile? {
        guard let name = discoveryInfo["name"],
              let status = discoveryInfo["status"],
              let iconID = discoveryInfo["iconID"] else { return nil }
        return UserProfile(name: name, status: status, iconID: iconID)
    }
}
```

---

## 4. 通信ロジック（MultipeerManager）

`MultipeerManager` は `ObservableObject` として、通信の全ライフサイクルを管理する。

### 基本設定

| 項目 | 値 |
|------|-----|
| ServiceType | `airtalk` |
| セッション暗号化 | `.required`（MCEncryptionPreference） |
| トランスポート | Wi-Fi + Bluetooth（OS自動選択） |

### プロパティ（@Published）

```swift
@Published var discoveredPeers: [(peerID: MCPeerID, profile: UserProfile)] = []
@Published var connectedPeers: [MCPeerID] = []
@Published var messages: [MCPeerID: [AirMessage]] = [:]  // ピアごとのメッセージ履歴
```

### ライフサイクル

#### 起動時
1. `MCPeerID` を `UserProfile.name` で生成
2. `MCSession` を生成（暗号化: `.required`）
3. `MCNearbyServiceAdvertiser` を開始 — `discoveryInfo` に `UserProfile.asDiscoveryInfo` を設定
4. `MCNearbyServiceBrowser` を開始 — 周囲のピアを探索

#### ピア発見時（MCNearbyServiceBrowserDelegate）
- `browser(_:foundPeer:withDiscoveryInfo:)`: `discoveryInfo` から `UserProfile` を復元し、`discoveredPeers` に追加
- `browser(_:lostPeer:)`: `discoveredPeers` から削除

#### 接続フロー
1. ユーザーが DiscoveryView でカードをタップ
2. `browser.invitePeer()` で招待を送信
3. 相手側は `advertiser(_:didReceiveInvitationFromPeer:)` で**自動承認**（`invitationHandler(true, session)`）
4. 両者の `session(_:peer:didChange:)` で `.connected` を検知 → ChatView に遷移

#### メッセージ送受信
- **送信:** `MCSession.send(_:toPeers:with:)` で JSON エンコードした `AirMessage` を送信（`.reliable` モード）
- **受信:** `session(_:didReceive:fromPeer:)` で JSON デコードし、`messages[peerID]` に追加。`isMe = false` を設定

#### 切断時（オート・シュレッダー発動）
1. `session(_:peer:didChange:)` で `.notConnected` を検知
2. `messages[peerID]` を即座に空配列に置換して消去
3. `connectedPeers` から削除
4. UI に切断を通知（ChatView からの自動退出トリガー）

#### プロフィール更新時
1. 現在の Advertiser を停止
2. 新しい `discoveryInfo` で Advertiser を再生成・再開始

---

## 5. 画面構成・UI仕様

### 画面遷移図

```
[App Launch]
    │
    ├─ 初回起動 ──→ [OnboardingView] ──→ [DiscoveryView]
    │                                         │
    └─ 2回目以降 ──→ [DiscoveryView] ←────────┘
                          │
                     タップで接続
                          │
                          ▼
                      [ChatView]
                          │
                     切断で自動復帰
                          │
                          ▼
                    [DiscoveryView]
```

### 5.1 OnboardingView

**表示条件:** 初回起動時のみ（`UserDefaults` に `hasCompletedOnboarding` フラグを保存）

| 要素 | 仕様 |
|------|------|
| タイトル | "AirTalk" を大きく Bold 表示 |
| 名前入力 | 黒枠 TextField。プレースホルダー: "ニックネーム" |
| アイコン選択 | SF Symbols のプリセットから選択（横スクロール）。例: `person.fill`, `star.fill`, `flame.fill` 等 |
| ステータス入力 | 黒枠 TextField。プレースホルダー: "ひとこと"（例:「おすすめのカフェ教えて」） |
| 開始ボタン | 黒背景白文字の Capsule ボタン。名前が空の場合は disabled |

**保存先:** `UserDefaults`（プロフィール情報のみ。メッセージは保存しない）

### 5.2 DiscoveryView（メイン画面）

| 要素 | 仕様 |
|------|------|
| ヘッダー | "AirTalk" ロゴ（Bold）+ 自分のプロフィール編集ボタン（`gear` アイコン） |
| ピアリスト | `List` + `PlainListStyle`。各行は `ProfileCard` コンポーネント |
| 空状態 | "周囲にユーザーがいません" をグレーで中央表示 |
| プロフィール編集 | Sheet で表示。OnboardingView と同じフォーム（名前・アイコン・ステータス） |

#### ProfileCard コンポーネント

```
┌─────────────────────────────────┐
│  [icon]  ニックネーム            │
│          ステータス（グレー）     │
└─────────────────────────────────┘
```

- 白背景 + 黒枠 1px（ダークモード時は反転）
- タップで接続リクエスト送信

### 5.3 ChatView

| 要素 | 仕様 |
|------|------|
| ナビゲーションバー | 相手の名前 + 接続状態インジケーター（`"● Connected"`、グリーンは使わず黒丸） |
| メッセージ一覧 | `ScrollView` + `LazyVStack`。新着メッセージで自動スクロール |
| 入力エリア | 黒枠 TextField + 送信ボタン（`arrow.up.circle.fill`） |

#### MessageBubble コンポーネント

| 送信者 | スタイル | 配置 |
|--------|----------|------|
| 自分 | 黒背景 + 白文字 | 右寄せ |
| 相手 | 白背景 + 黒枠 + 黒文字 | 左寄せ |

- 角丸: 12pt
- 最大幅: 画面幅の 70%
- タイムスタンプ: バブル下部にグレー小文字で表示

#### 切断時の挙動

1. 画面上部にバナー表示: **「通信が途絶えました。メッセージは破棄されます。」**
2. 3秒後に DiscoveryView へ自動遷移
3. 遷移時にメッセージ配列をクリア（オート・シュレッダー）

### アニメーション

| トリガー | アニメーション |
|----------|----------------|
| ピア発見 | リストにフェードイン（`.transition(.opacity)`） |
| ピア消失 | リストからフェードアウト（`.transition(.opacity)`） |
| 切断バナー | 上からスライドイン（`.transition(.move(edge: .top))`） |
| メッセージ送信 | バブルがスケールイン（`.transition(.scale)`） |

---

## 6. オート・シュレッダー仕様

AirTalk の核心機能。「離れたら消える」を技術的に担保する。

### 原則

- メッセージは **メモリ上にのみ** 保持する
- `SwiftData`, `CoreData`, `FileManager`, `UserDefaults` によるメッセージの永続化は **一切禁止**
- スクリーンショット検知等の対策は Phase 1 では不要

### 消去トリガーと対象

| トリガー | 消去対象 |
|----------|----------|
| P2Pセッション切断（`.notConnected`） | 該当ピアとのメッセージ配列 |
| アプリ終了（`scenePhase == .background`） | 全メッセージ、全ピア情報 |
| 手動切断（ユーザー操作） | 該当ピアとのメッセージ配列 |

### 保持してよいデータ

- 自分のプロフィール情報（`UserDefaults`）
- オンボーディング完了フラグ（`UserDefaults`）

---

## 7. Info.plist 設定

MultipeerConnectivity を使用するために必須の設定。

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>周囲のユーザーと通信するためにローカルネットワークを使用します。</string>

<key>NSBluetoothAlwaysUsageDescription</key>
<string>近くのデバイスを発見するためにBluetoothを使用します。</string>

<key>NSBonjourServices</key>
<array>
    <string>_airtalk._tcp</string>
    <string>_airtalk._udp</string>
</array>
```

---

## 8. 実装上の注意点・アンチパターン

### 禁止事項

| やってはいけないこと | 理由 |
|----------------------|------|
| メッセージをディスクに保存する | オート・シュレッダーの設計原則に反する |
| `CoreData` / `SwiftData` を導入する | メッセージの永続化につながる |
| バックグラウンドでの通信維持を試みる | iOS の制約上不可能。切断を仕様として受け入れる |
| ServiceType に規約外の文字を使う | 15文字以内、小文字英数字とハイフンのみ |

### 留意点

- **バックグラウンド遷移**: アプリがバックグラウンドに回ると MultipeerConnectivity の接続は切れる可能性が高い。これは「離れたら終わり」の仕様として UI 上で説明する
- **MCPeerID の一意性**: 同じ `displayName` でも `MCPeerID` のインスタンスが異なれば別ピア扱いになる。アプリ起動ごとに新しい `MCPeerID` が生成されるため、過去のセッションとの紐付けは不要（＝一期一会の設計と一致）
- **招待の自動承認**: Phase 1 では招待を自動承認する。ブロック機能等は将来フェーズで検討
- **スレッド安全性**: `MCSessionDelegate` のコールバックはメインスレッドで呼ばれない場合がある。`@MainActor` または `DispatchQueue.main.async` で UI 更新を保護すること

---

## 9. アプリアイコン

リポジトリルートの `icon.png` を使用する。`Assets.xcassets` の `AppIcon` に設定すること。
