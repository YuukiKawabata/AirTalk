import Foundation
import MultipeerConnectivity

struct DiscoveredPeer {
    let peerID: MCPeerID
    let profile: UserProfile
}

class MultipeerManager: NSObject, ObservableObject {
    private static let serviceType = "airtalk"

    @Published var discoveredPeers: [DiscoveredPeer] = []
    @Published var connectedPeers: [MCPeerID] = []
    @Published var messages: [MCPeerID: [AirMessage]] = [:]
    @Published var activeChatPeerID: MCPeerID?
    @Published var pendingInvitation: (peerID: MCPeerID, name: String)?
    @Published var invitingPeerID: MCPeerID?
    @Published var declinedByPeerName: String?
    /// 接続確立後に相手から受信したフルプロフィール（画像含む）。発見時の軽量プロフィールを上書きする。
    @Published var connectedPeerProfiles: [MCPeerID: UserProfile] = [:]
    /// ローカルネットワーク／Bluetooth 権限が拒否され、広告・探索を開始できなかった状態。
    @Published var permissionDenied = false
    @Published private(set) var blockedPeerNames: Set<String> = MultipeerManager.loadBlockedPeerNames()
    private(set) var isRunning = false

    private var myPeerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var myProfile: UserProfile?
    private var pendingInvitationHandler: ((Bool, MCSession?) -> Void)?
    private static let blockedPeerNamesKey = "blockedPeerNames"

    override init() {
        super.init()
    }

    func configure(with profile: UserProfile) {
        guard !profile.name.isEmpty else { return }

        self.myProfile = profile
        self.myPeerID = MCPeerID(displayName: profile.name)

        let session = MCSession(peer: myPeerID!, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID!,
            discoveryInfo: profile.asDiscoveryInfo,
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: myPeerID!, serviceType: Self.serviceType)
        browser.delegate = self
        self.browser = browser
    }

    func start() {
        guard myPeerID != nil else { return }
        permissionDenied = false
        advertiser?.startAdvertisingPeer()
        browser?.startBrowsingForPeers()
        isRunning = true
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        isRunning = false
    }

    /// 探索／広告を再起動する。ピアが見つからないときに UI から手動で叩く。
    /// 探索中であることをユーザーが能動的に確認できるようにし、「固まっている」印象を避ける。
    func restartDiscovery() {
        guard isRunning else { return }
        permissionDenied = false
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        discoveredPeers.removeAll()
        browser?.startBrowsingForPeers()
        advertiser?.startAdvertisingPeer()
    }

