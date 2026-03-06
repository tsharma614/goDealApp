import Foundation

// MARK: - AI Difficulty

enum AIDifficulty: String, CaseIterable {
    case easy
    case medium
    case hard
}

// MARK: - AI Decision

struct AIDecision {
    let card: Card
    let destination: CardDestination
    let targetPlayerIndex: Int?
    let targetPropertyColor: PropertyColor?
    let wildColor: PropertyColor?

    init(
        card: Card,
        destination: CardDestination,
        targetPlayerIndex: Int? = nil,
        targetPropertyColor: PropertyColor? = nil,
        wildColor: PropertyColor? = nil
    ) {
        self.card = card
        self.destination = destination
        self.targetPlayerIndex = targetPlayerIndex
        self.targetPropertyColor = targetPropertyColor
        self.wildColor = wildColor
    }
}

// MARK: - AI Strategy

enum AIStrategy {

    /// Returns the next card play decision for a CPU player, or nil to end turn.
    static func decideNextPlay(
        state: GameState,
        playerIndex: Int,
        difficulty: AIDifficulty
    ) -> AIDecision? {
        switch difficulty {
        case .easy:   return easyDecision(state: state, playerIndex: playerIndex)
        case .medium: return mediumDecision(state: state, playerIndex: playerIndex)
        case .hard:   return hardDecision(state: state, playerIndex: playerIndex)
        }
    }

    // MARK: - Easy Strategy (random valid play)

    private static func easyDecision(state: GameState, playerIndex: Int) -> AIDecision? {
        guard state.canPlayCard else { return nil }
        let hand = state.players[playerIndex].hand
        guard !hand.isEmpty else { return nil }

        let shuffled = hand.shuffled()
        for card in shuffled {
            if let decision = makeValidDecision(card: card, state: state, playerIndex: playerIndex) {
                return decision
            }
        }
        return nil
    }

    // MARK: - Medium Strategy (priority heuristics)

    private static func mediumDecision(state: GameState, playerIndex: Int) -> AIDecision? {
        guard state.canPlayCard else { return nil }
        let hand = state.players[playerIndex].hand
        let player = state.players[playerIndex]

        // 1. Play Deal Snatcher if it wins the game
        if let decision = tryDealSnatcher(hand: hand, state: state, playerIndex: playerIndex, winningOnly: true) {
            return decision
        }

        // 2. Quick Grab / Swap It to steal a set-completing property
        if let decision = tryStealSetCompleting(hand: hand, state: state, playerIndex: playerIndex) {
            return decision
        }

        // 3. Play rent if it yields $4M+
        if let decision = tryHighValueRent(hand: hand, state: state, playerIndex: playerIndex, threshold: 4) {
            return decision
        }

        // 4. Property that completes or most-advances a partial set
        if let decision = tryBestProperty(hand: hand, state: state, playerIndex: playerIndex) {
            return decision
        }

        // 5. Deal Forward if hand <= 3 cards
        if player.hand.count <= 3,
           let dealFwd = hand.first(where: { if case .action(.dealForward) = $0.type { return true }; return false }) {
            return AIDecision(card: dealFwd, destination: .action)
        }

        // 6. Bank highest-value money card
        if let decision = tryBankMoney(hand: hand, playerIndex: playerIndex) {
            return decision
        }

        // 7. Play Collect Now / Big Spender
        if let decision = tryIncomeAction(hand: hand, state: state, playerIndex: playerIndex) {
            return decision
        }

        // 8. Any valid play
        return easyDecision(state: state, playerIndex: playerIndex)
    }

    // MARK: - Hard Strategy (target the leader, always block wins)

