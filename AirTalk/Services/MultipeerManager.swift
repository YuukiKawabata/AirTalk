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
    private(set) var isRunning = false

    private var myPeerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var myProfile: UserProfile?
    private var pendingInvitationHandler: ((Bool, MCSession?) -> Void)?

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

    func send(text: String, to peerID: MCPeerID) {
        guard let myProfile = myProfile else { return }
        let message = AirMessage(
            id: UUID(),
            sender: myProfile.name,
            text: text,
            timestamp: Date(),
            isMe: true
        )
        if messages[peerID] == nil {
            messages[peerID] = []
        }
        messages[peerID]?.append(message)

        guard let data = try? JSONEncoder().encode(message) else { return }
        try? session?.send(data, toPeers: [peerID], with: .reliable)
    }

    func disconnect(from peerID: MCPeerID) {
        messages[peerID] = []
        connectedPeers.removeAll { $0 == peerID }
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

    func clearAll() {
        stop()
        messages.removeAll()
        connectedPeers.removeAll()
        discoveredPeers.removeAll()
        activeChatPeerID = nil
        invitingPeerID = nil
        pendingInvitation = nil
        pendingInvitationHandler = nil
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
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.messages[peerID] = self.messages[peerID] ?? []
                self.invitingPeerID = nil
                self.activeChatPeerID = peerID
                // チャット中は他のユーザーから見えないようにする
                self.advertiser?.stopAdvertisingPeer()
            case .notConnected:
                let wasInChat = self.activeChatPeerID == peerID
                self.messages[peerID] = []
                self.connectedPeers.removeAll { $0 == peerID }
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
        guard let message = try? JSONDecoder().decode(AirMessage.self, from: data) else { return }
        let receivedMessage = AirMessage(
            id: message.id,
            sender: message.sender,
            text: message.text,
            timestamp: message.timestamp,
            isMe: false
        )
        DispatchQueue.main.async {
            if self.messages[peerID] == nil {
                self.messages[peerID] = []
            }
            self.messages[peerID]?.append(receivedMessage)
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
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            self.pendingInvitationHandler = invitationHandler
            self.pendingInvitation = (peerID: peerID, name: peerID.displayName)
        }
    }
}
