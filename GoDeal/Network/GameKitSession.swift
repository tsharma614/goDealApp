import Foundation
import GameKit

// MARK: - GameKit Session

/// NetworkSession implementation backed by a GKMatch for internet multiplayer.
/// Host determination is done externally (lowest gamePlayerID = host).
@Observable
@MainActor
final class GameKitSession: NSObject, NetworkSession {

    // MARK: - NetworkSession conformance

    let role: MCRole
    /// Stored + observable so lobby views can react when new players join mid-wait.
    var connectedPeerIDs: [String] = []
    var connectedPeerNames: [String] = []
    var assignedPlayerIndex: Int = 0
    var gameStartReceived: Bool = false
    var onReceive: ((NetworkMessage, String) -> Void)?
    var onDisconnect: (() -> Void)?

    /// Peer IDs currently in reconnecting state (disconnected but waiting)
    var reconnectingPeerIDs: Set<String> = []
    /// Display names of peers currently reconnecting
    var reconnectingPeerNames: Set<String> = []

    // MARK: - Private

    private var reconnectTimers: [String: Task<Void, Never>] = [:]

    private let match: GKMatch
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let log = GameLogger.shared

    // MARK: - Init

    init(match: GKMatch, role: MCRole) {
        self.match = match
        self.role = role
        self.connectedPeerIDs = match.players.map { $0.gamePlayerID }
        self.connectedPeerNames = match.players.map { $0.displayName }
        super.init()
        match.delegate = self
        log.event("[GKSession] session created — role=\(role == .host ? "host" : "guest") peers=\(match.players.map { $0.displayName })")
    }

    // MARK: - Send

    func send(_ message: NetworkMessage) {
        guard !match.players.isEmpty else { return }
        do {
            let data = try encoder.encode(message)
            try match.sendData(toAllPlayers: data, with: .reliable)
            log.event("[GKSession] send \(typeName(message)) \(data.count)B to all")
        } catch {
            log.error("[GKSession] send error: \(error.localizedDescription)")
        }
    }

    func send(_ message: NetworkMessage, toPeerIDs: [String]) {
        let targets = match.players.filter { toPeerIDs.contains($0.gamePlayerID) }
        guard !targets.isEmpty else { return }
        do {
            let data = try encoder.encode(message)
            try match.send(data, to: targets, dataMode: .reliable)
            log.event("[GKSession] send \(typeName(message)) \(data.count)B to \(targets.map { $0.displayName })")
        } catch {
            log.error("[GKSession] send(toPeerIDs:) error: \(error.localizedDescription)")
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        match.disconnect()
    }

    // MARK: - Helpers

    private func typeName(_ msg: NetworkMessage) -> String {
        switch msg {
        case .playerAssignment:  return "playerAssignment"
        case .gameState:         return "gameState"
        case .playerAction:      return "playerAction"
        case .gameStart:         return "gameStart"
        case .playAgainRequest:  return "playAgainRequest"
        case .playAgainConfirm:  return "playAgainConfirm"
        case .emojiReaction:     return "emojiReaction"
        }
    }
}

// MARK: - GKMatchDelegate

extension GameKitSession: GKMatchDelegate {

    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        Task { @MainActor in
            do {
                let message = try self.decoder.decode(NetworkMessage.self, from: data)
                self.log.event("[GKSession] received \(self.typeName(message)) from \(player.displayName)")
                self.onReceive?(message, player.gamePlayerID)
            } catch {
                self.log.error("[GKSession] decode error: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor in
            let peerID = player.gamePlayerID
            if state == .connected {
                // Cancel any pending reconnect timeout
                self.reconnectTimers[peerID]?.cancel()
                self.reconnectTimers.removeValue(forKey: peerID)
                let wasReconnecting = self.reconnectingPeerIDs.remove(peerID) != nil
                self.reconnectingPeerNames.remove(player.displayName)

                if !self.connectedPeerIDs.contains(peerID) {
                    self.connectedPeerIDs.append(peerID)
                    self.connectedPeerNames.append(player.displayName)
                }
                if wasReconnecting {
                    self.log.event("[GKSession] player \(player.displayName) reconnected")
                } else {
                    self.log.event("[GKSession] player \(player.displayName) connected (total peers: \(self.connectedPeerIDs.count))")
                }
            } else if state == .disconnected {
                // Enter reconnecting state — wait 30s before treating as permanent
                self.reconnectingPeerIDs.insert(peerID)
                self.reconnectingPeerNames.insert(player.displayName)
                self.log.warn("[GKSession] player \(player.displayName) disconnected — waiting 30s for reconnect")

                self.reconnectTimers[peerID] = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled else { return }
                    // Timeout — permanent disconnect
                    self.reconnectingPeerIDs.remove(peerID)
                    self.reconnectingPeerNames.remove(player.displayName)
                    self.connectedPeerIDs.removeAll { $0 == peerID }
                    self.connectedPeerNames.removeAll { $0 == player.displayName }
                    self.reconnectTimers.removeValue(forKey: peerID)
                    self.log.warn("[GKSession] player \(player.displayName) reconnect timed out")
                    self.onDisconnect?()
                }
            }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor in
            self.log.error("[GKSession] match failed: \(error?.localizedDescription ?? "unknown")")
            self.onDisconnect?()
        }
    }
}
