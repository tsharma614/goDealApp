import Foundation

// MARK: - Role

/// Whether a player is authoritative (host) or remote (guest).
enum MCRole { case host, guest }

// MARK: - Network Session Protocol

/// Unified transport abstraction for local (MultipeerConnectivity) and internet (GameKit) play.
/// GameViewModel is session-agnostic through this protocol.
protocol NetworkSession: AnyObject {
    /// Whether this device is the game host or a guest.
    var role: MCRole { get }
    /// Stable unique IDs for all connected peers (not including self).
    /// MultipeerSession: MCPeerID.displayName. GameKitSession: GKPlayer.gamePlayerID.
    var connectedPeerIDs: [String] { get }
    /// Human-readable display names for connected peers (same order as connectedPeerIDs).
    var connectedPeerNames: [String] { get }
    /// Guest: player index assigned by the host.
    var assignedPlayerIndex: Int { get set }
    /// Guest: set to true when a .gameStart message is received from the host.
    var gameStartReceived: Bool { get set }
    /// Called on MainActor when any message arrives. Second arg is the sender's stable ID.
    var onReceive: ((NetworkMessage, String) -> Void)? { get set }
    /// Called on MainActor when a remote peer disconnects unexpectedly.
    var onDisconnect: (() -> Void)? { get set }
    /// Send a message to all connected peers.
    func send(_ message: NetworkMessage)
    /// Send a message to the subset of peers identified by their stable IDs.
    func send(_ message: NetworkMessage, toPeerIDs: [String])
    /// Terminate the session and release all resources.
    func disconnect()
}
