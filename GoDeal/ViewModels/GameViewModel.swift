import Foundation
import SwiftUI

// MARK: - Game Setup

struct GameSetup {
    var humanPlayerName: String = ""
    var cpuDifficulty: AIDifficulty = .medium
    var cpuCount: Int = 1   // 1–3 CPU opponents
}

// MARK: - Game View Model

@Observable
@MainActor
final class GameViewModel {

    // MARK: - State

    var engine: GameEngine
    var cpuPlayers: [CPUPlayer] = []
    var isShowingNoDealSheet = false
    var isShowingPaymentSheet = false
    var isShowingDiscardSheet = false
    var isShowingActionTargetSheet = false
    var isShowingPropertyChoiceSheet = false
    var pendingActionCard: Card? = nil
    var selectedCard: Card? = nil
    var errorMessage: String? = nil
    var gameOverWinnerName: String? = nil

    // NoDeal sheet context (stored snapshot so sheet body doesn't rely on live phase)
    var pendingNoDealAttackerName: String = ""
    var pendingNoDealCards: [Card] = []
    var pendingNoDealActionDetail: String = ""

    // Payment choice state (set when awaitingPayment with human debtor)
    var pendingPaymentAmount: Int = 0
    var pendingPaymentCreditorIndex: Int? = nil
    var pendingPaymentReason: PaymentReason? = nil

    // Stuck-state watchdog
    private var stuckStateTask: Task<Void, Never>?

    // MARK: - Computed State

    var state: GameState { engine.state }
    var currentPlayer: Player { engine.state.currentPlayer }
    var humanPlayer: Player? { engine.state.players.first(where: { $0.isHuman }) }
    var humanPlayerIndex: Int? { engine.state.players.firstIndex(where: { $0.isHuman }) }

    var isHumanTurn: Bool {
        engine.state.players[engine.state.currentPlayerIndex].isHuman
    }

    var phase: GamePhase { engine.state.phase }

    var canEndTurn: Bool {
        isHumanTurn && (state.phase == .playing)
    }

    // MARK: - CPU Name Pool

    private static let cpuNamePool = [
        "Jonathan", "Nikhil", "Trusha", "Som", "Meha", "Ishan",
        "Vikram", "Amit", "Tejal", "Akshay", "Tanmay", "Ambi"
    ]

    // MARK: - Init

    init(setup: GameSetup = GameSetup()) {
        let humanName = setup.humanPlayerName.trimmingCharacters(in: .whitespaces)
        let humanPlayer = Player(name: humanName.isEmpty ? "You" : humanName, isHuman: true)
        let cpuCount = max(1, min(3, setup.cpuCount))

        // Pick random CPU names, excluding the human's name
        var namePool = Self.cpuNamePool
            .filter { $0.lowercased() != humanName.lowercased() }
            .shuffled()
        var players: [Player] = [humanPlayer]
        for _ in 0..<cpuCount {
            let name = namePool.isEmpty ? "CPU" : namePool.removeFirst()
            players.append(Player(name: name, isHuman: false))
        }

        let deck = DeckBuilder.buildDeck()
        var state = GameState(players: players, deck: deck)

        // Deal initial hands (5 cards each, matching Monopoly Deal rules)
        for playerIdx in 0..<state.players.count {
            let drawn = ActionResolver.drawCards(count: 5, from: &state)
            state.players[playerIdx].addToHand(drawn)
        }
        state.phase = .drawing

        let engine = GameEngine(state: state)
        self.engine = engine

        // Setup CPU players
        for (idx, player) in state.players.enumerated() where !player.isHuman {
            let cpu = CPUPlayer(playerIndex: idx, difficulty: setup.cpuDifficulty, engine: engine)
            cpuPlayers.append(cpu)
        }

        // Wire up engine callbacks
        engine.onGameOver = { [weak self] winnerIndex in
            self?.handleGameOver(winnerIndex: winnerIndex)
        }
        engine.onError = { [weak self] message in
            self?.errorMessage = message
        }
    }

    // MARK: - Human Actions

