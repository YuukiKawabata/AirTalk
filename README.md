# AirTalk

半径50mの「一期一会」ローカルチャットアプリ。
インターネット不要、履歴も残さない。すれ違った人と、その場限りの会話を。

## 技術スタック

- **言語:** Swift
- **UI:** SwiftUI
- **通信:** MultipeerConnectivity Framework（Wi-Fi / Bluetooth）
- **最低対応:** iOS 17+
- **永続化:** なし（メモリオンリー設計）

## ディレクトリ構成

```
AirTalk/
├── AirTalk.xcodeproj
├── AirTalk/
│   ├── AirTalkApp.swift
│   ├── Models/
│   │   ├── AirMessage.swift
│   │   └── UserProfile.swift
│   ├── Services/
│   │   └── MultipeerManager.swift
│   ├── Views/
│   │   ├── OnboardingView.swift
│   │   ├── DiscoveryView.swift
│   │   ├── ChatView.swift
│   │   └── Components/
│   │       ├── ProfileCard.swift
│   │       └── MessageBubble.swift
│   ├── Assets.xcassets
│   └── Info.plist
├── docs/
│   └── SPEC.md
├── icon.png
└── README.md
```

## セットアップ

1. Xcode 16+ で `AirTalk.xcodeproj` を開く
2. Deployment Target が **iOS 17.0** 以上であることを確認
3. `Info.plist` に以下のキーを設定（詳細は [SPEC.md](docs/SPEC.md#infoplist-設定) を参照）:
   - `NSLocalNetworkUsageDescription`
   - `NSBluetoothAlwaysUsageDescription`
   - `NSBonjourServices`
4. 実機でビルド＆ラン（MultipeerConnectivity はシミュレータでは制限あり）

## ロードマップ

| Phase | 内容 | 状態 |
|-------|------|------|
| **1** | コア通信基盤 — MultipeerManager、データモデル、基本的な接続・切断フロー | 未着手 |
| **2** | UI実装 — OnboardingView、DiscoveryView、ChatView、モノクロデザイン適用 | 未着手 |
| **3** | 体験の磨き込み — アニメーション（フェードアウト等）、接続状態表示、エラーハンドリング | 未着手 |
| **4** | 仕上げ — アプリアイコン（`icon.png`）適用、パフォーマンス最適化、テスト | 未着手 |

## 仕様書

詳細な技術仕様・デザインガイドライン・実装指針は **[docs/SPEC.md](docs/SPEC.md)** を参照。
