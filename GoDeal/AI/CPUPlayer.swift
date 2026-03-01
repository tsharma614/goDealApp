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

    init(playerIndex: Int, difficulty: AIDifficulty, engine: GameEngine) {
        self.playerIndex = playerIndex
        self.difficulty = difficulty
        self.engine = engine
    }

    // MARK: - Execute Turn

    /// Runs the CPU's full turn asynchronously.
    @MainActor
    func executeTurn() async {
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
        switch purpose {
        case .quickGrab(let targetIdx):
            let stealable = engine.state.players[targetIdx].properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
            if let card = stealable.max(by: { $0.monetaryValue < $1.monetaryValue }) {
                log.event("[CPU quickGrab choice] stealing '\(card.name)' from \(engine.state.players[targetIdx].name)")
                engine.resolvePropertyChoice(purpose: purpose, selectedCardId: card.id)
            } else {
                log.warn("[CPU quickGrab choice] no stealable properties found — passing")
                engine.resolvePropertyChoice(purpose: purpose)
            }

        case .dealSnatcher(let targetIdx):
            let completeSets = engine.state.players[targetIdx].properties.filter { $0.value.isComplete }
            if let (color, _) = completeSets.max(by: { $0.value.currentRent < $1.value.currentRent }) {
                log.event("[CPU dealSnatcher choice] stealing \(color.displayName) set from \(engine.state.players[targetIdx].name)")
                engine.resolvePropertyChoice(purpose: purpose, selectedColor: color)
            } else {
                log.warn("[CPU dealSnatcher choice] no complete sets found — passing")
                engine.resolvePropertyChoice(purpose: purpose)
            }

        case .swapIt(let targetIdx):
            let targetProps = engine.state.players[targetIdx].properties.values.flatMap { $0.properties }
            let myProps = engine.state.players[playerIndex].properties.values.flatMap { $0.properties }
            if let theirCard = targetProps.max(by: { $0.monetaryValue < $1.monetaryValue }),
               let myCard = myProps.min(by: { $0.monetaryValue < $1.monetaryValue }) {
                log.event("[CPU swapIt choice] giving '\(myCard.name)', taking '\(theirCard.name)' from \(engine.state.players[targetIdx].name)")
                engine.resolvePropertyChoice(purpose: purpose, selectedCardId: myCard.id, secondaryCardId: theirCard.id)
            } else {
                log.warn("[CPU swapIt choice] couldn't find swap candidates — passing")
                engine.resolvePropertyChoice(purpose: purpose)
            }

        default:
            log.event("[CPU propertyChoice] unhandled purpose=\(purpose) — passing")
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
            log.event("[CPU player=\(playerIndex)] plays No Deal! against '\(actionCard.name)'")
            engine.playNoDeal(cardId: noDealCard.id, playerIndex: playerIndex)
        } else {
            log.event("[CPU player=\(playerIndex)] accepts '\(actionCard.name)'")
            engine.acceptAction()
        }
    }

    // MARK: - Private Helpers

    private func executeDecision(_ decision: AIDecision, in engine: GameEngine) {
        let log = GameLogger.shared
        switch decision.destination {
        case .bank:
            log.event("[CPU] plays '\(decision.card.name)' → bank ($\(decision.card.monetaryValue)M)")
            engine.playCard(cardId: decision.card.id, as: .bank)

        case .property(let color):
            if case .wildProperty = decision.card.type, let wildColor = decision.wildColor {
                log.event("[CPU] assigns wild '\(decision.card.name)' → \(wildColor.displayName)")
                engine.assignWildColor(cardId: decision.card.id, color: wildColor)
            } else {
                log.event("[CPU] plays '\(decision.card.name)' → \(color.displayName)")
                engine.playCard(cardId: decision.card.id, as: .property(color))
            }

        case .action:
            let targetName = decision.targetPlayerIndex.map { engine.state.players[$0].name } ?? "all"
            log.event("[CPU] plays action '\(decision.card.name)' → target=\(targetName)")
            engine.playCard(
                cardId: decision.card.id,
                as: .action,
                targetPlayerIndex: decision.targetPlayerIndex,
                targetPropertyColor: decision.targetPropertyColor
            )

        case .rent(let color):
            let targetName = decision.targetPlayerIndex.map { engine.state.players[$0].name } ?? "all"
            let colorName = color?.displayName ?? "wild"
            log.event("[CPU] plays rent '\(decision.card.name)' color=\(colorName) → \(targetName)")
            engine.playCard(
                cardId: decision.card.id,
                as: .rent(color),
                targetPlayerIndex: decision.targetPlayerIndex
            )
        }
    }

    @MainActor
    private func handleAwaitingResponse(engine: GameEngine) async {
        if case .awaitingResponse(_, let actionCard, let attackerIndex) = engine.state.phase {
            // If CPU is the target, respond
            if engine.state.currentPlayerIndex != playerIndex {
                // We are the target
                await respondToAction(actionCard: actionCard, engine: engine)
            } else {
                // We are the attacker waiting — just accept if no response from opponent
                // (Human target handled by UI)
            }
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
                GameLogger.shared.event("[CPU] discards '\(lowestCard.name)' ($\(lowestCard.monetaryValue)M) (hand: \(hand.count) → \(hand.count - 1))")
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
