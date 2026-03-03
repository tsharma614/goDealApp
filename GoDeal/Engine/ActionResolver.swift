import Foundation

// MARK: - Action Resolver
// Stateless: takes inout GameState, returns updated state.
// All action-specific logic lives here.

enum ActionResolverError: Error, LocalizedError {
    case invalidTarget
    case noCompleteSet
    case noIncompleteSet
    case noPropertiesAvailable
    case cannotAddImprovement
    case needsColorChoice

    var errorDescription: String? {
        switch self {
        case .invalidTarget:          return "Invalid target selected."
        case .noCompleteSet:          return "Target has no complete property set."
        case .noIncompleteSet:        return "Target has no incomplete property set."
        case .noPropertiesAvailable:  return "Target has no properties to steal."
        case .cannotAddImprovement:   return "Cannot add improvement to this set."
        case .needsColorChoice:       return "A color must be chosen for this wild card."
        }
    }
}

enum ActionResolver {

    // MARK: - Main Dispatch

    /// Play an action card. Returns true if the action was handled immediately,
    /// or sets state.phase to awaitingResponse/awaitingPayment if target must respond.
    static func resolve(
        card: Card,
        playerIndex: Int,
        targetPlayerIndex: Int?,
        targetPropertyColor: PropertyColor?,
        state: inout GameState
    ) throws {
        guard case .action(let actionType) = card.type else { return }

        switch actionType {
        case .dealSnatcher:
            try resolveDealSnatcher(playerIndex: playerIndex, targetIndex: targetPlayerIndex, state: &state, card: card)
        case .noDeal:
            resolveNoDeal(card: card, playerIndex: playerIndex, state: &state)
        case .quickGrab:
            try resolveQuickGrab(playerIndex: playerIndex, targetIndex: targetPlayerIndex, targetColor: targetPropertyColor, state: &state, card: card)
        case .swapIt:
            try resolveSwapIt(playerIndex: playerIndex, targetIndex: targetPlayerIndex, state: &state, card: card)
        case .collectNow:
            resolveCollectNow(playerIndex: playerIndex, targetIndex: targetPlayerIndex, state: &state, card: card)
        case .bigSpender:
            resolveBigSpender(playerIndex: playerIndex, state: &state, card: card)
        case .dealForward:
            resolveDealForward(playerIndex: playerIndex, state: &state)
        case .doubleUp:
            resolveDoubleUp(playerIndex: playerIndex, state: &state)
        case .cornerStore:
            try resolveCornerStore(playerIndex: playerIndex, targetColor: targetPropertyColor, state: &state, card: card)
        case .apartmentBuilding:
            try resolveApartmentBuilding(playerIndex: playerIndex, targetColor: targetPropertyColor, state: &state, card: card)
        }
    }

    // MARK: - Deal Snatcher (steal complete set — triggers No Deal! window)

    private static func resolveDealSnatcher(
        playerIndex: Int,
        targetIndex: Int?,
        state: inout GameState,
        card: Card
    ) throws {
        guard let targetIndex = targetIndex else {
            // Should not happen — pre-action picker flow always provides a target.
            // Log and bail rather than using the attacker's own index as a placeholder.
            GameLogger.shared.warn("[ActionResolver] resolveDealSnatcher called with no targetIndex — aborting")
            throw ActionResolverError.invalidTarget
        }

        let target = state.players[targetIndex]
        let completeSets = target.properties.filter { $0.value.isComplete }
        guard !completeSets.isEmpty else { throw ActionResolverError.noCompleteSet }

        // Trigger No Deal! response window
        state.phase = .awaitingResponse(
            targetPlayerIndex: targetIndex,
            actionCard: card,
            attackerIndex: playerIndex
        )
    }

