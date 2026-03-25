# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

AirTalk は「半径50mの一期一会」をコンセプトにした iOS P2P チャットアプリ。メッセージは一切永続化されず、切断時に自動削除される。インターネット不要・サーバーレス。

- **対象 iOS**: 17.0+
- **言語**: Swift / SwiftUI
- **通信**: MultipeerConnectivity（Wi-Fi + Bluetooth）
- **外部依存**: なし（純粋 Apple フレームワークのみ）

## ビルド・実行

```bash
# Xcodeでビルド
xcodebuild -project AirTalk.xcodeproj -scheme AirTalk -configuration Debug build

# デバイス一覧確認
xcodebuild -project AirTalk.xcodeproj -scheme AirTalk -showdestinations
```

**重要**: MultipeerConnectivity はシミュレータでは動作不安定。P2P 機能のテストには物理デバイス2台が必要。

現時点でユニットテストは存在しない。手動テストのみ。

## アーキテクチャ

### MVVM + EnvironmentObject パターン

```
AirTalkApp
├── MultipeerManager (@StateObject)  ← 全状態・P2Pロジック
└── Views (@EnvironmentObject で共有)
    ├── OnboardingView  (初回起動時のみ)
    ├── DiscoveryView   (メイン画面・ピア発見)
    ├── ChatView        (1対1チャット)
    └── Components/
        ├── ProfileCard
        └── MessageBubble
```

### MultipeerManager（`Services/MultipeerManager.swift`）

アプリの中核。全 P2P ライフサイクルを管理する ObservableObject。

- **サービスタイプ**: `airtalk`（Bonjour）
- **暗号化**: `.required`
- **Delegate が3つ**: `MCSessionDelegate`, `MCNearbyServiceBrowserDelegate`, `MCNearbyServiceAdvertiserDelegate`
- 全 delegate コールバックは `DispatchQueue.main.async` でラップ

主要な状態遷移:
1. `configure(with:)` → MCSession・Advertiser・Browser を初期化
2. `start()` → 広告・探索を開始
3. `invitePeer` / `acceptInvitation` / `declineInvitation` → 接続フロー
4. 切断検知 → 即座に `messages[peerID] = []`（自動シュレッダー）
5. アプリがバックグラウンドへ → `clearAll()`（全メッセージ・セッション破棄）

### データモデル

**AirMessage**（`Identifiable, Codable`）: `id`, `sender`, `text`, `timestamp`, `isMe`
→ JSON エンコードして MCSession でやり取り

**UserProfile**（UserDefaults に保存）: `name`, `status`, `iconID`（SF Symbols名）
→ `asDiscoveryInfo` プロパティで Bonjour discovery info として配信

### 画面遷移

```
起動
 └─ 初回: OnboardingView → DiscoveryView
 └─ 2回目以降: DiscoveryView → ChatView → DiscoveryView（切断で自動戻り）
```

### 設計原則

- **メッセージは永続化しない**: CoreData・SwiftData・FileManager 不使用。UserDefaults はプロフィールのみ
- **切断 = 即削除**: ディスコネクト・バックグラウンド移行のどちらもメッセージを消去
- **モノクロデザイン**: Black / White / Gray (#8E8E93) のみ。SF Symbols は `.monochrome`
- `closeChat()` はセッションを再生成し、再接続を可能にする

## Info.plist 必須設定

以下3つがないと MultipeerConnectivity が動作しない:

```xml
NSLocalNetworkUsageDescription
NSBluetoothAlwaysUsageDescription
NSBonjourServices: [_airtalk._tcp, _airtalk._udp]
```

## 仕様書

詳細な技術仕様は `docs/SPEC.md` に記載（UI レイアウト、自動シュレッダーの発火条件、スレッド安全性など）。
