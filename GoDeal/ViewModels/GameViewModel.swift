import Foundation
import SwiftUI
import MultipeerConnectivity
import GameKit

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

    // MARK: - Multiplayer state

    var networkSession: (any NetworkSession)? = nil
    var localPlayerIndex: Int = 0
    var isHost: Bool { networkSession == nil || networkSession?.role == .host }

    /// Guest: set when host sends `.playAgainRequest` — triggers confirmation dialog in view
    var showPlayAgainConfirmation = false
    /// Host: set while waiting for guest to confirm play again
    var isWaitingForPlayAgain = false
    /// Set when a remote player drops mid-game (GameKit only); view shows a dismissal alert.
    var playerDisconnectedAlert: Bool = false

    /// Host-side: maps stable peer ID → player index in state.players
    private var peerPlayerIndexMap: [String: Int] = [:]

    // Stuck-state watchdog
    private var stuckStateTask: Task<Void, Never>?

    // MARK: - Computed State

    var state: GameState { engine.state }
    var currentPlayer: Player { engine.state.currentPlayer }
    var humanPlayer: Player? { state.players[safe: localPlayerIndex] }
    var humanPlayerIndex: Int? { localPlayerIndex }

    var isHumanTurn: Bool {
        engine.state.currentPlayerIndex == localPlayerIndex
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

    // MARK: - Solo Init

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
        self.localPlayerIndex = 0

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

    // MARK: - Multiplayer Host Init

    /// Host creates the game after lobby is ready. All players are real humans; no CPUPlayer objects.
    init(setup: GameSetup, session: MultipeerSession, localPlayerIndex: Int = 0) {
        // Prefer setup name, fall back to whatever name the host typed in the lobby
        // (stored as MCPeerID.displayName), then "You" as last resort.
        let setupName = setup.humanPlayerName.trimmingCharacters(in: .whitespaces)
        let hostName = !setupName.isEmpty ? setupName : session.myPeerID.displayName
        let guests = session.connectedPeers

        var players: [Player] = [Player(name: hostName.isEmpty ? "You" : hostName, isHuman: true)]
        for peer in guests {
            players.append(Player(name: peer.displayName, isHuman: true))
        }

        let deck = DeckBuilder.buildDeck()
        var state = GameState(players: players, deck: deck)
        for playerIdx in 0..<state.players.count {
            let drawn = ActionResolver.drawCards(count: 5, from: &state)
            state.players[playerIdx].addToHand(drawn)
        }
        state.phase = .drawing

        let engine = GameEngine(state: state)
        self.engine = engine
        self.networkSession = session
        self.localPlayerIndex = localPlayerIndex

        // Build peer → player-index map (keyed by displayName, matching NetworkSession.send toPeerIDs)
        for (offset, peer) in guests.enumerated() {
            peerPlayerIndexMap[peer.displayName] = offset + 1
        }

        engine.onGameOver = { [weak self] winnerIndex in
            self?.handleGameOver(winnerIndex: winnerIndex)
        }
        engine.onError = { [weak self] message in
            self?.errorMessage = message
        }
        wireSessionCallbacks()
    }

    // MARK: - Multiplayer Guest Init (MC)

    /// Guest device (local play): creates a minimal placeholder engine. Real state arrives via broadcasts.
    init(session: MultipeerSession, localPlayerIndex: Int) {
        let placeholder = Player(name: session.myPeerID.displayName, isHuman: true)
        let emptyState = GameState(players: [placeholder], deck: [])
        let engine = GameEngine(state: emptyState)
        self.engine = engine
        self.networkSession = session
        self.localPlayerIndex = localPlayerIndex

        engine.onGameOver = { [weak self] winnerIndex in
            self?.handleGameOver(winnerIndex: winnerIndex)
        }
        engine.onError = { [weak self] message in
            self?.errorMessage = message
        }
        wireSessionCallbacks()
    }

    // MARK: - GameKit Host Init

    /// Host init for internet play. Creates full game state from GKMatch players.
    init(setup: GameSetup, session: GameKitSession, localPlayerIndex: Int = 0) {
        let setupName = setup.humanPlayerName.trimmingCharacters(in: .whitespaces)
        let hostName = !setupName.isEmpty ? setupName : GKLocalPlayer.local.displayName

        var players: [Player] = [Player(name: hostName.isEmpty ? "You" : hostName, isHuman: true)]
        var map: [String: Int] = [:]
        for (offset, (peerID, name)) in zip(session.connectedPeerIDs, session.connectedPeerNames).enumerated() {
            players.append(Player(name: name, isHuman: true))
            map[peerID] = offset + 1
        }

        let deck = DeckBuilder.buildDeck()
        var state = GameState(players: players, deck: deck)
        for i in 0..<state.players.count {
            let drawn = ActionResolver.drawCards(count: 5, from: &state)
            state.players[i].addToHand(drawn)
        }
        state.phase = .drawing

        let engine = GameEngine(state: state)
        self.engine = engine
        self.networkSession = session
        self.localPlayerIndex = localPlayerIndex
        self.peerPlayerIndexMap = map

        engine.onGameOver = { [weak self] wi in self?.handleGameOver(winnerIndex: wi) }
        engine.onError = { [weak self] msg in self?.errorMessage = msg }
        wireSessionCallbacks()

        // Broadcast initial state to all guests
        Task { @MainActor [weak self] in
            guard let self else { return }
            for (offset, peerID) in session.connectedPeerIDs.enumerated() {
                session.send(.playerAssignment(localPlayerIndex: offset + 1), toPeerIDs: [peerID])
            }
            session.send(.gameState(self.engine.state))
            session.send(.gameStart)
        }
    }

    // MARK: - GameKit Guest Init

    /// Guest init for internet play. Placeholder state; real state arrives via host broadcasts.
    init(session: GameKitSession, localPlayerIndex: Int) {
        let name = GKLocalPlayer.local.displayName
        let placeholder = Player(name: name.isEmpty ? "Player" : name, isHuman: true)
        let emptyState = GameState(players: [placeholder], deck: [])
        let engine = GameEngine(state: emptyState)
        self.engine = engine
        self.networkSession = session
        self.localPlayerIndex = localPlayerIndex

        engine.onGameOver = { [weak self] wi in self?.handleGameOver(winnerIndex: wi) }
        engine.onError = { [weak self] msg in self?.errorMessage = msg }
        wireSessionCallbacks()
    }

    // MARK: - Human Actions

    /// Draw cards at start of turn. Routed through the host in multiplayer.
    func startTurn() {
        guard isHumanTurn, case .drawing = phase else { return }
        routeAction(.startTurn, callerIndex: localPlayerIndex)
    }

    /// Play a card from hand to bank
    func playToBank(cardId: UUID) {
        guard isHumanTurn, state.canPlayCard else { return }
        routeAction(.playToBank(cardId: cardId), callerIndex: localPlayerIndex)
        clearError()
        if isHost { autoEndTurnIfNeeded() }
    }

    /// Play a property card to a specific color group
    func playProperty(cardId: UUID, color: PropertyColor) {
        guard isHumanTurn, state.canPlayCard else { return }
        routeAction(.playProperty(cardId: cardId, color: color), callerIndex: localPlayerIndex)
        clearError()
        if isHost { autoEndTurnIfNeeded() }
    }

    /// Play a wild property card and assign a color
    func playWildProperty(cardId: UUID, color: PropertyColor) {
        guard isHumanTurn, state.canPlayCard else { return }
        routeAction(.playWildProperty(cardId: cardId, color: color), callerIndex: localPlayerIndex)
        clearError()
        if isHost { autoEndTurnIfNeeded() }
    }

    /// Play a steal action (quickGrab/dealSnatcher/swapIt) after pre-selecting the target property.
    func playActionWithPreSelection(
        cardId: UUID,
        targetPlayerIndex: Int,
        stealCardId: UUID? = nil,
        stealColor: PropertyColor? = nil,
        stealSecondaryCardId: UUID? = nil
    ) {
        guard isHumanTurn, state.canPlayCard else { return }
        routeAction(.playActionWithPreSelection(
            cardId: cardId,
            targetPlayerIndex: targetPlayerIndex,
            stealCardId: stealCardId,
            stealColor: stealColor,
            stealSecondaryCardId: stealSecondaryCardId
        ), callerIndex: localPlayerIndex)
        clearError()
        if isHost {
            triggerCPUIfNeeded()
            autoEndTurnIfNeeded()
        }
    }

    /// Play an action card
    func playAction(cardId: UUID, targetPlayerIndex: Int? = nil, targetPropertyColor: PropertyColor? = nil) {
        guard isHumanTurn, state.canPlayCard else { return }
        routeAction(.playAction(
            cardId: cardId,
            targetPlayerIndex: targetPlayerIndex,
            targetPropertyColor: targetPropertyColor
        ), callerIndex: localPlayerIndex)
        clearError()
        if isHost {
            triggerCPUIfNeeded()
            autoEndTurnIfNeeded()
        }
    }

    /// Play a rent card
    func playRent(cardId: UUID, color: PropertyColor, targetPlayerIndex: Int? = nil) {
        guard isHumanTurn, state.canPlayCard else { return }
        routeAction(.playRent(cardId: cardId, color: color, targetPlayerIndex: targetPlayerIndex),
                    callerIndex: localPlayerIndex)
        clearError()
        if isHost {
            triggerCPUIfNeeded()
            autoEndTurnIfNeeded()
        }
    }

    /// Human plays No Deal! as a response
    func playNoDeal(cardId: UUID) {
        log.event("Human played No Deal! — cardId=\(cardId)")
        routeAction(.playNoDeal(cardId: cardId), callerIndex: localPlayerIndex)
        isShowingNoDealSheet = false
        if isHost { triggerCPUIfNeeded() }
    }

    /// Human accepts an action (does not play No Deal!)
    func acceptAction() {
        log.event("Human accepted action — card=\(pendingActionCard?.name ?? "?")")
        routeAction(.acceptAction, callerIndex: localPlayerIndex)
        isShowingNoDealSheet = false
        // Do NOT call triggerCPUIfNeeded() here — handlePhaseChange() fires via
        // onChange(of: state.phase) and handles CPU resumption. Double-triggering
        // causes the CPU to run its turn twice, advancing to human's turn prematurely.
    }

    /// Human ends their turn
    func endTurn() {
        guard isHumanTurn else { return }
        log.event("Human ended turn \(state.turnNumber) — hand=\(humanPlayer?.hand.count ?? 0) cards, sets=\(humanPlayer?.completedSets ?? 0)/3")
        routeAction(.endTurn, callerIndex: localPlayerIndex)
        if isHost { triggerCPUIfNeeded() }
    }

    /// Human submits their chosen payment cards
    func submitHumanPayment(bankCardIds: [UUID], propertyCardIds: [UUID]) {
        routeAction(.submitPayment(bankCardIds: bankCardIds, propertyCardIds: propertyCardIds),
                    callerIndex: localPlayerIndex)
        isShowingPaymentSheet = false
        pendingPaymentAmount = 0
        pendingPaymentCreditorIndex = nil
        pendingPaymentReason = nil
        if isHost { triggerCPUIfNeeded() }
    }

    /// Human cancels discard to go back and play more cards (only when < 3 cards played)
    func cancelDiscard() {
        routeAction(.cancelDiscard, callerIndex: localPlayerIndex)
        isShowingDiscardSheet = false
    }

    /// Human discards a card
    func discard(cardId: UUID) {
        routeAction(.discard(cardId: cardId), callerIndex: localPlayerIndex)
        // Auto-dismiss sheet once discard is complete
        if case .discarding = state.phase {
            // Still need to discard more — keep sheet open
        } else {
            isShowingDiscardSheet = false
        }
        if isHost, case .drawing = state.phase {
            triggerCPUIfNeeded()
        }
    }

    /// Move a wild card to a different color group — free action, no card count cost.
    func reassignWild(cardId: UUID, toColor: PropertyColor) {
        guard isHumanTurn else { return }
        routeAction(.reassignWild(cardId: cardId, toColor: toColor), callerIndex: localPlayerIndex)
    }

    /// Resolve a property choice (for quickGrab, swapIt, dealSnatcher)
    func resolvePropertyChoice(
        purpose: PropertyChoicePurpose,
        selectedCardId: UUID? = nil,
        selectedColor: PropertyColor? = nil,
        secondaryCardId: UUID? = nil
    ) {
        routeAction(.resolvePropertyChoice(
            purpose: purpose,
            selectedCardId: selectedCardId,
            selectedColor: selectedColor,
            secondaryCardId: secondaryCardId
        ), callerIndex: localPlayerIndex)
        isShowingPropertyChoiceSheet = false
        if isHost { triggerCPUIfNeeded() }
    }

    // MARK: - Network Routing

    /// Route an action: host executes immediately; guest sends over network.
    private func routeAction(_ action: PlayerAction, callerIndex: Int) {
        if isHost {
            executeAction(action, callerIndex: callerIndex)
            broadcastState()
        } else {
            networkSession?.send(.playerAction(action))
        }
    }

    /// Execute a player action directly on the engine. Host-only.
    private func executeAction(_ action: PlayerAction, callerIndex: Int) {
        switch action {
        case .playToBank(let cardId):
            engine.playCard(cardId: cardId, as: .bank)

        case .playProperty(let cardId, let color):
            engine.playCard(cardId: cardId, as: .property(color))

        case .playWildProperty(let cardId, let color):
            engine.assignWildColor(cardId: cardId, color: color)

        case .playAction(let cardId, let targetIdx, let targetColor):
            engine.playCard(cardId: cardId, as: .action,
                            targetPlayerIndex: targetIdx,
                            targetPropertyColor: targetColor)

        case .playActionWithPreSelection(let cardId, let targetIdx, let stealCardId, let stealColor, let stealSecondaryCardId):
            engine.state.pendingSteal.cardId = stealCardId
            engine.state.pendingSteal.color = stealColor
            engine.state.pendingSteal.secondaryCardId = stealSecondaryCardId
            engine.playCard(cardId: cardId, as: .action, targetPlayerIndex: targetIdx)

        case .playRent(let cardId, let color, let targetIdx):
            engine.playCard(cardId: cardId, as: .rent(color), targetPlayerIndex: targetIdx)

        case .playNoDeal(let cardId):
            engine.playNoDeal(cardId: cardId, playerIndex: callerIndex)

        case .acceptAction:
            engine.acceptAction()

        case .endTurn:
            engine.endTurn()

        case .submitPayment(let bankIds, let propIds):
            engine.executeHumanPayment(bankCardIds: bankIds, propertyCardIds: propIds)

        case .cancelDiscard:
            engine.cancelDiscard()

        case .discard(let cardId):
            engine.discard(cardId: cardId)

        case .reassignWild(let cardId, let toColor):
            engine.reassignWild(cardId: cardId, toColor: toColor)

        case .resolvePropertyChoice(let purpose, let selectedCardId, let selectedColor, let secondaryCardId):
            engine.resolvePropertyChoice(
                purpose: purpose,
                selectedCardId: selectedCardId,
                selectedColor: selectedColor,
                secondaryCardId: secondaryCardId
            )

        case .startTurn:
            engine.startTurn()
        }
    }

    // MARK: - Host: broadcast state

    private func broadcastState() {
        guard isHost, let session = networkSession else { return }
        session.send(.gameState(engine.state))
    }

    // MARK: - Guest: apply incoming state

    func applyNetworkState(_ newState: GameState) {
        engine.state = newState
        // SwiftUI's @Observable system will notify views via observation tracking.
        // updateGuestUI() drives sheet visibility for the local guest player.
        updateGuestUI()
    }

    /// Guest: update overlay sheet visibility based on current phase.
    private func updateGuestUI() {
        let humanIdx = localPlayerIndex
        switch state.phase {
        case .awaitingResponse(let targetIdx, let actionCard, let attackerIdx):
            if targetIdx == humanIdx {
                pendingActionCard = actionCard
                pendingNoDealAttackerName = state.players[attackerIdx].name
                pendingNoDealCards = state.players[targetIdx].hand.filter { $0.isNoDeal }
                pendingNoDealActionDetail = computeNoDealDetail(
                    actionCard: actionCard, attackerIdx: attackerIdx, targetIdx: targetIdx)
                isShowingNoDealSheet = true
            }

        case .awaitingPayment(let debtorIdx, let creditorIdx, let amount, let reason):
            if debtorIdx == humanIdx {
                let me = state.players[humanIdx]
                if me.totalAssets == 0 {
                    networkSession?.send(.playerAction(.submitPayment(bankCardIds: [], propertyCardIds: [])))
                } else {
                    pendingPaymentAmount = amount
                    pendingPaymentCreditorIndex = creditorIdx
                    pendingPaymentReason = reason
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard let self,
                              case .awaitingPayment(let d, _, _, _) = self.state.phase,
                              d == humanIdx else { return }
                        self.isShowingPaymentSheet = true
                    }
                }
            }

        case .awaitingPropertyChoice(let chooserIdx, _):
            if chooserIdx == humanIdx {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard let self,
                          case .awaitingPropertyChoice(let c, _) = self.state.phase,
                          c == chooserIdx else { return }
                    self.isShowingPropertyChoiceSheet = true
                }
            }

        case .discarding(let idx):
            if idx == humanIdx {
                isShowingDiscardSheet = true
            }

        case .gameOver(let w):
            handleGameOver(winnerIndex: w)

        default:
            break
        }
    }

    // MARK: - Host: handle incoming player action

    func handleIncomingAction(_ action: PlayerAction, from peerIndex: Int) {
        // For response/payment/choice actions, the sender may not be the current player
        switch action {
        case .playNoDeal, .acceptAction, .submitPayment,
             .resolvePropertyChoice, .discard, .cancelDiscard:
            break  // allowed from any player (they are responding, not acting as current player)
        default:
            guard state.currentPlayerIndex == peerIndex else { return }
        }
        executeAction(action, callerIndex: peerIndex)
        // NOTE: handlePhaseChange() is NOT called here — onChange(of: viewModel.state.phase)
        // in GameBoardView fires automatically when phase changes, avoiding double calls.
        broadcastState()
        triggerCPUIfNeeded()

        // Auto-end guest's turn after 3 cards (mirrors autoEndTurnIfNeeded for local player)
        if state.currentPlayerIndex == peerIndex,
           case .playing = state.phase,
           state.cardsPlayedThisTurn >= 3 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard let self,
                      self.state.currentPlayerIndex == peerIndex,
                      case .playing = self.state.phase,
                      self.state.cardsPlayedThisTurn >= 3 else { return }
                self.log.event("Auto-ending turn for \(self.state.players[peerIndex].name) (3/3 cards played)")
                self.executeAction(.endTurn, callerIndex: peerIndex)
                // onChange fires automatically for the phase change; no handlePhaseChange() here
                self.broadcastState()
                self.triggerCPUIfNeeded()
            }
        }
    }

    // MARK: - Wire Session Callbacks

    private func wireSessionCallbacks() {
        networkSession?.onReceive = { [weak self] message, peerID in
            guard let self else { return }
            switch message {
            case .gameState(let gs):
                guard !self.isHost else { return }
                self.applyNetworkState(gs)
            case .playerAction(let action):
                guard self.isHost else { return }
                let idx = self.peerIndex(for: peerID)
                self.handleIncomingAction(action, from: idx)
            case .playAgainRequest:
                guard !self.isHost else { return }
                self.showPlayAgainConfirmation = true
            case .playAgainConfirm:
                guard self.isHost else { return }
                self.newMultiplayerGame()
            default:
                break
            }
        }

        networkSession?.onDisconnect = { [weak self] in
            self?.playerDisconnectedAlert = true
        }
    }

    private func peerIndex(for peerID: String) -> Int {
        peerPlayerIndexMap[peerID] ?? -1
    }

    // MARK: - CPU Turn Trigger

    @MainActor
    func triggerCPUIfNeeded() {
        guard networkSession == nil else { return }   // no CPU in multiplayer
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

        // Guest: sheet updates are driven by applyNetworkState → updateGuestUI
        guard isHost else { return }

        let humanIdx = localPlayerIndex

        switch state.phase {
        case .awaitingResponse(let targetIdx, let actionCard, let attackerIdx):
            if targetIdx == humanIdx {
                // Snapshot context before showing sheet so the body doesn't rely on live phase
                pendingActionCard = actionCard
                pendingNoDealAttackerName = state.players[attackerIdx].name
                pendingNoDealCards = state.players[humanIdx].hand.filter { $0.isNoDeal }
                pendingNoDealActionDetail = computeNoDealDetail(actionCard: actionCard, attackerIdx: attackerIdx, targetIdx: humanIdx)
                log.event("Showing NoDeal sheet — attacker=\(pendingNoDealAttackerName) card=\(actionCard.name)")
                isShowingNoDealSheet = true
            } else if networkSession == nil {
                // Solo: CPU handles response automatically
                if let cpu = cpuPlayers.first(where: { $0.playerIndex == targetIdx }) {
                    Task { @MainActor in
                        await cpu.respondToAction(actionCard: actionCard, engine: engine)
                    }
                }
            }
            // Multiplayer non-local target: wait for that device to send response

        case .awaitingPayment(let debtorIdx, let creditorIdx, let amount, let reason):
            if debtorIdx == humanIdx {
                let human = state.players[humanIdx]
                if human.totalAssets == 0 {
                    // Nothing to pay — auto-resolve
                    log.event("Human has $0 assets — auto-resolving payment")
                    engine.resolveCPUPayment(debtorIndex: humanIdx, creditorIndex: creditorIdx, amount: amount)
                    broadcastState()
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
                              d == humanIdx else { return }
                        self.pendingPaymentAmount = capturedAmount
                        self.pendingPaymentCreditorIndex = capturedCreditorIdx
                        self.pendingPaymentReason = capturedReason
                        self.isShowingPaymentSheet = true
                    }
                }
            } else if networkSession == nil {
                // Solo: CPU debtor — auto-resolve
                engine.resolveCPUPayment(debtorIndex: debtorIdx, creditorIndex: creditorIdx, amount: amount)
                triggerCPUIfNeeded()
            }
            // Multiplayer non-local: wait for that player's device to send submitPayment

        case .awaitingPropertyChoice(let chooserIdx, _):
            if chooserIdx == humanIdx {
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
            } else if networkSession == nil {
                // Solo: CPU needs to make a property choice
                triggerCPUIfNeeded()
            }
            // Multiplayer non-local: wait for network

        case .discarding(let idx):
            if idx == humanIdx {
                isShowingDiscardSheet = true
            }
            // Solo: CPU handles discard in its turn; multiplayer: wait for player's device

        case .drawing:
            if networkSession == nil && !isHumanTurn {
                // Solo: immediately start CPU's turn (CPU auto-draws; human uses Draw button)
                triggerCPUIfNeeded()
                stuckStateTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    guard !Task.isCancelled, let self else { return }
                    self.log.warn("Stuck state detected (\(self.state.currentPlayer.name) drawing) — auto-triggering CPU")
                    self.triggerCPUIfNeeded()
                }
            }
            // Multiplayer: each player presses their own Draw button; no auto-draw

        case .playing:
            if networkSession == nil && !isHumanTurn {
                // Solo: immediately resume CPU's turn
                triggerCPUIfNeeded()
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
        // Rent cards (Collect Dues / Rent Blitz!) now go through the NoDeal chain too.
        if case .rent = actionCard.type {
            let amount = state.pendingRentAmount
            let colorName = state.pendingRentColor?.displayName ?? "?"
            return "You will owe $\(amount)M rent (\(colorName))"
        }
        if case .wildRent = actionCard.type {
            let amount = state.pendingRentAmount
            let colorName = state.pendingRentColor?.displayName ?? "?"
            return "You will owe $\(amount)M rent (\(colorName))"
        }

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
        guard state.players.indices.contains(winnerIndex) else { return }
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
            self.routeAction(.endTurn, callerIndex: self.localPlayerIndex)
            self.broadcastState()
            self.triggerCPUIfNeeded()
        }
    }

    private func phaseDescription(_ phase: GamePhase) -> String {
        switch phase {
        case .drawing:                      return "drawing"
        case .playing:                      return "playing (\(state.cardsPlayedThisTurn)/3 played)"
        case .awaitingResponse(let t, let c, _): return "awaitingResponse target=\(state.players[safe: t]?.name ?? "?") card=\(c.name)"
        case .awaitingPayment(let d, let c, let a, _): return "awaitingPayment debtor=\(state.players[safe: d]?.name ?? "?") creditor=\(state.players[safe: c]?.name ?? "?") $\(a)M"
        case .awaitingPropertyChoice(let c, let p): return "awaitingPropertyChoice chooser=\(state.players[safe: c]?.name ?? "?") \(p)"
        case .awaitingWildColorChoice(let p, _): return "awaitingWildColor player=\(state.players[safe: p]?.name ?? "?")"
        case .discarding(let p):            return "discarding player=\(state.players[safe: p]?.name ?? "?")"
        case .gameOver(let w):              return "gameOver winner=\(state.players[safe: w]?.name ?? "?")"
        }
    }

    // MARK: - Multiplayer Play Again

    /// Host: broadcast a play-again request to all guests.
    func requestPlayAgain() {
        guard let session = networkSession else { return }
        isWaitingForPlayAgain = true
        session.send(.playAgainRequest)
    }

    /// Guest: accept the host's play-again request.
    func confirmPlayAgain() {
        guard let session = networkSession else { return }
        showPlayAgainConfirmation = false
        session.send(.playAgainConfirm)
    }

    /// Host: cancel waiting (e.g. guest never responded).
    func cancelWaitingForPlayAgain() {
        isWaitingForPlayAgain = false
    }

    /// Host: reinitialize the game with the same players / session. Broadcasts initial state.
    private func newMultiplayerGame() {
        guard let session = networkSession else { return }
        let playerNames = state.players.map { $0.name }
        let players = playerNames.map { Player(name: $0, isHuman: true) }

        let deck = DeckBuilder.buildDeck()
        var newState = GameState(players: players, deck: deck)
        for playerIdx in 0..<newState.players.count {
            let drawn = ActionResolver.drawCards(count: 5, from: &newState)
            newState.players[playerIdx].addToHand(drawn)
        }
        newState.phase = .drawing

        let newEngine = GameEngine(state: newState)
        newEngine.onGameOver = { [weak self] wi in self?.handleGameOver(winnerIndex: wi) }
        newEngine.onError = { [weak self] msg in self?.errorMessage = msg }

        self.engine = newEngine
        self.isWaitingForPlayAgain = false
        self.showPlayAgainConfirmation = false
        self.isShowingNoDealSheet = false
        self.isShowingPaymentSheet = false
        self.isShowingDiscardSheet = false
        self.isShowingPropertyChoiceSheet = false
        self.pendingActionCard = nil
        self.errorMessage = nil
        self.gameOverWinnerName = nil
        self.pendingPaymentAmount = 0
        self.pendingPaymentCreditorIndex = nil
        self.pendingPaymentReason = nil
        self.pendingNoDealAttackerName = ""
        self.pendingNoDealCards = []
        self.pendingNoDealActionDetail = ""

        session.send(.gameState(engine.state))
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
        self.networkSession = nil
        self.localPlayerIndex = 0
        self.peerPlayerIndexMap = [:]
        self.playerDisconnectedAlert = false
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