    /// Execute the actual steal after No Deal! window passes
    static func executeDealSnatcher(
        attackerIndex: Int,
        targetIndex: Int,
        color: PropertyColor,
        state: inout GameState
    ) {
        guard let targetSet = state.players[targetIndex].properties[color],
              targetSet.isComplete else { return }

        // Move entire set to attacker
        state.players[targetIndex].properties.removeValue(forKey: color)

        if state.players[attackerIndex].properties[color] == nil {
            state.players[attackerIndex].properties[color] = PropertySet(color: color, properties: [])
        }
        for card in targetSet.properties {
            state.players[attackerIndex].properties[color]?.addProperty(card)
        }
        // Transfer improvements
        if targetSet.hasCornerStore {
            state.players[attackerIndex].properties[color]?.hasCornerStore = true
        }
        if targetSet.hasApartmentBuilding {
            state.players[attackerIndex].properties[color]?.hasApartmentBuilding = true
        }
        GameLogger.shared.event("[\(state.players[attackerIndex].name)] stole complete \(color.displayName) set (\(targetSet.properties.count) cards\(targetSet.hasCornerStore ? " + CornerStore" : "")\(targetSet.hasApartmentBuilding ? " + ApartmentBuilding" : "")) from \(state.players[targetIndex].name)")
    }

    // MARK: - No Deal! (cancel action)

    private static func resolveNoDeal(card: Card, playerIndex: Int, state: inout GameState) {
        // NoDeal is handled by the game engine's response logic, not here
        // This is called when a player plays No Deal! proactively (shouldn't happen normally)
        // In practice, the engine intercepts No Deal! during awaitingResponse
    }

    // MARK: - Quick Grab (steal one property from incomplete set)

    private static func resolveQuickGrab(
        playerIndex: Int,
        targetIndex: Int?,
        targetColor: PropertyColor?,
        state: inout GameState,
        card: Card
    ) throws {
        guard let targetIndex = targetIndex else {
            GameLogger.shared.warn("[ActionResolver] resolveQuickGrab called with no targetIndex — aborting")
            throw ActionResolverError.invalidTarget
        }

        let target = state.players[targetIndex]
        let incompleteSets = target.properties.filter { !$0.value.isComplete && !$0.value.properties.isEmpty }
        guard !incompleteSets.isEmpty else { throw ActionResolverError.noIncompleteSet }

        // Trigger No Deal! window
        state.phase = .awaitingResponse(
            targetPlayerIndex: targetIndex,
            actionCard: card,
            attackerIndex: playerIndex
        )
    }

    static func executeQuickGrab(
        attackerIndex: Int,
        targetIndex: Int,
        cardId: UUID,
        state: inout GameState
    ) {
        guard let (stolenCard, fromColor) = state.players[targetIndex].removeProperty(id: cardId) else { return }

        // Attacker gets the property — put in same color set
        state.players[attackerIndex].placeProperty(stolenCard, in: fromColor)
        GameLogger.shared.event("[\(state.players[attackerIndex].name)] Quick Grab stole '\(stolenCard.name)' (\(fromColor.displayName)) from \(state.players[targetIndex].name)")
    }

    // MARK: - Swap It (trade properties)

    private static func resolveSwapIt(
        playerIndex: Int,
        targetIndex: Int?,
        state: inout GameState,
        card: Card
    ) throws {
        guard let tIdx = targetIndex else {
            state.phase = .awaitingPropertyChoice(
                chooserIndex: playerIndex,
                purpose: .swapIt(targetPlayerIndex: playerIndex)
            )
            return
        }
        // Both the target and attacker must have at least one property in an incomplete set
        let targetIncomplete = state.players[tIdx].properties.filter { !$0.value.isComplete && !$0.value.properties.isEmpty }
        guard !targetIncomplete.isEmpty else {
            GameLogger.shared.warn("[ActionResolver] resolveSwapIt — target has no incomplete sets")
            throw ActionResolverError.noIncompleteSet
        }
        let attackerIncomplete = state.players[playerIndex].properties.filter { !$0.value.isComplete && !$0.value.properties.isEmpty }
        guard !attackerIncomplete.isEmpty else {
            GameLogger.shared.warn("[ActionResolver] resolveSwapIt — attacker has no incomplete sets to give")
            throw ActionResolverError.noIncompleteSet
        }
        state.phase = .awaitingResponse(
            targetPlayerIndex: tIdx,
            actionCard: card,
            attackerIndex: playerIndex
        )
    }