    func invitePeer(_ peerID: MCPeerID) {
        guard let session = session else { return }
        invitingPeerID = peerID
        browser?.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    func acceptInvitation() {
        pendingInvitationHandler?(true, session)
        pendingInvitationHandler = nil
        pendingInvitation = nil
    }

    func declineInvitation() {
        pendingInvitationHandler?(false, nil)
        pendingInvitationHandler = nil
        pendingInvitation = nil
    }

    func isBlocked(_ peerID: MCPeerID) -> Bool {
        blockedPeerNames.contains(peerID.displayName)
    }

    func send(text: String, to peerID: MCPeerID) {
        guard let myProfile = myProfile else { return }
        let trimmed = String(text.prefix(AirMessage.maxTextLength))
        let message = AirMessage(
            id: UUID(),
            sender: myProfile.name,
            text: trimmed,
            timestamp: Date(),
            isMe: true
        )
        if messages[peerID] == nil {
            messages[peerID] = []
        }
        messages[peerID]?.append(message)

        sendPacket(.message(message), to: peerID)
    }

    func sendReaction(_ reaction: String, for messageID: UUID, to peerID: MCPeerID) {
        let event = ReactionEvent(messageID: messageID, reaction: reaction)

        // ローカル側のメッセージも更新する
        if let index = messages[peerID]?.firstIndex(where: { $0.id == messageID }) {
            messages[peerID]?[index].reaction = reaction
        }

        sendPacket(.reaction(event), to: peerID)
    }

    /// 接続確立後、自分のフルプロフィール（画像含む）を相手に送る。
    private func sendProfile(to peerID: MCPeerID) {
        guard let myProfile = myProfile else { return }
        sendPacket(.profile(myProfile), to: peerID)
    }

    private func sendPacket(_ packet: NetworkPacket, to peerID: MCPeerID) {
        guard let session = session, session.connectedPeers.contains(peerID) else { return }
        guard let data = try? JSONEncoder().encode(packet) else { return }
        try? session.send(data, toPeers: [peerID], with: .reliable)
    }

    func disconnect(from peerID: MCPeerID) {
        messages[peerID] = []
        connectedPeers.removeAll { $0 == peerID }
        connectedPeerProfiles[peerID] = nil
        if activeChatPeerID == peerID {
            activeChatPeerID = nil
        }
    }

    func openChat(with peerID: MCPeerID) {
        activeChatPeerID = peerID
    }

    func closeChat() {
        if let peer = activeChatPeerID {
            messages[peer] = []
            connectedPeers.removeAll { $0 == peer }
            connectedPeerProfiles[peer] = nil
        }
        activeChatPeerID = nil
        // セッション切断 → 相手にも .notConnected が通知される
        session?.disconnect()
        // セッション再生成
        if let myPeerID = myPeerID {
            let newSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
            newSession.delegate = self
            self.session = newSession
        }
        // 再アドバタイズ開始（他のユーザーから見えるようにする）
        advertiser?.startAdvertisingPeer()
    }

    func block(_ peerID: MCPeerID) {
        blockedPeerNames.insert(peerID.displayName)
        Self.saveBlockedPeerNames(blockedPeerNames)
        removePeerState(peerID)
        session?.disconnect()
        if let myPeerID = myPeerID {
            let newSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
            newSession.delegate = self
            self.session = newSession
        }
        advertiser?.startAdvertisingPeer()
    }

    func clearAll() {
        stop()
        messages.removeAll()
        connectedPeers.removeAll()
        connectedPeerProfiles.removeAll()
        discoveredPeers.removeAll()
        activeChatPeerID = nil
        invitingPeerID = nil
        declinedByPeerName = nil
        pendingInvitation = nil
        pendingInvitationHandler = nil
    }

    func deleteLocalAccountData() {
        clearAll()
        UserProfile.delete()
        ProfilePresetStore.deleteAll()
        blockedPeerNames.removeAll()
        Self.saveBlockedPeerNames(blockedPeerNames)
        myProfile = nil
        myPeerID = nil
        session = nil
        advertiser = nil
        browser = nil
        permissionDenied = false
    }

    private func removePeerState(_ peerID: MCPeerID) {
        discoveredPeers.removeAll { $0.peerID == peerID || $0.profile.name == peerID.displayName }
        messages[peerID] = []
        connectedPeers.removeAll { $0 == peerID }
        connectedPeerProfiles[peerID] = nil
        if activeChatPeerID == peerID {
            activeChatPeerID = nil
        }
        if invitingPeerID == peerID {
            invitingPeerID = nil
        }
        if pendingInvitation?.peerID == peerID {
            pendingInvitationHandler?(false, nil)
            pendingInvitationHandler = nil
            pendingInvitation = nil
        }
    }

    private static func loadBlockedPeerNames() -> Set<String> {
        let names = UserDefaults.standard.stringArray(forKey: blockedPeerNamesKey) ?? []
        return Set(names)
    }

    private static func saveBlockedPeerNames(_ names: Set<String>) {
        UserDefaults.standard.set(Array(names).sorted(), forKey: blockedPeerNamesKey)
    }

    // MARK: - Demo Mode

    /// スクショ撮影用にデモデータを注入する。実ネットワークは起動せず、架空のピア・会話を表示する。
    /// 本番ビルドでは `DemoMode.isEnabled` が false のため呼ばれない。
    func loadDemoData(scene: DemoMode.Scene) {
        // 実ネットワークが動いていれば止めて、状態をクリーンにする
        stop()
        myProfile = DemoData.myProfile
        myPeerID = MCPeerID(displayName: DemoData.myProfile.name)

        // レーダーに並べる架空のピア
        let peers = DemoData.discoveredPeers()
        discoveredPeers = peers

        switch scene {
        case .chat:
            // チャット相手を「接続済み」状態にして、会話とプロフィールを注入する
            guard let partner = peers.first else { return }
            let partnerID = partner.peerID
            connectedPeers = [partnerID]
            connectedPeerProfiles[partnerID] = partner.profile
            messages[partnerID] = DemoData.chatMessages(partnerName: partner.profile.name)
            activeChatPeerID = partnerID

        case .invite:
            // 誰かからチャットリクエストが届いた瞬間を再現する
            let inviter = peers.first(where: { $0.profile.name == DemoData.inviterName }) ?? peers.first
            if let inviter = inviter {
                pendingInvitation = (peerID: inviter.peerID, name: inviter.profile.name)
            }

        case .discovery, .onboarding:
            break
        }
    }

    func updateProfile(_ profile: UserProfile) {
        stop()
        discoveredPeers.removeAll()
        connectedPeers.removeAll()
        messages.removeAll()
        activeChatPeerID = nil
        invitingPeerID = nil
        pendingInvitation = nil
        pendingInvitationHandler = nil
        configure(with: profile)
        start()
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if self.isBlocked(peerID) {
                    session.disconnect()
                    self.removePeerState(peerID)
                    return
                }
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.messages[peerID] = self.messages[peerID] ?? []
                self.invitingPeerID = nil
                self.activeChatPeerID = peerID
                // チャット中は他のユーザーから見えないようにする
                self.advertiser?.stopAdvertisingPeer()
                // 自分のフルプロフィール（画像含む）を相手に送る
                self.sendProfile(to: peerID)
            case .notConnected:
                let wasInChat = self.activeChatPeerID == peerID
                self.messages[peerID] = []
                self.connectedPeers.removeAll { $0 == peerID }
                self.connectedPeerProfiles[peerID] = nil
                if self.invitingPeerID == peerID {
                    self.declinedByPeerName = peerID.displayName
                    self.invitingPeerID = nil
                }
                if wasInChat {
                    self.activeChatPeerID = nil
                    // セッション再生成（再接続可能にする）
                    if let myPeerID = self.myPeerID {
                        let newSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
                        newSession.delegate = self
                        self.session = newSession
                    }
                    // 再アドバタイズ開始
                    self.advertiser?.startAdvertisingPeer()
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard !Self.loadBlockedPeerNames().contains(peerID.displayName) else { return }
        guard let packet = try? JSONDecoder().decode(NetworkPacket.self, from: data) else { return }

        DispatchQueue.main.async {
            switch packet {
            case .reaction(let event):
                if let index = self.messages[peerID]?.firstIndex(where: { $0.id == event.messageID }) {
                    self.messages[peerID]?[index].reaction = event.reaction
                }

            case .message(let message):
                let receivedMessage = AirMessage(
                    id: message.id,
                    sender: message.sender,
                    text: message.text,
                    timestamp: message.timestamp,
                    isMe: false,
                    reaction: message.reaction
                )
                if self.messages[peerID] == nil {
                    self.messages[peerID] = []
                }
                self.messages[peerID]?.append(receivedMessage)

            case .profile(let profile):
                // 相手のフルプロフィール（画像含む）を保存し、発見時の軽量情報を上書き
                self.connectedPeerProfiles[peerID] = profile
                if let index = self.discoveredPeers.firstIndex(where: { $0.peerID == peerID }) {
                    self.discoveredPeers[index] = DiscoveredPeer(peerID: peerID, profile: profile)
                }
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let info = info, let profile = UserProfile.from(discoveryInfo: info) else { return }
        DispatchQueue.main.async {
            guard !self.isBlocked(peerID) && !self.blockedPeerNames.contains(profile.name) else {
                self.discoveredPeers.removeAll { $0.peerID == peerID || $0.profile.name == profile.name }
                return
            }
            if let index = self.discoveredPeers.firstIndex(where: { $0.peerID == peerID }) {
                self.discoveredPeers[index] = DiscoveredPeer(peerID: peerID, profile: profile)
            } else {
                self.discoveredPeers.append(DiscoveredPeer(peerID: peerID, profile: profile))
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0.peerID == peerID }
        }
    }

    // 探索を開始できなかった（多くはローカルネットワーク権限拒否）
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.permissionDenied = true
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard !Self.loadBlockedPeerNames().contains(peerID.displayName) else {
            invitationHandler(false, nil)
            return
        }
        DispatchQueue.main.async {
            self.pendingInvitationHandler = invitationHandler
            self.pendingInvitation = (peerID: peerID, name: peerID.displayName)
        }
    }

    // 広告を開始できなかった（多くはローカルネットワーク権限拒否）
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.permissionDenied = true
        }
    }
}
