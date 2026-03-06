import Foundation

// MARK: - Game Engine
// Single source of truth for game state mutations.
// The ViewModel observes this and exposes state to SwiftUI.

@Observable
final class GameEngine {

    internal(set) var state: GameState

    // Callbacks for UI events that need user input
    var onNeedPropertyChoice: ((PropertyChoicePurpose) -> Void)?
    var onNeedWildColorChoice: ((UUID, [PropertyColor]) -> Void)?
    var onGameOver: ((Int) -> Void)?
    var onError: ((String) -> Void)?

    private let log = GameLogger.shared

    init(state: GameState) {
        self.state = state
    }

    // MARK: - Turn Start

    func startTurn() {
        guard case .drawing = state.phase else { return }
        let playerIndex = state.currentPlayerIndex
        let drawCount = state.players[playerIndex].hand.isEmpty ? 5 : 2
        let drawn = ActionResolver.drawCards(count: drawCount, from: &state)
        state.players[playerIndex].addToHand(drawn)
        trackCardsDraw(drawn, for: playerIndex)
        state.phase = .playing
        log.event("[\(state.players[playerIndex].name)] drew \(drawn.count) cards (hand: \(state.players[playerIndex].hand.count)) — turn \(state.turnNumber)")
        log.addActivity("\(state.players[playerIndex].name) drew \(drawn.count) cards")
    }

    /// Record drawn cards in per-player stats (money/property/action/rent).
    func trackCardsDraw(_ cards: [Card], for playerIndex: Int) {
        guard playerIndex < state.playerStats.count else { return }
        for card in cards {
            switch card.type {
            case .money:                   state.playerStats[playerIndex].moneyCardsDrawn += 1
            case .property, .wildProperty: state.playerStats[playerIndex].propertyCardsDrawn += 1
            case .action:                  state.playerStats[playerIndex].actionCardsDrawn += 1
            case .rent, .wildRent:         state.playerStats[playerIndex].rentCardsDrawn += 1
            }
        }
    }

    // MARK: - Play Card

    /// Play a card from the current player's hand.
    /// `destination`: .bank, .property(color), .action(targetIndex?, targetColor?)
    func playCard(
        cardId: UUID,
        as destination: CardDestination,
        targetPlayerIndex: Int? = nil,
        targetPropertyColor: PropertyColor? = nil,
        wildColor: PropertyColor? = nil
    ) {
        guard state.canPlayCard else { return }
        let playerIndex = state.currentPlayerIndex
        guard let card = state.players[playerIndex].removeFromHand(id: cardId) else { return }

        state.cardsPlayedThisTurn += 1

        let player = state.players[playerIndex]
        log.event("[\(player.name)] plays '\(card.name)' → \(destination) (card \(state.cardsPlayedThisTurn)/3)")

        switch destination {
        case .bank:
            state.players[playerIndex].addToBank(card)
            state.discardPile.append(card)
            state.pendingDoubleUp.rentCardPlayed = false
            let bankNow = state.players[playerIndex].bankTotal
            if playerIndex < state.playerStats.count, bankNow > state.playerStats[playerIndex].peakBankValue {
                state.playerStats[playerIndex].peakBankValue = bankNow
            }
            log.event("[\(player.name)] banked '\(card.name)' ($\(card.monetaryValue)M) — bank total now $\(bankNow)M")
            log.addActivity("\(player.name) banked \(card.name) ($\(card.monetaryValue)M)")
            checkWinAndAdvance()

        case .property(let color):
            state.players[playerIndex].placeProperty(card, in: color)
            let setCount = state.players[playerIndex].properties[color]?.properties.count ?? 0
            let setSize = color.setSize
            log.event("[\(player.name)] placed '\(card.name)' in \(color.displayName) [\(setCount)/\(setSize)]")
            let dot: String = {
                if case .wildProperty = card.type { return "🌈" }
                return color.colorDot
            }()
            log.addActivity("\(player.name) → \(dot)")
            checkWinAndAdvance()

        case .action:
            state.discardPile.append(card)
            // Steal and improvement actions log their own descriptive entries; skip generic "played" for them
            let skipGenericActivity: Bool = {
                if case .action(let t) = card.type {
                    return t == .dealSnatcher || t == .quickGrab || t == .swapIt
                        || t == .cornerStore || t == .apartmentBuilding
                }
                return false
            }()
            if !skipGenericActivity {
                log.addActivity("\(player.name) played \(card.name)")
            }
            do {
                try ActionResolver.resolve(
                    card: card,
                    playerIndex: playerIndex,
                    targetPlayerIndex: targetPlayerIndex,
                    targetPropertyColor: targetPropertyColor,
                    state: &state
                )
                // If action didn't set a new phase, check win and continue
                if case .playing = state.phase {
                    checkWinAndAdvance()
                }
            } catch let actionError as ActionResolverError {
                // Revert card played count on error and surface to UI
                state.cardsPlayedThisTurn -= 1
                state.players[playerIndex].addToHand(card)
                state.discardPile.removeLast()
                let msg = actionError.errorDescription ?? "Cannot play that card."
                log.warn("[\(player.name)] action '\(card.name)' failed: \(msg)")
                onError?(msg)
            } catch {
                state.cardsPlayedThisTurn -= 1
                state.players[playerIndex].addToHand(card)
                state.discardPile.removeLast()
                log.warn("[\(player.name)] action '\(card.name)' failed: \(error)")
            }

        case .rent(let color):
            state.discardPile.append(card)
            let multiplier = state.pendingDoubleUp.isActive ? 2 : 1
            state.pendingDoubleUp.isActive = false
            let colorName = color?.colorDot ?? "🌈"
            let targetName = targetPlayerIndex.map { state.players[$0].name } ?? "all"
            log.event("[\(player.name)] plays rent '\(card.name)' color=\(colorName) ×\(multiplier) → \(targetName)")
            log.addActivity("\(player.name) collecting rent on \(colorName)\(multiplier > 1 ? " ×2" : "")")
            ActionResolver.resolveRent(
                card: card,
                playerIndex: playerIndex,
                targetPlayerIndex: targetPlayerIndex,
                chosenColor: color,
                multiplier: multiplier,
                state: &state
            )
            if case .playing = state.phase {
                checkWinAndAdvance()
            }
        }
    }

