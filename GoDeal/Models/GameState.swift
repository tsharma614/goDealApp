import Foundation

// MARK: - Game Phase

enum GamePhase: Equatable, Codable {
    case drawing
    case playing
    case awaitingResponse(targetPlayerIndex: Int, actionCard: Card, attackerIndex: Int)
    case awaitingPayment(debtorIndex: Int, creditorIndex: Int, amount: Int, reason: PaymentReason)
    case awaitingPropertyChoice(chooserIndex: Int, purpose: PropertyChoicePurpose)
    case awaitingWildColorChoice(playerIndex: Int, cardId: UUID)
    case discarding(playerIndex: Int)
    case gameOver(winnerIndex: Int)

    static func == (lhs: GamePhase, rhs: GamePhase) -> Bool {
        switch (lhs, rhs) {
        case (.drawing, .drawing): return true
        case (.playing, .playing): return true
        case (.awaitingResponse(let li, let lc, let la), .awaitingResponse(let ri, let rc, let ra)):
            return li == ri && lc == rc && la == ra
        case (.awaitingPayment(let ld, let lc, let la, let lr), .awaitingPayment(let rd, let rc, let ra, let rr)):
            return ld == rd && lc == rc && la == ra && lr == rr
        case (.awaitingPropertyChoice(let li, let lp), .awaitingPropertyChoice(let ri, let rp)):
            return li == ri && lp == rp
        case (.awaitingWildColorChoice(let li, let lc), .awaitingWildColorChoice(let ri, let rc)):
            return li == ri && lc == rc
        case (.discarding(let l), .discarding(let r)): return l == r
        case (.gameOver(let l), .gameOver(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - Supporting Enums

enum PaymentReason: Equatable, Codable {
    case rent(PropertyColor)
    case collectNow
    case bigSpender
    case dealSnatcher  // Target must pay back: property is taken instead
}

enum PropertyChoicePurpose: Equatable, Codable {
    case quickGrab(targetPlayerIndex: Int)                     // Attacker picks which property to steal
    case quickGrabVictim(attackerPlayerIndex: Int)             // Human victim picks which property to sacrifice
    case swapIt(targetPlayerIndex: Int)                        // Attacker picks their card + target card
    case swapItVictim(attackerPlayerIndex: Int)                // Human victim picks their card + attacker's card
    case dealSnatcher(targetPlayerIndex: Int)                  // Attacker picks which complete set to steal
    case dealSnatcherVictim(attackerPlayerIndex: Int)          // Human victim picks which complete set to give up
    case swapItTarget(initiatorIndex: Int, offeredCardId: UUID)
    case payWithProperty(creditorIndex: Int, amount: Int)
}

// MARK: - Pending Double Up

struct PendingDoubleUp: Codable {
    var isActive: Bool = false
    var rentCardPlayed: Bool = false
}

// MARK: - Pending Steal Pre-Selection
// When a human plays quickGrab/dealSnatcher/swapIt, they pick the target
// property BEFORE the card is played so they can cancel freely. These fields
// carry that choice through the awaitingResponse phase so executeQueuedAction
// can execute immediately after the target accepts (no second picker needed).
struct PendingStealPreSelection: Codable {
    var cardId: UUID? = nil          // quickGrab / swapIt attacker card
    var color: PropertyColor? = nil  // dealSnatcher
    var secondaryCardId: UUID? = nil // swapIt target card
}

// MARK: - Game State

struct GameState: Codable {
    var players: [Player]
    var deck: [Card]
    var discardPile: [Card]
    var currentPlayerIndex: Int
    var cardsPlayedThisTurn: Int   // max 3
    var phase: GamePhase
    var pendingDoubleUp: PendingDoubleUp
    var pendingSteal: PendingStealPreSelection
    var turnNumber: Int

    // Convenience
    var currentPlayer: Player {
        get { players[currentPlayerIndex] }
        set { players[currentPlayerIndex] = newValue }
    }

    var activePlayerCount: Int { players.count }

    init(players: [Player], deck: [Card]) {
        self.players = players
        self.deck = deck
        self.discardPile = []
        self.currentPlayerIndex = 0
        self.cardsPlayedThisTurn = 0
        self.phase = .drawing
        self.pendingDoubleUp = PendingDoubleUp()
        self.pendingSteal = PendingStealPreSelection()
        self.turnNumber = 1
    }

    // Next player index (wraps around)
    func nextPlayerIndex(after index: Int) -> Int {
        (index + 1) % players.count
    }

    // All other player indices relative to current
    func otherPlayerIndices() -> [Int] {
        players.indices.filter { $0 != currentPlayerIndex }
    }

    // Can the current player still play a card?
    var canPlayCard: Bool {
        guard case .playing = phase else { return false }
        return cardsPlayedThisTurn < 3
    }
}
