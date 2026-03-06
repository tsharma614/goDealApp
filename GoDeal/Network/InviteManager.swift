import Foundation
import GameKit

// MARK: - Invite Manager
// Singleton that registers as a GKLocalPlayerListener to handle incoming Game Center invites.
// When a remote player invites us, GameKit delivers the invite here. We store it and
// notify the UI so it can present the lobby automatically.

@Observable
@MainActor
final class InviteManager: NSObject {

    static let shared = InviteManager()

    /// Set when an invite arrives — the UI observes this to auto-open the lobby.
    var pendingInvite: GKInvite? = nil

    /// The match created from an accepted invite (set after accepting).
    var inviteMatch: GKMatch? = nil

    private let log = GameLogger.shared

    private override init() {
        super.init()
    }

    /// Call once after Game Center authentication succeeds.
    func register() {
        GKLocalPlayer.local.register(self)
        log.event("[InviteManager] registered for invite events")
    }

    /// Accept a pending invite — creates the match.
    func acceptInvite() async throws -> (GKMatch, MCRole) {
        guard let invite = pendingInvite else {
            throw MatchmakerError.timeout
        }

        let match: GKMatch = try await withCheckedThrowingContinuation { continuation in
            GKMatchmaker.shared().match(for: invite) { match, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let match else {
                    continuation.resume(throwing: MatchmakerError.timeout)
                    return
                }
                continuation.resume(returning: match)
            }
        }

        // Deterministic host election
        let allIDs = ([GKLocalPlayer.local.gamePlayerID]
            + match.players.map { $0.gamePlayerID }).sorted()
        let role: MCRole = allIDs.first == GKLocalPlayer.local.gamePlayerID ? .host : .guest

        pendingInvite = nil
        inviteMatch = match
        log.event("[InviteManager] invite accepted — role=\(role == .host ? "host" : "guest") players=\(match.players.map { $0.displayName })")

        return (match, role)
    }

    func clearInvite() {
        pendingInvite = nil
        inviteMatch = nil
    }
}

// MARK: - GKLocalPlayerListener

extension InviteManager: GKLocalPlayerListener {

    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        Task { @MainActor in
            self.log.event("[InviteManager] received invite from \(invite.sender.displayName)")
            self.pendingInvite = invite
        }
    }
}