    // MARK: - No Deal! Response

    /// Called when the target plays a No Deal! during awaitingResponse.
    /// Card must be a No Deal! card in target's hand.
    func playNoDeal(cardId: UUID, playerIndex: Int) {
        guard case .awaitingResponse(let targetIdx, let actionCard, let attackerIndex) = state.phase,
              targetIdx == playerIndex else { return }
        guard let card = state.players[playerIndex].removeFromHand(id: cardId),
              card.isNoDeal else { return }

        state.discardPile.append(card)
        if playerIndex < state.playerStats.count {
            state.playerStats[playerIndex].noDealPlayed += 1
        }
        log.event("[\(state.players[playerIndex].name)] played No Deal! against '\(actionCard.name)'")

        // For multi-target actions NoDeal only protects THIS player — advance the queue so
        // remaining players still get their own response window and pay if they don't block.
        switch actionCard.type {
        case .action(.bigSpender), .rent, .wildRent:
            // Skip payment for this player; continue to next in queue (or process payments).
            state.advanceResponseQueue(actionCard: actionCard, attackerIndex: attackerIndex)
        default:
            // Single-target action: cancel the entire action.
            state.pendingResponsePlayerIndices = []
            state.pendingRentAmount = 0
            state.pendingRentColor = nil
            state.phase = .playing
        }
    }

    /// Called when the target does NOT play No Deal! (accepts the action)
    func acceptAction() {
        guard case .awaitingResponse(let targetIdx, let actionCard, let attackerIndex) = state.phase else { return }
        log.event("[\(state.players[targetIdx].name)] accepted '\(actionCard.name)' from \(state.players[attackerIndex].name)")

        switch actionCard.type {
        case .action(.bigSpender):
            // Queue payment for this player and advance to the next response window.
            if state.players[targetIdx].isHuman {
                state.pendingPayments.append(
                    PendingPayment(debtorIndex: targetIdx, creditorIndex: attackerIndex,
                                   amount: 2, reason: .bigSpender)
                )
            } else {
                PaymentResolver.resolvePayment(state: &state, debtorIndex: targetIdx,
                                               creditorIndex: attackerIndex, amount: 2)
            }
            state.advanceResponseQueue(actionCard: actionCard, attackerIndex: attackerIndex)
            checkWinAndAdvance()

        case .rent, .wildRent:
            // Queue rent payment for this player and advance to the next response window.
            let amount = state.pendingRentAmount
            let reason: PaymentReason = .rent(state.pendingRentColor ?? .blueChip)
            if state.players[targetIdx].isHuman {
                state.pendingPayments.append(
                    PendingPayment(debtorIndex: targetIdx, creditorIndex: attackerIndex,
                                   amount: amount, reason: reason)
                )
            } else {
                PaymentResolver.resolvePayment(state: &state, debtorIndex: targetIdx,
                                               creditorIndex: attackerIndex, amount: amount)
            }
            state.advanceResponseQueue(actionCard: actionCard, attackerIndex: attackerIndex)
            checkWinAndAdvance()

        default:
            // Single-target action card: execute immediately.
            executeQueuedAction(actionCard: actionCard, attackerIndex: attackerIndex)
            if case .awaitingResponse = state.phase {} else {
                checkWinAndAdvance()
            }
        }
    }

