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
    case playerNotFound

    var errorDescription: String? {
        switch self {
        case .timeout:          return "Room not found. Make sure both players enter the same code and try again."
        case .notAuthenticated: return "Sign in to Game Center in Settings to play online."
        case .playerNotFound:   return "Could not reach this player. They may be offline or unavailable."
        }
    }
}

// MARK: - Peer Connection Watcher

/// Temporary GKMatchDelegate that waits for the first remote player to actually connect.
/// GKMatchmaker's findMatch callback fires before peer-to-peer connections are established,
/// so this watcher bridges the gap. Replaced by GameKitSession's delegate after connection.
private final class PeerConnectionWatcher: NSObject, GKMatchDelegate {

    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    init(match: GKMatch, continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
        super.init()
        match.delegate = self
    }

    private func resume(_ result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard let c = continuation else { return }
        continuation = nil
        c.resume(with: result)
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        if state == .connected { resume(.success(())) }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        resume(.failure(error ?? MatchmakerError.timeout))
    }

    // Data arriving during the brief handoff window is dropped (game hasn't started yet).
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {}
}

// MARK: - GameKit Matchmaker

/// Creates or joins a GKMatch using a deterministic room-code → playerGroup mapping.
/// No server needed: all players enter the same code, GameKit routes them into a shared match.
@Observable
@MainActor
final class GameKitMatchmaker {

    var isSearching: Bool = false

    private let log = GameLogger.shared
    /// Held strongly so the delegate object lives until the first peer connects.
    private var peerWatcher: PeerConnectionWatcher?

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
        request.maxPlayers = max(2, min(5, maxPlayers))
        request.playerGroup = group

        // 60-second timeout: cancel GK matchmaker, which triggers the completion handler with an error.
        let timeoutTask = Task { [log] in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            GKMatchmaker.shared().cancel()
            log.warn("[GKMatchmaker] 60s timeout for roomCode=\(roomCode)")
        }
        defer { timeoutTask.cancel() }

        // Step 1: Get the GKMatch object from GKMatchmaker.
        // NOTE: findMatch fires its callback as soon as GameKit finds a match slot, but
        // match.players may be empty at that point — remote peers connect asynchronously.
        let match: GKMatch = try await withCheckedThrowingContinuation { continuation in
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
                continuation.resume(returning: match)
            }
        }

        // Step 2: If remote peers aren't connected yet, wait for the first connection event.
        // This is the common case — the match object arrives before the P2P link is up.
        if match.players.isEmpty {
            log.event("[GKMatchmaker] match slot found — waiting for remote player to connect...")
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                // Store the watcher on self so it lives until the continuation fires.
                peerWatcher = PeerConnectionWatcher(match: match, continuation: cont)
            }
            peerWatcher = nil
        }

        // Step 3: Deterministic host election — sort all gamePlayerIDs; lowest = host.
        let allIDs = ([GKLocalPlayer.local.gamePlayerID]
            + match.players.map { $0.gamePlayerID }).sorted()
        let role: MCRole = allIDs.first == GKLocalPlayer.local.gamePlayerID ? .host : .guest
        log.event("[GKMatchmaker] match ready — players: \(match.players.map { $0.displayName }) role=\(role == .host ? "host" : "guest")")

        return (match, role)
    }

    /// Invite specific players by their gamePlayerIDs.
    /// GameKit sends them a push notification; they accept → match is created.
    func invitePlayers(gamePlayerIDs: [String], maxPlayers: Int = 5) async throws -> (GKMatch, MCRole) {
        guard GKLocalPlayer.local.isAuthenticated else {
            throw MatchmakerError.notAuthenticated
        }

        // Cancel any in-flight matchmaking before starting a new invite
        GKMatchmaker.shared().cancel()

        isSearching = true
        log.event("[GKMatchmaker] inviting \(gamePlayerIDs.count) player(s)")

        // Load GKPlayer objects from stored IDs
        let players: [GKPlayer] = try await withCheckedThrowingContinuation { continuation in
            GKLocalPlayer.loadPlayers(forIdentifiers: gamePlayerIDs) { players, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: players ?? [])
                }
            }
        }
        guard !players.isEmpty else {
            isSearching = false
            throw MatchmakerError.playerNotFound
        }

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = max(2, min(5, maxPlayers))
        request.recipients = players
        request.inviteMessage = "Let's play Go! Deal!"

        // 90-second timeout for invites (longer than room code since we wait for human response)
        let timeoutTask = Task { [log] in
            try await Task.sleep(nanoseconds: 90_000_000_000)
            GKMatchmaker.shared().cancel()
            log.warn("[GKMatchmaker] 90s invite timeout")
        }
        defer { timeoutTask.cancel() }

        let match: GKMatch = try await withCheckedThrowingContinuation { continuation in
            GKMatchmaker.shared().findMatch(for: request) { [log] match, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == GKErrorDomain,
                       nsError.code == GKError.Code.cancelled.rawValue {
                        continuation.resume(throwing: MatchmakerError.timeout)
                    } else {
                        log.error("[GKMatchmaker] invite error \(nsError.code): \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let match else {
                    continuation.resume(throwing: MatchmakerError.timeout)
                    return
                }
                continuation.resume(returning: match)
            }
        }

        // Wait for peers to actually connect
        if match.players.isEmpty {
            log.event("[GKMatchmaker] invite accepted — waiting for peer connection...")
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                peerWatcher = PeerConnectionWatcher(match: match, continuation: cont)
            }
            peerWatcher = nil
        }

        // Deterministic host election
        let allIDs = ([GKLocalPlayer.local.gamePlayerID]
            + match.players.map { $0.gamePlayerID }).sorted()
        let role: MCRole = allIDs.first == GKLocalPlayer.local.gamePlayerID ? .host : .guest
        log.event("[GKMatchmaker] invite match ready — players: \(match.players.map { $0.displayName }) role=\(role == .host ? "host" : "guest")")

        return (match, role)
    }

    func cancel() {
        GKMatchmaker.shared().cancel()
        isSearching = false
    }
}