    static func executeSwapIt(
        attackerIndex: Int,
        targetIndex: Int,
        attackerCardId: UUID,
        targetCardId: UUID,
        state: inout GameState
    ) {
        guard let (attackerCard, attackerColor) = state.players[attackerIndex].removeProperty(id: attackerCardId),
              let (targetCard, targetColor) = state.players[targetIndex].removeProperty(id: targetCardId) else { return }

        state.players[attackerIndex].placeProperty(targetCard, in: targetColor)
        state.players[targetIndex].placeProperty(attackerCard, in: attackerColor)
        GameLogger.shared.event("[\(state.players[attackerIndex].name)] Swap It — gave '\(attackerCard.name)' (\(attackerColor.displayName)), took '\(targetCard.name)' (\(targetColor.displayName)) from \(state.players[targetIndex].name)")
    }

    // MARK: - Collect Now (one player pays $5M)

    private static func resolveCollectNow(
        playerIndex: Int,
        targetIndex: Int?,
        state: inout GameState,
        card: Card
    ) {
        guard let targetIndex = targetIndex else {
            state.phase = .awaitingResponse(
                targetPlayerIndex: state.nextPlayerIndex(after: playerIndex),
                actionCard: card,
                attackerIndex: playerIndex
            )
            return
        }
        state.phase = .awaitingResponse(
            targetPlayerIndex: targetIndex,
            actionCard: card,
            attackerIndex: playerIndex
        )
    }

    static func executeCollectNow(
        creditorIndex: Int,
        debtorIndex: Int,
        state: inout GameState
    ) {
        GameLogger.shared.event("[\(state.players[creditorIndex].name)] Collect Now — \(state.players[debtorIndex].name) must pay $5M")
        PaymentResolver.resolvePayment(
            state: &state,
            debtorIndex: debtorIndex,
            creditorIndex: creditorIndex,
            amount: 5
        )
    }

    // MARK: - Big Spender (all players pay $2M)

    private static func resolveBigSpender(playerIndex: Int, state: inout GameState, card: Card) {
        // Every non-attacker gets their own NoDeal window in turn order.
        // The first target enters awaitingResponse immediately; the rest go into the queue.
        let targets = state.otherPlayerIndices()
        guard !targets.isEmpty else { return }
        state.pendingResponsePlayerIndices = Array(targets.dropFirst())
        state.phase = .awaitingResponse(
            targetPlayerIndex: targets[0],
            actionCard: card,
            attackerIndex: playerIndex
        )
    }

    // MARK: - Deal Forward (draw 2 extra cards)

    private static func resolveDealForward(playerIndex: Int, state: inout GameState) {
        let drawn = drawCards(count: 2, from: &state)
        state.players[playerIndex].addToHand(drawn)
        GameLogger.shared.event("[\(state.players[playerIndex].name)] Deal Forward — drew \(drawn.count) cards (hand: \(state.players[playerIndex].hand.count))")
        // Does NOT count as "playing" a card slot — stays in playing phase
    }

    // MARK: - Double Up (double rent this turn)

    private static func resolveDoubleUp(playerIndex: Int, state: inout GameState) {
        state.pendingDoubleUp.isActive = true
        GameLogger.shared.event("[\(state.players[playerIndex].name)] Double Up activated — next rent is doubled")
    }

    // MARK: - Corner Store (improvement on complete set)

    private static func resolveCornerStore(
        playerIndex: Int,
        targetColor: PropertyColor?,
        state: inout GameState,
        card: Card
    ) throws {
        // Find a complete set without a corner store
        let eligible = state.players[playerIndex].properties.filter { $0.value.canAddCornerStore }
        guard !eligible.isEmpty else { throw ActionResolverError.cannotAddImprovement }

        if let color = targetColor, var set = state.players[playerIndex].properties[color] {
            guard set.canAddCornerStore else { throw ActionResolverError.cannotAddImprovement }
            set.hasCornerStore = true
            state.players[playerIndex].properties[color] = set
            GameLogger.shared.event("[\(state.players[playerIndex].name)] added Corner Store to \(color.displayName)")
        } else if eligible.count == 1, let color = eligible.keys.first {
            state.players[playerIndex].properties[color]?.hasCornerStore = true
            GameLogger.shared.event("[\(state.players[playerIndex].name)] added Corner Store to \(color.displayName) (only eligible set)")
        } else {
            // Multiple eligible sets — need UI to pick
            state.phase = .awaitingPropertyChoice(
                chooserIndex: playerIndex,
                purpose: .payWithProperty(creditorIndex: playerIndex, amount: 0) // reused as "pick set"
            )
        }
    }