    private func executeQueuedAction(actionCard: Card, attackerIndex: Int) {
        guard case .action(let actionType) = actionCard.type else { return }
        guard case .awaitingResponse(let targetIdx, _, _) = state.phase else { return }

        switch actionType {
        case .dealSnatcher:
            // Pre-selection takes priority (human attacker in both solo and multiplayer).
            // CPU attacker path only fires when no pre-selection was made.
            if let preColor = state.pendingSteal.color {
                // Human attacker pre-selected a color before playing the card
                log.event("[\(state.players[attackerIndex].name)] Deal Snatcher executes with pre-selected \(preColor.displayName)")
                ActionResolver.executeDealSnatcher(attackerIndex: attackerIndex, targetIndex: targetIdx, color: preColor, state: &state)
                state.pendingSteal = PendingStealPreSelection()
                state.phase = .playing
                log.addActivity("\(state.players[attackerIndex].name) snatched \(preColor.colorDot) from \(state.players[targetIdx].name)")
            } else if !state.players[attackerIndex].isHuman {
                // CPU attacker — steal the target's highest-rent complete set automatically
                let completeSets = state.players[targetIdx].properties.filter { $0.value.isComplete }
                if let (color, _) = completeSets.max(by: { $0.value.currentRent < $1.value.currentRent }) {
                    log.event("[\(state.players[attackerIndex].name)] Deal Snatcher auto-selects \(color.displayName) set from \(state.players[targetIdx].name)")
                    ActionResolver.executeDealSnatcher(
                        attackerIndex: attackerIndex,
                        targetIndex: targetIdx,
                        color: color,
                        state: &state
                    )
                    log.addActivity("\(state.players[attackerIndex].name) snatched \(color.colorDot) from \(state.players[targetIdx].name)")
                } else {
                    log.warn("[\(state.players[attackerIndex].name)] Deal Snatcher — no complete sets to steal (should have been caught earlier)")
                }
                state.phase = .playing
            } else {
                // Fallback: show picker (legacy path)
                state.phase = .awaitingPropertyChoice(
                    chooserIndex: attackerIndex,
                    purpose: .dealSnatcher(targetPlayerIndex: targetIdx)
                )
            }

        case .quickGrab:
            // Pre-selection takes priority (human attacker in both solo and multiplayer).
            // CPU attacker path only fires when no pre-selection was made.
            if let preCardId = state.pendingSteal.cardId {
                // Human attacker pre-selected a card before playing
                let dot = propertyColor(of: preCardId, for: targetIdx)?.colorDot ?? "?"
                log.event("[\(state.players[attackerIndex].name)] Quick Grab executes with pre-selected card id=\(preCardId)")
                ActionResolver.executeQuickGrab(attackerIndex: attackerIndex, targetIndex: targetIdx, cardId: preCardId, state: &state)
                state.pendingSteal = PendingStealPreSelection()
                state.phase = .playing
                log.addActivity("\(state.players[attackerIndex].name) grabbed \(dot) from \(state.players[targetIdx].name)")
            } else if !state.players[attackerIndex].isHuman {
                // CPU attacker — auto-steal best card from target's incomplete sets
                let stealable = state.players[targetIdx].properties.values
                    .filter { !$0.isComplete }
                    .flatMap { $0.properties }
                if let best = stealable.max(by: { $0.monetaryValue < $1.monetaryValue }) {
                    let dot = propertyColor(of: best.id, for: targetIdx)?.colorDot ?? "?"
                    log.event("[\(state.players[attackerIndex].name)] Quick Grab auto-selects '\(best.name)' from \(state.players[targetIdx].name)")
                    ActionResolver.executeQuickGrab(
                        attackerIndex: attackerIndex,
                        targetIndex: targetIdx,
                        cardId: best.id,
                        state: &state
                    )
                    log.addActivity("\(state.players[attackerIndex].name) grabbed \(dot) from \(state.players[targetIdx].name)")
                } else {
                    log.warn("[\(state.players[attackerIndex].name)] Quick Grab — no stealable properties (should have been caught earlier)")
                }
                state.phase = .playing
            } else {
                // Fallback: show picker
                state.phase = .awaitingPropertyChoice(
                    chooserIndex: attackerIndex,
                    purpose: .quickGrab(targetPlayerIndex: targetIdx)
                )
            }

        case .swapIt:
            // Pre-selection takes priority (human attacker in both solo and multiplayer).
            // CPU attacker path only fires when no pre-selection was made.
            if let myCardId = state.pendingSteal.cardId, let theirCardId = state.pendingSteal.secondaryCardId {
                // Human attacker pre-selected both cards
                let myDot = propertyColor(of: myCardId, for: attackerIndex)?.colorDot ?? "?"
                let theirDot = propertyColor(of: theirCardId, for: targetIdx)?.colorDot ?? "?"
                log.event("[\(state.players[attackerIndex].name)] Swap It executes with pre-selected cards")
                ActionResolver.executeSwapIt(attackerIndex: attackerIndex, targetIndex: targetIdx, attackerCardId: myCardId, targetCardId: theirCardId, state: &state)
                state.pendingSteal = PendingStealPreSelection()
                state.phase = .playing
                log.addActivity("\(state.players[attackerIndex].name) swapped \(myDot) ↔ \(theirDot) with \(state.players[targetIdx].name)")
            } else if !state.players[attackerIndex].isHuman {
                // CPU attacker — auto-trade worst of own incomplete set for best of target's incomplete set
                let targetProps = state.players[targetIdx].properties.values.filter { !$0.isComplete }.flatMap { $0.properties }
                let attackerProps = state.players[attackerIndex].properties.values.filter { !$0.isComplete }.flatMap { $0.properties }
                let valueDesc: (Card, Card) -> Bool = {
                    $0.monetaryValue != $1.monetaryValue
                        ? $0.monetaryValue < $1.monetaryValue
                        : $0.id.uuidString < $1.id.uuidString
                }
                if let targetCard = targetProps.max(by: valueDesc),
                   let attackerCard = attackerProps.min(by: valueDesc) {
                    let myDot = propertyColor(of: attackerCard.id, for: attackerIndex)?.colorDot ?? "?"
                    let theirDot = propertyColor(of: targetCard.id, for: targetIdx)?.colorDot ?? "?"
                    log.event("[\(state.players[attackerIndex].name)] Swap It auto-selects '\(targetCard.name)' ↔ '\(attackerCard.name)' with \(state.players[targetIdx].name)")
                    ActionResolver.executeSwapIt(
                        attackerIndex: attackerIndex,
                        targetIndex: targetIdx,
                        attackerCardId: attackerCard.id,
                        targetCardId: targetCard.id,
                        state: &state
                    )
                    log.addActivity("\(state.players[attackerIndex].name) swapped \(myDot) ↔ \(theirDot) with \(state.players[targetIdx].name)")
                } else {
                    log.warn("[\(state.players[attackerIndex].name)] Swap It — couldn't find cards to swap")
                }
                state.phase = .playing
            } else {
                // Fallback: show picker
                state.phase = .awaitingPropertyChoice(
                    chooserIndex: attackerIndex,
                    purpose: .swapIt(targetPlayerIndex: targetIdx)
                )
            }

        case .collectNow:
            // Human debtors get a payment choice; CPU debtors pay immediately
            if state.players[targetIdx].isHuman {
                state.phase = .awaitingPayment(
                    debtorIndex: targetIdx,
                    creditorIndex: attackerIndex,
                    amount: 5,
                    reason: .collectNow
                )
            } else {
                ActionResolver.executeCollectNow(
                    creditorIndex: attackerIndex,
                    debtorIndex: targetIdx,
                    state: &state
                )
                state.phase = .playing
            }

        default:
            state.phase = .playing
        }
    }

