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

    // MARK: - Private

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
            if state == .connected {
                if !self.connectedPeerIDs.contains(player.gamePlayerID) {
                    self.connectedPeerIDs.append(player.gamePlayerID)
                    self.connectedPeerNames.append(player.displayName)
                    self.log.event("[GKSession] player \(player.displayName) connected (total peers: \(self.connectedPeerIDs.count))")
                }
            } else if state == .disconnected {
                self.connectedPeerIDs.removeAll { $0 == player.gamePlayerID }
                self.connectedPeerNames.removeAll { $0 == player.displayName }
                self.log.warn("[GKSession] player \(player.displayName) disconnected")
                self.onDisconnect?()
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