    private static func hardDecision(state: GameState, playerIndex: Int) -> AIDecision? {
        guard state.canPlayCard else { return nil }
        let hand = state.players[playerIndex].hand
        let player = state.players[playerIndex]
        let otherIndices = state.otherPlayerIndices()

        // Identify the leader: player closest to winning (most complete sets, then most total properties).
        let leaderIndex = otherIndices.max(by: {
            let a = state.players[$0]
            let b = state.players[$1]
            if a.completedSets != b.completedSets { return a.completedSets < b.completedSets }
            return a.allPropertyCards.count < b.allPropertyCards.count
        })

        // 1. Win immediately: Deal Snatcher to reach 3 sets
        if let decision = tryDealSnatcher(hand: hand, state: state, playerIndex: playerIndex, winningOnly: true) {
            return decision
        }

        // 1.5. Block opponent 1 card from winning (2 complete + 1 near-done incomplete)
        if let nearWinIdx = opponentNearWin(state: state, playerIndex: playerIndex) {
            if let d = tryDealSnatcterAgainst(hand: hand, state: state, playerIndex: playerIndex, targetIndex: nearWinIdx) {
                return d
            }
            let target = state.players[nearWinIdx]
            if let grab = hand.first(where: { if case .action(.quickGrab) = $0.type { return true }; return false }),
               target.properties.values.contains(where: { !$0.isComplete && !$0.properties.isEmpty }) {
                return AIDecision(card: grab, destination: .action, targetPlayerIndex: nearWinIdx)
            }
        }

        // 2. Block the leader from winning: steal their complete set if they're at 2+ sets
        if let leader = leaderIndex, state.players[leader].completedSets >= 2 {
            if let decision = tryDealSnatcterAgainst(hand: hand, state: state, playerIndex: playerIndex, targetIndex: leader) {
                return decision
            }
        }

        // 3. Quick Grab a set-completing property for ourselves
        if let decision = tryStealSetCompleting(hand: hand, state: state, playerIndex: playerIndex) {
            return decision
        }

        // 4. Play Double Up before rent for maximum impact
        if let decision = tryDoubleUpThenRent(hand: hand, state: state, playerIndex: playerIndex) {
            return decision
        }

        // 5. Play rent targeting the leader (any rent >= $1M against them, or any threshold >= $1M)
        if let leader = leaderIndex,
           let decision = tryRentAgainst(hand: hand, state: state, playerIndex: playerIndex, preferredTarget: leader, threshold: 1) {
            return decision
        }
        if let decision = tryHighValueRent(hand: hand, state: state, playerIndex: playerIndex, threshold: 1) {
            return decision
        }

        // 5.5. Maintain $5M bank before placing properties
        if player.bankTotal < 5, let moneyDecision = tryBankMoney(hand: hand, playerIndex: playerIndex) {
            return moneyDecision
        }

        // 5.75. Drain richest opponent when they're flush (>= $5M)
        if let richOpp = otherIndices
                .filter({ state.players[$0].bankTotal >= 5 })
                .max(by: { state.players[$0].bankTotal < state.players[$1].bankTotal }) {
            if let cn = hand.first(where: { if case .action(.collectNow) = $0.type { return true }; return false }) {
                return AIDecision(card: cn, destination: .action, targetPlayerIndex: richOpp)
            }
            if let bs = hand.first(where: { if case .action(.bigSpender) = $0.type { return true }; return false }) {
                return AIDecision(card: bs, destination: .action)
            }
        }

        // 6. Property that advances our best partial set
        if let decision = tryBestProperty(hand: hand, state: state, playerIndex: playerIndex) {
            return decision
        }

        // 7. Offensive steal against leader even if it doesn't complete our set
        if let leader = leaderIndex {
            if let decision = tryOffensiveSteal(hand: hand, state: state, playerIndex: playerIndex, targetIndex: leader) {
                return decision
            }
        }

        // 8. Corner Store / Tower Block on a complete set
        if let decision = tryImprovement(hand: hand, state: state, playerIndex: playerIndex) {
            return decision
        }

        // 9. Deal Forward if hand <= 3 cards
        if player.hand.count <= 3,
           let dealFwd = hand.first(where: { if case .action(.dealForward) = $0.type { return true }; return false }) {
            return AIDecision(card: dealFwd, destination: .action)
        }

        // 10. Bank money
        if let decision = tryBankMoney(hand: hand, playerIndex: playerIndex) {
            return decision
        }

        // 11. Collect Now / Big Spender
        if let decision = tryIncomeAction(hand: hand, state: state, playerIndex: playerIndex) {
            return decision
        }

        // 12. Any valid play
        return easyDecision(state: state, playerIndex: playerIndex)
    }