    // MARK: - Property Choice Resolution

    /// Returns the PropertyColor a given card belongs to in a player's properties.
    private func propertyColor(of cardId: UUID, for playerIndex: Int) -> PropertyColor? {
        for (color, set) in state.players[playerIndex].properties {
            if set.properties.contains(where: { $0.id == cardId }) { return color }
        }
        return nil
    }

    func resolvePropertyChoice(
        purpose: PropertyChoicePurpose,
        selectedCardId: UUID? = nil,
        selectedColor: PropertyColor? = nil,
        secondaryCardId: UUID? = nil
    ) {
        let chooser = state.currentPlayerIndex
        switch purpose {
        case .dealSnatcher(let targetIdx):
            if let color = selectedColor {
                log.event("[\(state.players[chooser].name)] Deal Snatcher chose to steal \(color.displayName) set from \(state.players[targetIdx].name)")
                ActionResolver.executeDealSnatcher(
                    attackerIndex: chooser,
                    targetIndex: targetIdx,
                    color: color,
                    state: &state
                )
                log.addActivity("\(state.players[chooser].name) snatched \(color.colorDot) from \(state.players[targetIdx].name)")
            } else {
                log.event("[\(state.players[chooser].name)] Deal Snatcher cancelled (no color selected)")
            }
            state.phase = .playing

        case .quickGrab(let targetIdx):
            if let cardId = selectedCardId {
                log.event("[\(state.players[chooser].name)] Quick Grab chose card id=\(cardId) from \(state.players[targetIdx].name)")
                let dot = propertyColor(of: cardId, for: targetIdx)?.colorDot ?? "?"
                ActionResolver.executeQuickGrab(
                    attackerIndex: chooser,
                    targetIndex: targetIdx,
                    cardId: cardId,
                    state: &state
                )
                log.addActivity("\(state.players[chooser].name) grabbed \(dot) from \(state.players[targetIdx].name)")
            } else {
                log.event("[\(state.players[chooser].name)] Quick Grab cancelled (no card selected)")
            }
            state.phase = .playing

        case .swapIt(let targetIdx):
            if let myCardId = selectedCardId, let theirCardId = secondaryCardId {
                log.event("[\(state.players[chooser].name)] Swap It chose my=\(myCardId) ↔ their=\(theirCardId) with \(state.players[targetIdx].name)")
                let myDot = propertyColor(of: myCardId, for: chooser)?.colorDot ?? "?"
                let theirDot = propertyColor(of: theirCardId, for: targetIdx)?.colorDot ?? "?"
                ActionResolver.executeSwapIt(
                    attackerIndex: chooser,
                    targetIndex: targetIdx,
                    attackerCardId: myCardId,
                    targetCardId: theirCardId,
                    state: &state
                )
                log.addActivity("\(state.players[chooser].name) swapped \(myDot) ↔ \(theirDot) with \(state.players[targetIdx].name)")
            } else {
                log.event("[\(state.players[chooser].name)] Swap It cancelled (cards not selected)")
            }
            state.phase = .playing

        case .quickGrabVictim(let attackerIdx):
            // Human victim chose which of their properties the CPU steals
            guard case .awaitingPropertyChoice(let victimIdx, _) = state.phase else { return }
            if let cardId = selectedCardId {
                log.event("[\(state.players[victimIdx].name)] Quick Grab victim chose to give card id=\(cardId) to \(state.players[attackerIdx].name)")
                let dot = propertyColor(of: cardId, for: victimIdx)?.colorDot ?? "?"
                ActionResolver.executeQuickGrab(
                    attackerIndex: attackerIdx,
                    targetIndex: victimIdx,
                    cardId: cardId,
                    state: &state
                )
                log.addActivity("\(state.players[attackerIdx].name) grabbed \(dot) from \(state.players[victimIdx].name)")
            } else {
                log.event("[\(state.players[victimIdx].name)] Quick Grab victim made no selection — auto-resolving")
            }
            state.phase = .playing

        case .dealSnatcherVictim(let attackerIdx):
            // Human victim chose which complete set the CPU steals
            guard case .awaitingPropertyChoice(let victimIdx, _) = state.phase else { return }
            if let color = selectedColor {
                log.event("[\(state.players[victimIdx].name)] Deal Snatcher victim chose to give \(color.displayName) set to \(state.players[attackerIdx].name)")
                ActionResolver.executeDealSnatcher(
                    attackerIndex: attackerIdx,
                    targetIndex: victimIdx,
                    color: color,
                    state: &state
                )
                log.addActivity("\(state.players[attackerIdx].name) snatched \(color.colorDot) from \(state.players[victimIdx].name)")
            } else {
                log.event("[\(state.players[victimIdx].name)] Deal Snatcher victim made no selection — auto-resolving")
            }
            state.phase = .playing

        case .swapItVictim(let attackerIdx):
            // Human victim chose: selectedCardId = their card, secondaryCardId = attacker's card they take
            guard case .awaitingPropertyChoice(let victimIdx, _) = state.phase else { return }
            if let victimCardId = selectedCardId, let attackerCardId = secondaryCardId {
                log.event("[\(state.players[victimIdx].name)] Swap It victim chose their=\(victimCardId) ↔ attacker=\(attackerCardId)")
                let theirDot = propertyColor(of: victimCardId, for: victimIdx)?.colorDot ?? "?"
                let myDot = propertyColor(of: attackerCardId, for: attackerIdx)?.colorDot ?? "?"
                ActionResolver.executeSwapIt(
                    attackerIndex: attackerIdx,
                    targetIndex: victimIdx,
                    attackerCardId: attackerCardId,
                    targetCardId: victimCardId,
                    state: &state
                )
                log.addActivity("\(state.players[attackerIdx].name) swapped \(myDot) ↔ \(theirDot) with \(state.players[victimIdx].name)")
            } else {
                log.event("[\(state.players[victimIdx].name)] Swap It victim made no selection — auto-resolving")
            }
            state.phase = .playing

        case .swapItTarget:
            state.phase = .playing

        case .payWithProperty(_, _):
            if let color = selectedColor {
                log.event("[\(state.players[chooser].name)] added Corner Store to \(color.displayName) via payWithProperty")
                state.players[chooser].properties[color]?.hasCornerStore = true
            }
            state.phase = .playing
        }
        checkWinAndAdvance()
    }

