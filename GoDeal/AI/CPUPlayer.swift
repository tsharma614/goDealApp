import Foundation
import SwiftUI

// MARK: - CPU Player
// Drives the CPU's turn by making decisions via AIStrategy and calling GameEngine.

@Observable
final class CPUPlayer {

    let playerIndex: Int
    let difficulty: AIDifficulty
    private weak var engine: GameEngine?

    // Delay between CPU actions for visual feedback (seconds)
    var actionDelay: Double = 2.4

    // Guards against executeTurn + resumeTurn running concurrently.
    // SwiftUI's onChange(.playing) fires during executeTurn's sleep and schedules resumeTurn,
    // but executeTurn hasn't finished yet. The flag lets the second Task exit cleanly.
    private var isExecuting: Bool = false

    init(playerIndex: Int, difficulty: AIDifficulty, engine: GameEngine) {
        self.playerIndex = playerIndex
        self.difficulty = difficulty
        self.engine = engine
    }

    // MARK: - Execute Turn

    /// Runs the CPU's full turn asynchronously.
    @MainActor
    func executeTurn() async {
        guard !isExecuting else { return }
        isExecuting = true
        defer { isExecuting = false }

        guard let engine = engine else { return }

        // Draw phase
        guard case .drawing = engine.state.phase,
              engine.state.currentPlayerIndex == playerIndex else { return }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            engine.startTurn()
        }
        await sleep()

        // Play up to 3 cards
        for _ in 0..<3 {
            guard case .playing = engine.state.phase,
                  engine.state.currentPlayerIndex == playerIndex,
                  engine.state.canPlayCard else { break }

            guard let decision = AIStrategy.decideNextPlay(
                state: engine.state,
                playerIndex: playerIndex,
                difficulty: difficulty
            ) else { break }

            executeDecision(decision, in: engine)
            await sleep()

            // Check if game is over
            if case .gameOver = engine.state.phase { return }

            // Handle awaitingResponse phase (if CPU triggered an action requiring response)
            await handleAwaitingResponse(engine: engine)

            // Handle property choice (quickGrab/dealSnatcher/swapIt after accept)
            await resolvePropertyChoiceIfNeeded(engine: engine)
        }

        // End turn
        if case .playing = engine.state.phase,
           engine.state.currentPlayerIndex == playerIndex {
            engine.endTurn()
        }

