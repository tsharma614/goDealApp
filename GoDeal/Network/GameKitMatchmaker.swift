import Foundation
import GameKit

// MARK: - Room Code Helpers

extension String {
    /// Deterministic hash mapped to a non-negative integer for use as GKMatchRequest.playerGroup.
    /// Uses djb2 variant clamped to [0, 9_999_999].
    var playerGroupHash: Int {
        var hash: UInt = 5381
        for scalar in unicodeScalars {
            hash = 127 &* hash &+ UInt(scalar.value)
        }
        return Int(hash % 9_999_999)
    }

    /// Generate a random 6-character alphanumeric room code (no ambiguous chars: I, O, 0, 1).
    static func randomRoomCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

// MARK: - Matchmaker Error

enum MatchmakerError: LocalizedError {
    case timeout
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .timeout:          return "Room not found. Make sure both players enter the same code and try again."
        case .notAuthenticated: return "Sign in to Game Center in Settings to play online."
        }
    }
}

// MARK: - GameKit Matchmaker

/// Creates or joins a GKMatch using a deterministic room-code → playerGroup mapping.
/// No server needed: all players enter the same code, GameKit routes them into a shared match.
@Observable
@MainActor
final class GameKitMatchmaker {

    var isSearching: Bool = false

    private let log = GameLogger.shared

    /// Create or join a match for the given room code.
    /// Returns (match, role). Host = player with lowest gamePlayerID (deterministic, no race).
    func createOrJoinMatch(roomCode: String, maxPlayers: Int = 4) async throws -> (GKMatch, MCRole) {
        guard GKLocalPlayer.local.isAuthenticated else {
            throw MatchmakerError.notAuthenticated
        }

        isSearching = true

        let group = roomCode.uppercased().playerGroupHash
        log.event("[GKMatchmaker] creating roomCode=\(roomCode) group=\(group)")

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = max(2, min(4, maxPlayers))
        request.playerGroup = group

        // 60-second timeout: cancel GK matchmaker, which triggers the completion handler with an error.
        let timeoutTask = Task { [log] in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            GKMatchmaker.shared().cancel()
            log.warn("[GKMatchmaker] 60s timeout for roomCode=\(roomCode)")
        }
        defer { timeoutTask.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            GKMatchmaker.shared().findMatch(for: request) { [log] match, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == GKErrorDomain,
                       nsError.code == GKError.Code.cancelled.rawValue {
                        continuation.resume(throwing: MatchmakerError.timeout)
                    } else {
                        log.error("[GKMatchmaker] error \(nsError.code): \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let match else {
                    continuation.resume(throwing: MatchmakerError.timeout)
                    return
                }
                // Deterministic host election: sort all gamePlayerIDs; lowest = host
                let allIDs = ([GKLocalPlayer.local.gamePlayerID]
                    + match.players.map { $0.gamePlayerID }).sorted()
                let role: MCRole = allIDs.first == GKLocalPlayer.local.gamePlayerID ? .host : .guest
                log.event("[GKMatchmaker] match formed — players: \(match.players.map { $0.displayName }) role=\(role == .host ? "host" : "guest")")
                continuation.resume(returning: (match, role))
            }
        }
    }

    func cancel() {
        GKMatchmaker.shared().cancel()
        isSearching = false
    }
}