    // MARK: - Wild Card Reassignment (free action — no card cost)

    /// Move a wild property card from one color group to another.
    /// Free action: does NOT increment cardsPlayedThisTurn.
    func reassignWild(cardId: UUID, toColor: PropertyColor) {
        let playerIndex = state.currentPlayerIndex

        // Capture improvement state BEFORE removal — Player.removeProperty already clears
        // hasCornerStore/hasApartmentBuilding when the set becomes incomplete, so we must
        // snapshot them first to know whether compensation is owed.
        var savedCornerStore = false
        var savedApartmentBuilding = false
        for (_, set) in state.players[playerIndex].properties {
            if set.properties.contains(where: { $0.id == cardId }) {
                savedCornerStore = set.hasCornerStore
                savedApartmentBuilding = set.hasApartmentBuilding
                break
            }
        }

        // Remove first, then validate — restore if conditions aren't met
        guard let (card, fromColor) = state.players[playerIndex].removeProperty(id: cardId) else { return }
        guard case .wildProperty(let validColors) = card.type,
              validColors.isEmpty || validColors.contains(toColor) else {
            // Restore card to its original set
            state.players[playerIndex].placeProperty(card, in: fromColor)
            log.warn("[\(state.players[playerIndex].name)] reassignWild failed — '\(card.name)' cannot go in \(toColor.displayName), restored to \(fromColor.displayName)")
            return
        }
        // If source set is now incomplete, return improvement value to bank.
        // Improvements require a complete set; moving the wild breaks the set so they convert to cash.
        if let sourceSet = state.players[playerIndex].properties[fromColor], !sourceSet.isComplete {
            if savedCornerStore {
                let comp = Card(id: UUID(), type: .money(3), name: "Corner Store",
                                description: "Returned to bank", monetaryValue: 3,
                                assetKey: "card_cornerStore_1")
                state.players[playerIndex].bank.append(comp)
                log.event("[\(state.players[playerIndex].name)] Corner Store returned to bank ($3M) — \(fromColor.displayName) no longer complete")
                log.addActivity("\(state.players[playerIndex].name) Corner Store → bank ($3M)")
            }
            if savedApartmentBuilding {
                let comp = Card(id: UUID(), type: .money(3), name: "Apt. Building",
                                description: "Returned to bank", monetaryValue: 3,
                                assetKey: "card_apartmentBuilding_1")
                state.players[playerIndex].bank.append(comp)
                log.event("[\(state.players[playerIndex].name)] Apartment Building returned to bank ($3M) — \(fromColor.displayName) no longer complete")
                log.addActivity("\(state.players[playerIndex].name) Apt. Building → bank ($3M)")
            }
        }
        state.players[playerIndex].placeProperty(card, in: toColor)
        log.event("[\(state.players[playerIndex].name)] reassigned wild '\(card.name)' \(fromColor.displayName) → \(toColor.displayName)")
        // No cardsPlayedThisTurn increment — free action
        // Check win in case this completes a set
        checkWinAndAdvance()
    }

