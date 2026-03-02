import Foundation
import MultipeerConnectivity

// MARK: - Multipeer Session

/// Wraps MCSession + advertiser/browser for host-authoritative local multiplayer.
/// Host advertises; guests browse and invite the host.
/// Conforms to NetworkSession so GameViewModel works with both local and internet sessions.
@Observable
@MainActor
final class MultipeerSession: NSObject, NetworkSession {

    // MARK: - NetworkSession conformance

    let role: MCRole
    var connectedPeerIDs: [String] { connectedPeers.map { $0.displayName } }
    var connectedPeerNames: [String] { connectedPeers.map { $0.displayName } }
    var assignedPlayerIndex: Int = 0
    var gameStartReceived: Bool = false
    var onReceive: ((NetworkMessage, String) -> Void)?
    var onDisconnect: (() -> Void)?

    // MARK: - Public state (read by views)

    let myPeerID: MCPeerID
    /// Peers currently connected in the session (both host & guest update this).
    var connectedPeers: [MCPeerID] = []
    /// Nearby hosts visible to a guest browser.
    var nearbyHosts: [MCPeerID] = []

    // MARK: - Private

    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private static let serviceType = "godeal-mp"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init

    init(role: MCRole, displayName: String) {
        self.role = role
        self.myPeerID = MCPeerID(displayName: displayName)
        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        super.init()
        session.delegate = self
    }

    // MARK: - Host: advertise

    func startAdvertising() {
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    // MARK: - Guest: browse

    func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    /// Guest invites a discovered host to join the session.
    func invite(_ peer: MCPeerID) {
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    // MARK: - Send (NetworkSession protocol)

    /// Send a message to all connected peers.
    func send(_ message: NetworkMessage) {
        send(message, to: nil)
    }

    /// Send a message to specific peers by their display-name IDs.
    func send(_ message: NetworkMessage, toPeerIDs: [String]) {
        let targets = session.connectedPeers.filter { toPeerIDs.contains($0.displayName) }
        send(message, to: targets)
    }

    // MARK: - Send (internal helper)

    /// Encode and send a message. `peers` defaults to all connected peers.
    private func send(_ message: NetworkMessage, to peers: [MCPeerID]? = nil) {
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty else { return }
        do {
            let data = try encoder.encode(message)
            try session.send(data, toPeers: targets, with: .reliable)
        } catch {
            print("[MultipeerSession] send error: \(error)")
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        stopAdvertising()
        stopBrowsing()
        session.disconnect()
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSession: MCSessionDelegate {

    nonisolated func session(_ session: MCSession,
                             peer peerID: MCPeerID,
                             didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.onDisconnect?()
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession,
                             didReceive data: Data,
                             fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let message = try self.decoder.decode(NetworkMessage.self, from: data)
                self.onReceive?(message, peerID.displayName)
            } catch {
                print("[MultipeerSession] decode error: \(error)")
            }
        }
    }

    nonisolated func session(_ session: MCSession,
                             didReceive stream: InputStream,
                             withName streamName: String,
                             fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession,
                             didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID,
                             with progress: Progress) {}

    nonisolated func session(_ session: MCSession,
                             didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID,
                             at localURL: URL?,
                             withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {

    /// Host auto-accepts invitations up to 3 guests (4 players total).
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            let accept = self.connectedPeers.count < 3
            invitationHandler(accept, accept ? self.session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didNotStartAdvertisingPeer error: Error) {
        print("[MultipeerSession] advertise error: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerSession: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !self.nearbyHosts.contains(peerID) {
                self.nearbyHosts.append(peerID)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.nearbyHosts.removeAll { $0 == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             didNotStartBrowsingForPeers error: Error) {
        print("[MultipeerSession] browse error: \(error)")
    }
}
