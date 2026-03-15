import Foundation

// MARK: - Network Message

/// Top-level envelope sent between host and guests over MultipeerConnectivity.
enum NetworkMessage: Codable {
    /// Host → guest: "you control player at index N"
    case playerAssignment(localPlayerIndex: Int)
    /// Host → all: full game state snapshot after every mutation
    case gameState(GameState)
    /// Guest → host: action request
    case playerAction(PlayerAction)
    /// Host → all: game is starting now
    case gameStart
    /// Host → guests: "want to play again with the same setup?"
    case playAgainRequest
    /// Guest → host: "yes, start the new game"
    case playAgainConfirm
    /// Any player → all: emoji reaction
    case emojiReaction(emoji: String, fromPlayerIndex: Int)
}

// MARK: - Player Action

/// All actions a guest can request the host to execute on their behalf.
enum PlayerAction: Codable {
    case playToBank(cardId: UUID)
    case playProperty(cardId: UUID, color: PropertyColor)
    case playWildProperty(cardId: UUID, color: PropertyColor)
    case playAction(cardId: UUID, targetPlayerIndex: Int?, targetPropertyColor: PropertyColor?)
    case playActionWithPreSelection(
        cardId: UUID,
        targetPlayerIndex: Int,
        stealCardId: UUID?,
        stealColor: PropertyColor?,
        stealSecondaryCardId: UUID?
    )
    case playRent(cardId: UUID, color: PropertyColor, targetPlayerIndex: Int?)
    case playNoDeal(cardId: UUID)
    case acceptAction
    case endTurn
    case submitPayment(bankCardIds: [UUID], propertyCardIds: [UUID])
    case cancelDiscard
    case discard(cardId: UUID)
    case reassignWild(cardId: UUID, toColor: PropertyColor)
    case resolvePropertyChoice(
        purpose: PropertyChoicePurpose,
        selectedCardId: UUID?,
        selectedColor: PropertyColor?,
        secondaryCardId: UUID?
    )
    /// Player requests to start drawing cards at the beginning of their turn
    case startTurn
}