    /// Draw cards at start of turn
    func startTurn() {
        guard isHumanTurn, case .drawing = phase else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            engine.startTurn()
        }
    }

    /// Play a card from hand to bank
    func playToBank(cardId: UUID) {
        guard isHumanTurn, state.canPlayCard else { return }
        engine.playCard(cardId: cardId, as: .bank)
        clearError()
        autoEndTurnIfNeeded()
    }

    /// Play a property card to a specific color group
    func playProperty(cardId: UUID, color: PropertyColor) {
        guard isHumanTurn, state.canPlayCard else { return }
        engine.playCard(cardId: cardId, as: .property(color))
        clearError()
        autoEndTurnIfNeeded()
    }

    /// Play a wild property card and assign a color
    func playWildProperty(cardId: UUID, color: PropertyColor) {
        guard isHumanTurn, state.canPlayCard else { return }
        engine.assignWildColor(cardId: cardId, color: color)
        clearError()
        autoEndTurnIfNeeded()
    }

    /// Play a steal action (quickGrab/dealSnatcher/swapIt) after the human pre-selected the
    /// target property in the pre-action picker. The card stays in hand until this is called.
    func playActionWithPreSelection(
        cardId: UUID,
        targetPlayerIndex: Int,
        stealCardId: UUID? = nil,
        stealColor: PropertyColor? = nil,
        stealSecondaryCardId: UUID? = nil
    ) {
        guard isHumanTurn, state.canPlayCard else { return }
        engine.state.pendingSteal.cardId = stealCardId
        engine.state.pendingSteal.color = stealColor
        engine.state.pendingSteal.secondaryCardId = stealSecondaryCardId
        engine.playCard(cardId: cardId, as: .action, targetPlayerIndex: targetPlayerIndex)
        clearError()
        triggerCPUIfNeeded()
        autoEndTurnIfNeeded()
    }

    /// Play an action card
    func playAction(cardId: UUID, targetPlayerIndex: Int? = nil, targetPropertyColor: PropertyColor? = nil) {
        guard isHumanTurn, state.canPlayCard else { return }
        engine.playCard(
            cardId: cardId,
            as: .action,
            targetPlayerIndex: targetPlayerIndex,
            targetPropertyColor: targetPropertyColor
        )
        clearError()
        triggerCPUIfNeeded()
        autoEndTurnIfNeeded()
    }

    /// Play a rent card
    func playRent(cardId: UUID, color: PropertyColor, targetPlayerIndex: Int? = nil) {
        guard isHumanTurn, state.canPlayCard else { return }
        engine.playCard(
            cardId: cardId,
            as: .rent(color),
            targetPlayerIndex: targetPlayerIndex
        )
        clearError()
        triggerCPUIfNeeded()
        autoEndTurnIfNeeded()
    }

    /// Human plays No Deal! as a response
    func playNoDeal(cardId: UUID) {
        guard let humanIdx = humanPlayerIndex else { return }
        log.event("Human played No Deal! — cardId=\(cardId)")
        engine.playNoDeal(cardId: cardId, playerIndex: humanIdx)
        isShowingNoDealSheet = false
        triggerCPUIfNeeded()
    }

    /// Human accepts an action (does not play No Deal!)
    func acceptAction() {
        log.event("Human accepted action — card=\(pendingActionCard?.name ?? "?")")
        engine.acceptAction()
        isShowingNoDealSheet = false
        // Do NOT call triggerCPUIfNeeded() here — handlePhaseChange() fires via
        // onChange(of: state.phase) and handles CPU resumption. Double-triggering
        // causes the CPU to run its turn twice, advancing to human's turn prematurely.
    }

    /// Human ends their turn
    func endTurn() {
        guard isHumanTurn else { return }
        log.event("Human ended turn \(state.turnNumber) — hand=\(humanPlayer?.hand.count ?? 0) cards, sets=\(humanPlayer?.completedSets ?? 0)/3")
        engine.endTurn()
        triggerCPUIfNeeded()
    }

    /// Human submits their chosen payment cards
    func submitHumanPayment(bankCardIds: [UUID], propertyCardIds: [UUID]) {
        engine.executeHumanPayment(bankCardIds: bankCardIds, propertyCardIds: propertyCardIds)
        isShowingPaymentSheet = false
        pendingPaymentAmount = 0
        pendingPaymentCreditorIndex = nil
        pendingPaymentReason = nil
        triggerCPUIfNeeded()
    }

    /// Human cancels discard to go back and play more cards (only when < 3 cards played)
    func cancelDiscard() {
        engine.cancelDiscard()
        isShowingDiscardSheet = false
    }

    /// Human discards a card
    func discard(cardId: UUID) {
        engine.discard(cardId: cardId)
        // Auto-dismiss sheet once discard is complete
        if case .discarding = state.phase {
            // Still need to discard more — keep sheet open
        } else {
            isShowingDiscardSheet = false
        }
        if case .drawing = state.phase {
            triggerCPUIfNeeded()
        }
    }

    /// Move a wild card to a different color group — free action, no card count cost.
    func reassignWild(cardId: UUID, toColor: PropertyColor) {
        guard isHumanTurn else { return }
        engine.reassignWild(cardId: cardId, toColor: toColor)
    }

    /// Resolve a property choice (for quickGrab, swapIt, dealSnatcher)
    func resolvePropertyChoice(
        purpose: PropertyChoicePurpose,
        selectedCardId: UUID? = nil,
        selectedColor: PropertyColor? = nil,
        secondaryCardId: UUID? = nil
    ) {
        engine.resolvePropertyChoice(
            purpose: purpose,
            selectedCardId: selectedCardId,
            selectedColor: selectedColor,
            secondaryCardId: secondaryCardId
        )
        isShowingPropertyChoiceSheet = false
        triggerCPUIfNeeded()
    }

    // MARK: - CPU Turn Trigger

    @MainActor
    func triggerCPUIfNeeded() {
        guard !isHumanTurn else { return }
        let cpuIdx = state.currentPlayerIndex
        guard let cpu = cpuPlayers.first(where: { $0.playerIndex == cpuIdx }) else { return }

        Task {
            switch state.phase {
            case .drawing:
                await cpu.executeTurn()
            case .playing:
                await cpu.resumeTurn()
            case .awaitingPropertyChoice(let chooserIdx, _):
                // The chooser may be the attacker (current player) or a victim CPU
                if let chooserCPU = cpuPlayers.first(where: { $0.playerIndex == chooserIdx }) {
                    await chooserCPU.resolvePropertyChoiceIfNeeded(engine: engine)
                    // Resume attacker if it's still their turn
                    if case .playing = state.phase,
                       state.currentPlayerIndex == cpuIdx {
                        await cpu.resumeTurn()
                    }
                }
            default:
                break
            }

            // Chain to next CPU turn if needed — brief pause so SwiftUI can process the phase change
            if !state.players[state.currentPlayerIndex].isHuman,
               case .drawing = state.phase {
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.triggerCPUIfNeeded()
            }
        }
    }

    // MARK: - Phase Observation

    private let log = GameLogger.shared

    /// Called by view to handle phase changes (show sheets etc.)
    func handlePhaseChange() {
        // Reset stuck-state watchdog on every phase change
        stuckStateTask?.cancel()
        stuckStateTask = nil

        // Log every phase transition
        log.event("Turn \(state.turnNumber) · \(state.currentPlayer.name) · \(phaseDescription(state.phase))")

        // Populate the activity feed
        switch state.phase {
        case .awaitingPayment(let debtorIdx, let creditorIdx, let amount, _):
            let creditor = state.players[creditorIdx].name
            let debtor = state.players[debtorIdx].name
            log.addActivity("\(creditor) → \(debtor): pay $\(amount)M")
        case .awaitingResponse(_, let actionCard, let attackerIdx):
            log.addActivity("\(state.players[attackerIdx].name) played \(actionCard.name)")
        case .gameOver(let w):
            log.addActivity("🏆 \(state.players[w].name) wins!")
        default:
            break
        }

        switch state.phase {
        case .awaitingResponse(let targetIdx, let actionCard, let attackerIdx):
            if let humanIdx = humanPlayerIndex, targetIdx == humanIdx {
                // Snapshot context before showing sheet so the body doesn't rely on live phase
                pendingActionCard = actionCard
                pendingNoDealAttackerName = state.players[attackerIdx].name
                pendingNoDealCards = state.players[humanIdx].hand.filter { $0.isNoDeal }
                pendingNoDealActionDetail = computeNoDealDetail(actionCard: actionCard, attackerIdx: attackerIdx, targetIdx: humanIdx)
                log.event("Showing NoDeal sheet — attacker=\(pendingNoDealAttackerName) card=\(actionCard.name)")
                isShowingNoDealSheet = true
            } else {
                // CPU handles response automatically
                if let cpu = cpuPlayers.first(where: { $0.playerIndex == targetIdx }) {
                    Task { @MainActor in
                        await cpu.respondToAction(actionCard: actionCard, engine: engine)
                    }
                }
            }

        case .awaitingPayment(let debtorIdx, let creditorIdx, let amount, let reason):
            if let humanIdx = humanPlayerIndex, debtorIdx == humanIdx {
                let human = state.players[humanIdx]
                if human.totalAssets == 0 {
                    // Nothing to pay — auto-resolve
                    log.event("Human has $0 assets — auto-resolving payment")
                    engine.resolveCPUPayment(debtorIndex: humanIdx, creditorIndex: creditorIdx, amount: amount)
                    triggerCPUIfNeeded()
                } else {
                    // Store context and delay sheet presentation to avoid overlap with ActionTargetSheet dismissal
                    let capturedAmount = amount
                    let capturedCreditorIdx = creditorIdx
                    let capturedReason = reason
                    log.event("Scheduling PaymentSheet — amount=$\(amount)M creditor=\(state.players[creditorIdx].name)")
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard let self else { return }
                        guard case .awaitingPayment(let d, _, _, _) = self.state.phase,
                              let hIdx = self.humanPlayerIndex, d == hIdx else { return }
                        self.pendingPaymentAmount = capturedAmount
                        self.pendingPaymentCreditorIndex = capturedCreditorIdx
                        self.pendingPaymentReason = capturedReason
                        self.isShowingPaymentSheet = true
                    }
                }
            } else {
                // CPU debtor — auto-resolve
                engine.resolveCPUPayment(debtorIndex: debtorIdx, creditorIndex: creditorIdx, amount: amount)
                triggerCPUIfNeeded()
            }

        case .awaitingPropertyChoice(let chooserIdx, _):
            if let humanIdx = humanPlayerIndex, chooserIdx == humanIdx {
                // Delay to avoid presenting over a still-dismissing ActionTargetSheet
                let capturedChooserIdx = chooserIdx
                log.event("Scheduling PropertyChoiceSheet — chooser=\(state.players[chooserIdx].name)")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard let self else { return }
                    guard case .awaitingPropertyChoice(let c, _) = self.state.phase,
                          c == capturedChooserIdx else { return }
                    self.isShowingPropertyChoiceSheet = true
                }
            } else {
                // CPU needs to make a property choice
                triggerCPUIfNeeded()
            }

        case .discarding(let idx):
            if let humanIdx = humanPlayerIndex, idx == humanIdx {
                isShowingDiscardSheet = true
            }

        case .drawing:
            if !isHumanTurn {
                // Immediately start CPU's turn (phase just became .drawing for CPU)
                triggerCPUIfNeeded()
                // Also set a watchdog in case something goes wrong
                stuckStateTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard !Task.isCancelled, let self else { return }
                    self.log.warn("Stuck state detected (\(self.state.currentPlayer.name) drawing) — auto-triggering CPU")
                    self.triggerCPUIfNeeded()
                }
            }

        case .playing:
            if !isHumanTurn {
                // Immediately resume CPU's turn (phase just became .playing for CPU)
                triggerCPUIfNeeded()
                // Watchdog backup
                stuckStateTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard !Task.isCancelled, let self else { return }
                    self.log.warn("Stuck state detected (\(self.state.currentPlayer.name) playing) — auto-triggering CPU")
                    self.triggerCPUIfNeeded()
                }
            }

        case .awaitingWildColorChoice:
            break

        case .gameOver:
            break
        }
    }

    // MARK: - Private

    private func computeNoDealDetail(actionCard: Card, attackerIdx: Int, targetIdx: Int) -> String {
        guard case .action(let type) = actionCard.type else { return "" }
        let attacker = state.players[attackerIdx]
        let target = state.players[targetIdx]

        switch type {
        case .quickGrab:
            let stealable = target.properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
            if let best = stealable.max(by: { $0.monetaryValue < $1.monetaryValue }) {
                let colorName = target.properties
                    .first { $0.value.properties.contains { $0.id == best.id } }?.key.displayName ?? ""
                return "Will steal: \(best.name)\(colorName.isEmpty ? "" : " (\(colorName))")"
            }
            return "Will steal one of your properties"

        case .dealSnatcher:
            let sets = target.properties.values.filter { $0.isComplete }
            if let best = sets.max(by: { $0.currentRent < $1.currentRent }) {
                return "Will steal your complete \(best.color.displayName) set (\(best.properties.count) cards)"
            }
            return "Will steal one of your complete sets"

        case .swapIt:
            let humanProps = target.properties.values.flatMap { $0.properties }
            let cpuProps = attacker.properties.values.flatMap { $0.properties }
            if let humanCard = humanProps.max(by: { $0.monetaryValue < $1.monetaryValue }),
               let cpuCard = cpuProps.min(by: { $0.monetaryValue < $1.monetaryValue }) {
                return "Will take your \(humanCard.name), give you \(cpuCard.name)"
            }
            return "Will swap one of your properties"

        case .collectNow:
            return "You will owe $5M"

        case .bigSpender:
            return "You will owe $2M"

        default:
            return ""
        }
    }

    private func handleGameOver(winnerIndex: Int) {
        gameOverWinnerName = state.players[winnerIndex].name
        log.event("Game over — winner: \(state.players[winnerIndex].name)")
    }

    private func clearError() {
        errorMessage = nil
    }

    /// Auto-ends the human's turn after 3 cards are played, with a short delay for animation.
    private func autoEndTurnIfNeeded() {
        guard isHumanTurn, case .playing = state.phase, state.cardsPlayedThisTurn >= 3 else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, self.isHumanTurn,
                  case .playing = self.state.phase,
                  self.state.cardsPlayedThisTurn >= 3 else { return }
            self.log.event("Auto-ending turn (3/3 cards played)")
            self.engine.endTurn()
            self.triggerCPUIfNeeded()
        }
    }

    private func phaseDescription(_ phase: GamePhase) -> String {
        switch phase {
        case .drawing:                      return "drawing"
        case .playing:                      return "playing (\(state.cardsPlayedThisTurn)/3 played)"
        case .awaitingResponse(let t, let c, _): return "awaitingResponse target=\(state.players[t].name) card=\(c.name)"
        case .awaitingPayment(let d, let c, let a, _): return "awaitingPayment debtor=\(state.players[d].name) creditor=\(state.players[c].name) $\(a)M"
        case .awaitingPropertyChoice(let c, let p): return "awaitingPropertyChoice chooser=\(state.players[c].name) \(p)"
        case .awaitingWildColorChoice(let p, _): return "awaitingWildColor player=\(state.players[p].name)"
        case .discarding(let p):            return "discarding player=\(state.players[p].name)"
        case .gameOver(let w):              return "gameOver winner=\(state.players[w].name)"
        }
    }

    // MARK: - New Game

    func newGame(setup: GameSetup = GameSetup()) {
        let newVM = GameViewModel(setup: setup)
        self.engine = newVM.engine
        // Re-wire callbacks to self (newVM is temp and will be deallocated)
        self.engine.onGameOver = { [weak self] winnerIndex in
            self?.handleGameOver(winnerIndex: winnerIndex)
        }
        self.engine.onError = { [weak self] message in
            self?.errorMessage = message
        }
        self.cpuPlayers = newVM.cpuPlayers
        self.isShowingNoDealSheet = false
        self.isShowingPaymentSheet = false
        self.isShowingDiscardSheet = false
        self.pendingActionCard = nil
        self.pendingNoDealAttackerName = ""
        self.pendingNoDealCards = []
        self.pendingNoDealActionDetail = ""
        self.selectedCard = nil
        self.errorMessage = nil
        self.gameOverWinnerName = nil
        self.pendingPaymentAmount = 0
        self.pendingPaymentCreditorIndex = nil
        self.pendingPaymentReason = nil
    }
}