    // MARK: - Payment Resolution

    /// Human player manually pays by choosing specific cards.
    func executeHumanPayment(bankCardIds: [UUID], propertyCardIds: [UUID]) {
        guard case .awaitingPayment(let debtorIdx, let creditorIdx, _, _) = state.phase,
              state.players[debtorIdx].isHuman else { return }

        // Transfer selected bank cards
        for cardId in bankCardIds {
            if let idx = state.players[debtorIdx].bank.firstIndex(where: { $0.id == cardId }) {
                let card = state.players[debtorIdx].bank.remove(at: idx)
                state.players[creditorIdx].bank.append(card)
            }
        }
        // Transfer selected property cards to creditor's property area
        for cardId in propertyCardIds {
            if let (card, color) = state.players[debtorIdx].removeProperty(id: cardId) {
                state.players[creditorIdx].placeProperty(card, in: color)
            }
        }

        state.processNextPayment()
        checkWinAndAdvance()
    }

    /// Auto-resolve payment for a CPU debtor (or human with no assets).
    func resolveCPUPayment(debtorIndex: Int, creditorIndex: Int, amount: Int) {
        guard case .awaitingPayment(let d, let c, _, _) = state.phase,
              d == debtorIndex, c == creditorIndex else { return }
        PaymentResolver.resolvePayment(
            state: &state,
            debtorIndex: debtorIndex,
            creditorIndex: creditorIndex,
            amount: amount
        )
        state.processNextPayment()
        checkWinAndAdvance()
    }

