import Foundation
import MultipeerConnectivity

// MARK: - Role

enum MCRole { case host, guest }

// MARK: - Multipeer Session

/// Wraps MCSession + advertiser/browser for host-authoritative multiplayer.
/// Host advertises; guests browse and invite the host.
@Observable
@MainActor
final class MultipeerSession: NSObject {

    // MARK: - Public state (read by views)

    let role: MCRole
    let myPeerID: MCPeerID
    /// Peers currently connected in the session (both host & guest update this).
    var connectedPeers: [MCPeerID] = []
    /// Nearby hosts visible to a guest browser.
    var nearbyHosts: [MCPeerID] = []
    /// Called on main actor whenever a decoded message arrives.
    var onReceive: ((NetworkMessage, MCPeerID) -> Void)?

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

    // MARK: - Send

    /// Encode and send a message. `peers` defaults to all connected peers.
    func send(_ message: NetworkMessage, to peers: [MCPeerID]? = nil) {
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
                self.onReceive?(message, peerID)
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

    /// Host auto-accepts all invitations.
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            invitationHandler(true, self.session)
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