    // MARK: - No Deal! Decision

    /// Should the CPU play No Deal! in response to an attack?
    static func shouldPlayNoDeal(
        state: GameState,
        playerIndex: Int,
        actionCard: Card,
        difficulty: AIDifficulty
    ) -> Card? {
        let hand = state.players[playerIndex].hand
        guard let noDealCard = hand.first(where: { $0.isNoDeal }) else { return nil }

        if difficulty == .easy {
            // 30% chance on easy
            return Double.random(in: 0...1) < 0.3 ? noDealCard : nil
        }

        guard case .action(let actionType) = actionCard.type else { return nil }
        let player = state.players[playerIndex]

        if difficulty == .hard {
            // Hard: always block property threats; save No Deal for big money hits
            switch actionType {
            case .dealSnatcher:
                return player.completedSets > 0 ? noDealCard : nil
            case .quickGrab:
                return !player.allPropertyCards.isEmpty ? noDealCard : nil
            case .swapIt:
                return !player.allPropertyCards.isEmpty ? noDealCard : nil
            case .collectNow:
                return player.bankTotal > 0 && player.bankTotal <= 5 ? noDealCard : nil
            case .bigSpender:
                return player.bankTotal > 0 && player.bankTotal <= 2 ? noDealCard : nil
            default:
                return nil
            }
        }

        // Medium: protect complete sets or block wins
        switch actionType {
        case .dealSnatcher:
            return player.completedSets > 0 ? noDealCard : nil
        case .quickGrab:
            let nearComplete = player.properties.values.filter {
                !$0.isComplete && $0.properties.count >= $0.color.setSize - 1
            }
            return !nearComplete.isEmpty ? noDealCard : nil
        case .swapIt:
            return player.completedSets > 0 ? noDealCard : nil
        case .collectNow, .bigSpender:
            return player.bankTotal < 2 ? noDealCard : nil
        default:
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Find an opponent who has 2 complete sets AND an incomplete set 1 card from completion.
    private static func opponentNearWin(state: GameState, playerIndex: Int) -> Int? {
        state.players.indices.filter { $0 != playerIndex }.first { idx in
            let p = state.players[idx]
            guard p.completedSets >= 2 else { return false }
            return p.properties.values.contains {
                !$0.isComplete && !$0.properties.isEmpty &&
                ($0.color.setSize - $0.properties.count) <= 1
            }
        }
    }

    private static func tryDealSnatcher(
        hand: [Card],
        state: GameState,
        playerIndex: Int,
        winningOnly: Bool
    ) -> AIDecision? {
        guard let snatchers = hand.filter({ if case .action(.dealSnatcher) = $0.type { return true }; return false }).first else { return nil }

        let player = state.players[playerIndex]
        let otherIndices = state.otherPlayerIndices()

        for targetIdx in otherIndices {
            let target = state.players[targetIdx]
            let completeSets = target.properties.filter { $0.value.isComplete }
            guard !completeSets.isEmpty else { continue }

            if winningOnly {
                // Would stealing give us 3 sets?
                let newCount = player.completedSets + 1
                if newCount >= 3 {
                    let color = completeSets.keys.first!
                    return AIDecision(
                        card: snatchers,
                        destination: .action,
                        targetPlayerIndex: targetIdx,
                        targetPropertyColor: color
                    )
                }
            } else {
                let color = completeSets.keys.first!
                return AIDecision(
                    card: snatchers,
                    destination: .action,
                    targetPlayerIndex: targetIdx,
                    targetPropertyColor: color
                )
            }
        }
        return nil
    }

    private static func tryStealSetCompleting(
        hand: [Card],
        state: GameState,
        playerIndex: Int
    ) -> AIDecision? {
        let player = state.players[playerIndex]
        let otherIndices = state.otherPlayerIndices()

        let quickGrabs = hand.filter { if case .action(.quickGrab) = $0.type { return true }; return false }
        let swapIts = hand.filter { if case .action(.swapIt) = $0.type { return true }; return false }

        guard !quickGrabs.isEmpty || !swapIts.isEmpty else { return nil }

        // Look for a property on the board that would complete one of our sets
        for (color, ourSet) in player.properties {
            guard !ourSet.isComplete else { continue }
            let needed = ourSet.color.setSize - ourSet.properties.count

            for targetIdx in otherIndices {
                let target = state.players[targetIdx]
                guard let targetSet = target.properties[color],
                      !targetSet.properties.isEmpty else { continue }
                let incomplete = !targetSet.isComplete

                if incomplete, needed == 1, let grabCard = quickGrabs.first {
                    return AIDecision(
                        card: grabCard,
                        destination: .action,
                        targetPlayerIndex: targetIdx,
                        targetPropertyColor: color
                    )
                }
            }
        }
        return nil
    }

    private static func tryHighValueRent(
        hand: [Card],
        state: GameState,
        playerIndex: Int,
        threshold: Int
    ) -> AIDecision? {
        let player = state.players[playerIndex]
        let otherIndices = state.otherPlayerIndices()

        for card in hand {
            switch card.type {
            case .rent(let colors):
                // Find the best matching color we own
                let bestColor = colors
                    .compactMap { color -> (PropertyColor, Int)? in
                        guard let set = player.properties[color] else { return nil }
                        return (color, set.currentRent)
                    }
                    .max(by: { $0.1 < $1.1 })

                if let (color, rent) = bestColor, rent >= threshold {
                    return AIDecision(card: card, destination: .rent(color))
                }

            case .wildRent:
                // Pick highest rent color, pick richest target
                let bestColorAndRent = player.properties.values
                    .map { ($0.color, $0.currentRent) }
                    .max(by: { $0.1 < $1.1 })

                if let (color, rent) = bestColorAndRent, rent >= threshold {
                    let richestTarget = otherIndices.max(by: { state.players[$0].bankTotal < state.players[$1].bankTotal })
                    return AIDecision(
                        card: card,
                        destination: .rent(color),
                        targetPlayerIndex: richestTarget
                    )
                }

            default: break
            }
        }
        return nil
    }

    private static func tryBestProperty(
        hand: [Card],
        state: GameState,
        playerIndex: Int
    ) -> AIDecision? {
        let player = state.players[playerIndex]

        // Score each property card: higher score = more beneficial to play
        var best: (Card, PropertyColor, Int)? = nil

        for card in hand {
            switch card.type {
            case .property(let color):
                let existing = player.properties[color]?.properties.count ?? 0
                // Score: how many props we'll have after placing
                let score = existing + 1
                if best == nil || score > best!.2 {
                    best = (card, color, score)
                }

            case .wildProperty(let colors):
                // Rainbow wilds have an empty colors array — treat all colors as valid
                let validColors = colors.isEmpty ? Array(PropertyColor.allCases) : colors
                let bestColor = validColors.max(by: {
                    let a = player.properties[$0]?.properties.count ?? 0
                    let b = player.properties[$1]?.properties.count ?? 0
                    return a < b
                })
                if let color = bestColor {
                    let existing = player.properties[color]?.properties.count ?? 0
                    if best == nil || existing + 1 > best!.2 {
                        best = (card, color, existing + 1)
                    }
                }

            default: break
            }
        }

        if let (card, color, _) = best {
            return AIDecision(card: card, destination: .property(color), wildColor: color)
        }
        return nil
    }

    private static func tryBankMoney(hand: [Card], playerIndex: Int) -> AIDecision? {
        let moneyCards = hand.filter { $0.isMoneyCard }
        guard let highest = moneyCards.max(by: { $0.monetaryValue < $1.monetaryValue }) else { return nil }
        return AIDecision(card: highest, destination: .bank)
    }

    private static func tryIncomeAction(
        hand: [Card],
        state: GameState,
        playerIndex: Int
    ) -> AIDecision? {
        for card in hand {
            if case .action(let type) = card.type {
                switch type {
                case .collectNow:
                    let richestTarget = state.otherPlayerIndices()
                        .max(by: { state.players[$0].bankTotal < state.players[$1].bankTotal })
                    return AIDecision(card: card, destination: .action, targetPlayerIndex: richestTarget)
                case .bigSpender:
                    return AIDecision(card: card, destination: .action)
                default: break
                }
            }
        }
        return nil
    }

    /// Steal a complete set specifically from a given target (hard CPU blocker).
    private static func tryDealSnatcterAgainst(
        hand: [Card],
        state: GameState,
        playerIndex: Int,
        targetIndex: Int
    ) -> AIDecision? {
        guard let snatcher = hand.first(where: { if case .action(.dealSnatcher) = $0.type { return true }; return false }) else { return nil }
        let completeSets = state.players[targetIndex].properties.filter { $0.value.isComplete }
        guard let color = completeSets.keys.first else { return nil }
        return AIDecision(card: snatcher, destination: .action, targetPlayerIndex: targetIndex, targetPropertyColor: color)
    }

    /// Try to play a rent card targeting a specific player (hard CPU prefers hitting the leader).
    private static func tryRentAgainst(
        hand: [Card],
        state: GameState,
        playerIndex: Int,
        preferredTarget: Int,
        threshold: Int
    ) -> AIDecision? {
        let player = state.players[playerIndex]
        for card in hand {
            switch card.type {
            case .rent(let colors):
                let best = colors
                    .compactMap { color -> (PropertyColor, Int)? in
                        guard let set = player.properties[color] else { return nil }
                        return (color, set.currentRent)
                    }
                    .max(by: { $0.1 < $1.1 })
                if let (color, rent) = best, rent >= threshold {
                    return AIDecision(card: card, destination: .rent(color))
                }
            case .wildRent:
                let best = player.properties.values
                    .map { ($0.color, $0.currentRent) }
                    .max(by: { $0.1 < $1.1 })
                if let (color, rent) = best, rent >= threshold {
                    return AIDecision(card: card, destination: .rent(color), targetPlayerIndex: preferredTarget)
                }
            default: break
            }
        }
        return nil
    }

    /// Play Double Up only when a rent card is also available (maximizes value).
    private static func tryDoubleUpThenRent(
        hand: [Card],
        state: GameState,
        playerIndex: Int
    ) -> AIDecision? {
        let player = state.players[playerIndex]
        guard hand.contains(where: { if case .action(.doubleUp) = $0.type { return true }; return false }) else { return nil }

        // Only worth it if we have a rent card and own at least one property set
        let hasRent = hand.contains(where: {
            switch $0.type {
            case .rent, .wildRent: return true
            default: return false
            }
        })
        guard hasRent, !player.properties.isEmpty else { return nil }

        let doubleUp = hand.first(where: { if case .action(.doubleUp) = $0.type { return true }; return false })!
        return AIDecision(card: doubleUp, destination: .action)
    }

    /// Play a steal card (quickGrab/swapIt) offensively against a target even if it doesn't complete our set.
    private static func tryOffensiveSteal(
        hand: [Card],
        state: GameState,
        playerIndex: Int,
        targetIndex: Int
    ) -> AIDecision? {
        let target = state.players[targetIndex]
        guard !target.allPropertyCards.isEmpty else { return nil }

        if let grabCard = hand.first(where: { if case .action(.quickGrab) = $0.type { return true }; return false }),
           target.properties.values.contains(where: { !$0.isComplete && !$0.properties.isEmpty }) {
            return AIDecision(card: grabCard, destination: .action, targetPlayerIndex: targetIndex)
        }

        // SwapIt: trade our cheapest incomplete property for their most expensive one
        let player = state.players[playerIndex]
        if let swapCard = hand.first(where: { if case .action(.swapIt) = $0.type { return true }; return false }),
           !player.allPropertyCards.isEmpty {
            let ourCheapest = player.properties.values
                .filter { !$0.isComplete && !$0.properties.isEmpty }
                .flatMap { $0.properties }
                .min(by: { $0.monetaryValue < $1.monetaryValue })
            let theirBest = target.properties.values
                .filter { !$0.isComplete && !$0.properties.isEmpty }
                .flatMap { $0.properties }
                .max(by: { $0.monetaryValue < $1.monetaryValue })
            // Only swap if we're trading up
            if let ours = ourCheapest, let theirs = theirBest, theirs.monetaryValue > ours.monetaryValue {
                return AIDecision(card: swapCard, destination: .action, targetPlayerIndex: targetIndex)
            }
        }

        return nil
    }

    /// Play Corner Store or Tower Block on a complete set.
    private static func tryImprovement(
        hand: [Card],
        state: GameState,
        playerIndex: Int
    ) -> AIDecision? {
        let player = state.players[playerIndex]
        for card in hand {
            if case .action(let type) = card.type {
                switch type {
                case .cornerStore:
                    if let color = player.properties.first(where: { $0.value.canAddCornerStore })?.key {
                        return AIDecision(card: card, destination: .action, targetPropertyColor: color)
                    }
                case .apartmentBuilding:
                    if let color = player.properties.first(where: { $0.value.canAddApartmentBuilding })?.key {
                        return AIDecision(card: card, destination: .action, targetPropertyColor: color)
                    }
                default: break
                }
            }
        }
        return nil
    }

    private static func makeValidDecision(
        card: Card,
        state: GameState,
        playerIndex: Int
    ) -> AIDecision? {
        let player = state.players[playerIndex]

        switch card.type {
        case .money:
            return AIDecision(card: card, destination: .bank)

        case .property(let color):
            return AIDecision(card: card, destination: .property(color))

        case .wildProperty(let colors):
            // Rainbow wilds have an empty colors array — treat all colors as valid
            let validColors = colors.isEmpty ? Array(PropertyColor.allCases) : colors
            guard let color = validColors.first else { return nil }
            return AIDecision(card: card, destination: .property(color), wildColor: color)

        case .action(let type):
            switch type {
            case .noDeal: return nil  // Only play as response
            case .doubleUp: return nil // Only play before rent
            case .cornerStore:
                let eligible = player.properties.filter { $0.value.canAddCornerStore }
                if let color = eligible.keys.first {
                    return AIDecision(card: card, destination: .action, targetPropertyColor: color)
                }
                return nil
            case .apartmentBuilding:
                let eligible = player.properties.filter { $0.value.canAddApartmentBuilding }
                if let color = eligible.keys.first {
                    return AIDecision(card: card, destination: .action, targetPropertyColor: color)
                }
                return nil
            case .dealSnatcher:
                for targetIdx in state.otherPlayerIndices() {
                    let complete = state.players[targetIdx].properties.filter { $0.value.isComplete }
                    if let color = complete.keys.first {
                        return AIDecision(card: card, destination: .action, targetPlayerIndex: targetIdx, targetPropertyColor: color)
                    }
                }
                return nil
            case .quickGrab:
                for targetIdx in state.otherPlayerIndices() {
                    let incomplete = state.players[targetIdx].properties.filter { !$0.value.properties.isEmpty && !$0.value.isComplete }
                    if !incomplete.isEmpty {
                        return AIDecision(card: card, destination: .action, targetPlayerIndex: targetIdx)
                    }
                }
                return nil
            case .swapIt:
                for targetIdx in state.otherPlayerIndices() {
                    if !state.players[targetIdx].allPropertyCards.isEmpty,
                       !player.allPropertyCards.isEmpty {
                        return AIDecision(card: card, destination: .action, targetPlayerIndex: targetIdx)
                    }
                }
                return nil
            default:
                return AIDecision(card: card, destination: .action, targetPlayerIndex: state.nextPlayerIndex(after: playerIndex))
            }

        case .rent(let colors):
            let matching = colors.filter { player.properties[$0] != nil }
            if let color = matching.first {
                return AIDecision(card: card, destination: .rent(color))
            }
            return nil

        case .wildRent:
            if let color = player.properties.keys.first {
                let target = state.otherPlayerIndices().first
                return AIDecision(card: card, destination: .rent(color), targetPlayerIndex: target)
            }
            return nil
        }
    }
}
