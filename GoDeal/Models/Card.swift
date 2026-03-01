import Foundation

// MARK: - Card Type

enum CardType: Hashable {
    case property(PropertyColor)
    case money(Int)
    case action(ActionType)
    case rent([PropertyColor])       // two-color: charge all players
    case wildRent                    // any-color: charge one player
    case wildProperty([PropertyColor]) // can be placed in any of the listed colors
}

// MARK: - Action Type

enum ActionType: String, CaseIterable, Hashable {
    case dealSnatcher  // Steal a complete property set
    case noDeal        // Cancel any action played against you
    case quickGrab     // Steal one property from an incomplete set
    case swapIt        // Trade one of your properties for any other player's
    case collectNow    // One player pays you $5M
    case bigSpender    // All other players pay you $2M
    case dealForward   // Draw 2 extra cards
    case doubleUp      // Double rent on the same turn
    case cornerStore   // Add to a complete set (+$3M rent)
    case towerBlock    // Add after Corner Store (+$4M rent)

    var displayName: String {
        switch self {
        case .dealSnatcher: return "Deal Snatcher!"
        case .noDeal:       return "No Deal!"
        case .quickGrab:    return "Quick Grab!"
        case .swapIt:       return "Swap It!"
        case .collectNow:   return "Collect Now!"
        case .bigSpender:   return "Big Spender!"
        case .dealForward:  return "Deal Forward!"
        case .doubleUp:     return "Double Up!"
        case .cornerStore:  return "Corner Store"
        case .towerBlock:   return "Tower Block"
        }
    }

    var description: String {
        switch self {
        case .dealSnatcher: return "Steal a complete property set from any player."
        case .noDeal:       return "Cancel any action played against you."
        case .quickGrab:    return "Steal one property from another player's incomplete set."
        case .swapIt:       return "Trade one of your properties for any one of another player's."
        case .collectNow:   return "One player of your choice pays you $5M."
        case .bigSpender:   return "All other players pay you $2M each."
        case .dealForward:  return "Draw 2 extra cards from the deck."
        case .doubleUp:     return "Double the rent you collect this turn."
        case .cornerStore:  return "Add to a complete property set to increase rent by $3M."
        case .towerBlock:   return "Add after a Corner Store to increase rent by an additional $4M."
        }
    }
}

// MARK: - Card

struct Card: Identifiable, Hashable {
    let id: UUID
    let type: CardType
    let name: String
    let description: String
    let monetaryValue: Int  // Value when banked to pay debts
    let assetKey: String    // Stable key for custom image lookup

    // Convenience: is this card a "No Deal!" response card?
    var isNoDeal: Bool {
        if case .action(let actionType) = type, actionType == .noDeal {
            return true
        }
        return false
    }

    // Convenience: monetary value of the card itself (for banked money cards)
    var isMoneyCard: Bool {
        if case .money = type { return true }
        return false
    }

    var isPropertyCard: Bool {
        if case .property = type { return true }
        return false
    }

    var isWildProperty: Bool {
        if case .wildProperty = type { return true }
        return false
    }

    var propertyColor: PropertyColor? {
        switch type {
        case .property(let color): return color
        default: return nil
        }
    }
}