        // Handle discard if needed
        await handleDiscardIfNeeded(engine: engine)
    }

    // MARK: - Resume Turn (from .playing phase)

    /// Continues the CPU's turn from the .playing phase.
    /// Called after a No Deal! response cancels an action mid-turn.
    @MainActor
    func resumeTurn() async {
        guard !isExecuting else { return }
        isExecuting = true
        defer { isExecuting = false }

        guard let engine = engine else { return }
        guard engine.state.currentPlayerIndex == playerIndex else { return }
        guard case .playing = engine.state.phase else { return }

        for _ in 0..<3 {
            guard case .playing = engine.state.phase,
                  engine.state.currentPlayerIndex == playerIndex,
                  engine.state.canPlayCard else { break }

            guard let decision = AIStrategy.decideNextPlay(
                state: engine.state,
                playerIndex: playerIndex,
                difficulty: difficulty
            ) else { break }

            executeDecision(decision, in: engine)
            await sleep()

            if case .gameOver = engine.state.phase { return }

            await handleAwaitingResponse(engine: engine)
            await resolvePropertyChoiceIfNeeded(engine: engine)
        }

        if case .playing = engine.state.phase,
           engine.state.currentPlayerIndex == playerIndex {
            engine.endTurn()
        }

        await handleDiscardIfNeeded(engine: engine)
    }

    // MARK: - Resolve Property Choice

    /// Handles .awaitingPropertyChoice when the CPU is the chooser.
    @MainActor
    func resolvePropertyChoiceIfNeeded(engine: GameEngine) async {
        guard case .awaitingPropertyChoice(let chooserIdx, let purpose) = engine.state.phase,
              chooserIdx == playerIndex else { return }

        await sleep(1.0)

        let log = GameLogger.shared
        let name = engine.state.players[playerIndex].name
        switch purpose {
        case .quickGrab(let targetIdx):
            let stealable = engine.state.players[targetIdx].properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
            if let card = stealable.max(by: { $0.monetaryValue < $1.monetaryValue }) {
                log.event("[\(name) quickGrab] stealing '\(card.name)' from \(engine.state.players[targetIdx].name)")
                engine.resolvePropertyChoice(purpose: purpose, selectedCardId: card.id)
            } else {
                log.warn("[\(name) quickGrab] no stealable properties found — passing")
                engine.resolvePropertyChoice(purpose: purpose)
            }

        case .dealSnatcher(let targetIdx):
            let completeSets = engine.state.players[targetIdx].properties.filter { $0.value.isComplete }
            if let (color, _) = completeSets.max(by: { $0.value.currentRent < $1.value.currentRent }) {
                log.event("[\(name) dealSnatcher] stealing \(color.displayName) set from \(engine.state.players[targetIdx].name)")
                engine.resolvePropertyChoice(purpose: purpose, selectedColor: color)
            } else {
                log.warn("[\(name) dealSnatcher] no complete sets found — passing")
                engine.resolvePropertyChoice(purpose: purpose)
            }

        case .swapIt(let targetIdx):
            let targetProps = engine.state.players[targetIdx].properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
            let myProps = engine.state.players[playerIndex].properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
            if let theirCard = targetProps.max(by: { $0.monetaryValue < $1.monetaryValue }),
               let myCard = myProps.min(by: { $0.monetaryValue < $1.monetaryValue }) {
                log.event("[\(name) swapIt] giving '\(myCard.name)', taking '\(theirCard.name)' from \(engine.state.players[targetIdx].name)")
                engine.resolvePropertyChoice(purpose: purpose, selectedCardId: myCard.id, secondaryCardId: theirCard.id)
            } else {
                log.warn("[\(name) swapIt] couldn't find swap candidates — passing")
                engine.resolvePropertyChoice(purpose: purpose)
            }

        default:
            log.event("[\(name) propertyChoice] unhandled purpose=\(purpose) — passing")
            engine.resolvePropertyChoice(purpose: purpose)
        }
    }

    // MARK: - Handle Response as Target

    /// Called when CPU is the target of an action (must decide whether to play No Deal!)
    @MainActor
    func respondToAction(actionCard: Card, engine: GameEngine) async {
        await sleep(1.0)

        let log = GameLogger.shared
        if let noDealCard = AIStrategy.shouldPlayNoDeal(
            state: engine.state,
            playerIndex: playerIndex,
            actionCard: actionCard,
            difficulty: difficulty
        ) {
            log.event("[\(engine.state.players[playerIndex].name)] plays No Deal! against '\(actionCard.name)'")
            engine.playNoDeal(cardId: noDealCard.id, playerIndex: playerIndex)
        } else {
            log.event("[\(engine.state.players[playerIndex].name)] accepts '\(actionCard.name)'")
            engine.acceptAction()
        }
    }

    // MARK: - Private Helpers

    private func executeDecision(_ decision: AIDecision, in engine: GameEngine) {
        let log = GameLogger.shared
        let name = engine.state.players[playerIndex].name
        switch decision.destination {
        case .bank:
            log.event("[\(name)] plays '\(decision.card.name)' → bank ($\(decision.card.monetaryValue)M)")
            engine.playCard(cardId: decision.card.id, as: .bank)

        case .property(let color):
            if case .wildProperty = decision.card.type, let wildColor = decision.wildColor {
                log.event("[\(name)] assigns wild '\(decision.card.name)' → \(wildColor.displayName)")
                engine.assignWildColor(cardId: decision.card.id, color: wildColor)
            } else {
                log.event("[\(name)] plays '\(decision.card.name)' → \(color.displayName)")
                engine.playCard(cardId: decision.card.id, as: .property(color))
            }

        case .action:
            let targetName = decision.targetPlayerIndex.map { engine.state.players[$0].name } ?? "all"
            log.event("[\(name)] plays action '\(decision.card.name)' → target=\(targetName)")
            engine.playCard(
                cardId: decision.card.id,
                as: .action,
                targetPlayerIndex: decision.targetPlayerIndex,
                targetPropertyColor: decision.targetPropertyColor
            )

        case .rent(let color):
            let targetName = decision.targetPlayerIndex.map { engine.state.players[$0].name } ?? "all"
            let colorName = color?.displayName ?? "wild"
            log.event("[\(name)] plays rent '\(decision.card.name)' color=\(colorName) → \(targetName)")
            engine.playCard(
                cardId: decision.card.id,
                as: .rent(color),
                targetPlayerIndex: decision.targetPlayerIndex
            )
        }
    }

    @MainActor
    private func handleAwaitingResponse(engine: GameEngine) async {
        if case .awaitingResponse(let targetIdx, let actionCard, _) = engine.state.phase,
           targetIdx == playerIndex {
            // This CPU is the actual target — respond
            await respondToAction(actionCard: actionCard, engine: engine)
        }
    }

    @MainActor
    private func handleDiscardIfNeeded(engine: GameEngine) async {
        guard case .discarding(let idx) = engine.state.phase,
              idx == playerIndex else { return }

        await sleep(0.6)

        // Discard lowest-value cards first
        while case .discarding(let idx) = engine.state.phase,
              idx == playerIndex,
              engine.state.players[playerIndex].hand.count > 7 {

            let hand = engine.state.players[playerIndex].hand
            if let lowestCard = hand.min(by: { $0.monetaryValue < $1.monetaryValue }) {
                GameLogger.shared.event("[\(engine.state.players[playerIndex].name)] discards '\(lowestCard.name)' ($\(lowestCard.monetaryValue)M) (hand: \(hand.count) → \(hand.count - 1))")
                engine.discard(cardId: lowestCard.id)
            }
            await sleep(0.6)
        }
    }

    private func sleep(_ duration: Double? = nil) async {
        let delay = duration ?? actionDelay
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