    // MARK: - Apartment Building (improvement after Corner Store)

    private static func resolveApartmentBuilding(
        playerIndex: Int,
        targetColor: PropertyColor?,
        state: inout GameState,
        card: Card
    ) throws {
        let eligible = state.players[playerIndex].properties.filter { $0.value.canAddApartmentBuilding }
        guard !eligible.isEmpty else { throw ActionResolverError.cannotAddImprovement }

        if let color = targetColor, var set = state.players[playerIndex].properties[color] {
            guard set.canAddApartmentBuilding else { throw ActionResolverError.cannotAddImprovement }
            set.hasApartmentBuilding = true
            state.players[playerIndex].properties[color] = set
            GameLogger.shared.event("[\(state.players[playerIndex].name)] added Apartment Building to \(color.displayName)")
        } else if eligible.count == 1, let color = eligible.keys.first {
            state.players[playerIndex].properties[color]?.hasApartmentBuilding = true
            GameLogger.shared.event("[\(state.players[playerIndex].name)] added Apartment Building to \(color.displayName) (only eligible set)")
        }
    }

    // MARK: - Rent Resolution

    static func resolveRent(
        card: Card,
        playerIndex: Int,
        targetPlayerIndex: Int?,    // nil = charge all (two-color); non-nil = charge one (wild)
        chosenColor: PropertyColor?,
        multiplier: Int = 1,
        state: inout GameState
    ) {
        let rentAmount: Int = {
            guard let color = chosenColor,
                  let set = state.players[playerIndex].properties[color] else { return 0 }
            return set.currentRent * multiplier
        }()

        guard rentAmount > 0 else {
            GameLogger.shared.warn("[\(state.players[playerIndex].name)] rent is $0 for \(chosenColor?.displayName ?? "?") — skipped (no properties in that color?)")
            return
        }
        GameLogger.shared.event("[\(state.players[playerIndex].name)] charges $\(rentAmount)M rent for \(chosenColor?.displayName ?? "?") ×\(multiplier)")

        // Store rent info so the NoDeal response chain can access it later.
        state.pendingRentAmount = rentAmount
        state.pendingRentColor = chosenColor

        // Every targeted player gets their own NoDeal window before paying.
        switch card.type {
        case .rent:
            // Collect Dues — targets all other players.
            let targets = state.otherPlayerIndices()
            guard !targets.isEmpty else { return }
            state.pendingResponsePlayerIndices = Array(targets.dropFirst())
            state.phase = .awaitingResponse(
                targetPlayerIndex: targets[0],
                actionCard: card,
                attackerIndex: playerIndex
            )
            GameLogger.shared.event("[\(state.players[playerIndex].name)] Collect Dues — queuing NoDeal window for \(targets.count) player(s) at $\(rentAmount)M each")

        case .wildRent:
            // Rent Blitz! — single target chosen by attacker.
            guard let targetIdx = targetPlayerIndex else { return }
            state.pendingResponsePlayerIndices = []
            state.phase = .awaitingResponse(
                targetPlayerIndex: targetIdx,
                actionCard: card,
                attackerIndex: playerIndex
            )
            GameLogger.shared.event("[\(state.players[playerIndex].name)] Rent Blitz! — NoDeal window for \(state.players[targetIdx].name) at $\(rentAmount)M")

        default: break
        }
    }

    // MARK: - Helpers

    static func drawCards(count: Int, from state: inout GameState) -> [Card] {
        var drawn: [Card] = []
        for _ in 0..<count {
            if state.deck.isEmpty {
                // Reshuffle discard pile
                state.deck = state.discardPile.shuffled()
                state.discardPile = []
            }
            if let card = state.deck.first {
                state.deck.removeFirst()
                drawn.append(card)
            }
        }
        return drawn
    }
}
