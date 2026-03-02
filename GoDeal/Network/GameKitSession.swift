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
    var connectedPeerIDs: [String] { match.players.map { $0.gamePlayerID } }
    var connectedPeerNames: [String] { match.players.map { $0.displayName } }
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
            if state == .disconnected {
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