    // MARK: - Wild Color Assignment

    func assignWildColor(cardId: UUID, color: PropertyColor) {
        guard state.canPlayCard else { return }
        let playerIndex = state.currentPlayerIndex
        guard let card = state.players[playerIndex].removeFromHand(id: cardId) else { return }

        state.players[playerIndex].placeProperty(card, in: color)
        state.cardsPlayedThisTurn += 1
        log.event("[\(state.players[playerIndex].name)] assigned wild '\(card.name)' → \(color.displayName)")
        log.addActivity("\(state.players[playerIndex].name) → 🌈")

        if case .awaitingWildColorChoice = state.phase {
            state.phase = .playing
        }
        checkWinAndAdvance()
    }

    // MARK: - End Turn

    func endTurn() {
        guard case .playing = state.phase else { return }
        let playerIndex = state.currentPlayerIndex
        let handCount = state.players[playerIndex].hand.count
        if handCount > 7 {
            state.phase = .discarding(playerIndex: playerIndex)
        } else {
            advanceToNextTurn()
        }
    }

    // MARK: - Discard

    /// Cancel discard and return to playing so the human can play more cards first.
    /// Only valid when the discarding player has used fewer than 3 actions this turn.
    func cancelDiscard() {
        guard case .discarding(let idx) = state.phase,
              state.players[idx].isHuman,
              state.cardsPlayedThisTurn < 3 else { return }
        log.event("[\(state.players[idx].name)] cancelled discard — back to playing (\(state.cardsPlayedThisTurn)/3 cards)")
        state.phase = .playing
    }

    func discard(cardId: UUID) {
        guard case .discarding(let playerIndex) = state.phase else { return }
        guard let card = state.players[playerIndex].removeFromHand(id: cardId) else { return }
        state.discardPile.append(card)
        if state.players[playerIndex].hand.count <= 7 {
            advanceToNextTurn()
        }
    }

    // MARK: - Private Helpers

    private func checkWinAndAdvance() {
        if let winner = WinChecker.check(state) {
            state.phase = .gameOver(winnerIndex: winner)
            onGameOver?(winner)
        }
    }

    private func advanceToNextTurn() {
        state.currentPlayerIndex = state.nextPlayerIndex(after: state.currentPlayerIndex)
        state.cardsPlayedThisTurn = 0
        state.pendingDoubleUp = PendingDoubleUp()
        state.turnNumber += 1
        state.phase = .drawing
    }
}

// MARK: - Card Destination

enum CardDestination: Codable {
    case bank
    case property(PropertyColor)
    case action
    case rent(PropertyColor?)   // chosen color for rent
}
