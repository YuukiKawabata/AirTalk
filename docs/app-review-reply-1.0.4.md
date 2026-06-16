# App Review 返信メモ（1.0 ビルド4）

- 対象提出ID: d4194d2e-a1a2-4651-bdc3-b2c5ab54eedd
- 指摘: Guideline 2.1(a) — 「アプリ起動後も他のユーザーを検索し続ける」
- 原因: P2P アプリのため、審査端末が1台だと周囲にピアが現れず、探索中スピナーが永続表示され「ハング」に見えていた。
- 対応: ビルド4で、ピアが約12秒見つからない場合に「近くにユーザーがいません」案内＋手動再検索ボタンへ自動遷移するよう改善。

## App Store Connect「審査に関する情報 > メモ」へ記載する英文

```
AirTalk is a peer-to-peer chat app built on MultipeerConnectivity (Wi-Fi + Bluetooth).
By design it requires TWO nearby devices to discover each other and start a chat.
With a single device, no peers appear — this is expected behavior, not a hang.

What changed in build 1.0 (4):
On the discovery screen, if no peers are found within ~12 seconds, the app now shows
a clear empty state ("No AirTalk users nearby") with guidance and a manual "Search
again" button, instead of an indefinite loading spinner. Background scanning continues,
so the app is functioning correctly while waiting for nearby devices.

How to fully verify functionality:
Please run the app on TWO devices placed close to each other (within ~50 m).
Each device will appear on the other's radar; tapping a peer starts a 1:1 chat.
Messages are never persisted and are deleted on disconnect (core privacy concept).

If using a single device is required for review, the empty state described above is the
intended, correct behavior. We are also happy to provide a short demo video showing two
devices connecting on request.

Thank you for your time reviewing AirTalk.
```

## 日本語訳（社内確認用 / 必要なら日本語でも返信可）

```
AirTalk は MultipeerConnectivity（Wi-Fi + Bluetooth）を用いた P2P チャットアプリです。
仕様上、相手を発見しチャットを開始するには「近くにある2台の端末」が必要です。
1台のみの場合はピアが表示されませんが、これはハングではなく正常な挙動です。

ビルド 1.0 (4) での変更点:
発見画面で約12秒以内にピアが見つからない場合、無限ローディングではなく
「近くにAirTalkユーザーがいません」という明確な空状態（案内文＋手動「もう一度さがす」
ボタン）を表示するよう改善しました。バックグラウンドでの探索は継続しています。

機能の確認方法:
近接した（半径約50m以内の）2台の端末でアプリを起動してください。
互いのレーダーに相手が表示され、タップすると1対1チャットが始まります。
メッセージは一切永続化されず、切断時に削除されます（本アプリの中核となるプライバシー設計）。
```
