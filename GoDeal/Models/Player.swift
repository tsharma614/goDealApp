import Foundation

// MARK: - Player

struct Player: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var isHuman: Bool
    var hand: [Card]
    var bank: [Card]
    var properties: [PropertyColor: PropertySet]

    init(id: UUID = UUID(), name: String, isHuman: Bool) {
        self.id = id
        self.name = name
        self.isHuman = isHuman
        self.hand = []
        self.bank = []
        self.properties = [:]
    }

    // Number of complete property sets
    var completedSets: Int {
        properties.values.filter { $0.isComplete }.count
    }

    // Total bank value in millions
    var bankTotal: Int {
        bank.reduce(0) { sum, card in
            if case .money(let value) = card.type {
                return sum + value
            }
            return sum + card.monetaryValue
        }
    }

    // All property cards across all sets
    var allPropertyCards: [Card] {
        properties.values.flatMap { $0.properties }
    }

    // Total asset value (bank + property monetaryValues)
    var totalAssets: Int {
        let propertyValue = allPropertyCards.reduce(0) { $0 + $1.monetaryValue }
        return bankTotal + propertyValue
    }

    // Add a card to hand
    mutating func addToHand(_ card: Card) {
        hand.append(card)
    }

    // Add multiple cards to hand
    mutating func addToHand(_ cards: [Card]) {
        hand.append(contentsOf: cards)
    }

    // Remove a card from hand by id, returns nil if not found
    mutating func removeFromHand(id: UUID) -> Card? {
        if let index = hand.firstIndex(where: { $0.id == id }) {
            return hand.remove(at: index)
        }
        return nil
    }

    // Add a card to bank
    mutating func addToBank(_ card: Card) {
        bank.append(card)
    }

    // Place a property card into a specific color set
    mutating func placeProperty(_ card: Card, in color: PropertyColor) {
        if properties[color] == nil {
            properties[color] = PropertySet(color: color, properties: [])
        }
        properties[color]?.addProperty(card)
    }

    // Remove a property card from any set, returns the card and its color.
    // Also clears improvements (Corner Store / Tower Block) if the set is no longer complete.
    mutating func removeProperty(id: UUID) -> (Card, PropertyColor)? {
        for color in properties.keys {
            if let removed = properties[color]?.removeProperty(withId: id) {
                if properties[color]?.properties.isEmpty == true {
                    properties.removeValue(forKey: color)
                } else if properties[color]?.isComplete == false {
                    // Set is now incomplete — improvements require a complete set
                    properties[color]?.hasCornerStore = false
                    properties[color]?.hasTowerBlock = false
                }
                return (removed, color)
            }
        }
        return nil
    }

    // Pay a specific amount from bank (no change — overpayment kept by collector)
    // Returns the cards paid (may be less than amount if insufficient funds)
    mutating func payFromBank(amount: Int) -> [Card] {
        var paid: [Card] = []
        var remaining = amount

        // Sort bank cards by value ascending to use smallest denominations first
        let sortedIndices = bank.indices.sorted {
            bank[$0].monetaryValue < bank[$1].monetaryValue
        }

        // Try to find exact or minimal overpayment
        // Simple greedy: take smallest cards until we meet the amount
        var taken: [Int] = []
        var soFar = 0
        for idx in sortedIndices {
            if soFar >= remaining { break }
            taken.append(idx)
            soFar += bank[idx].monetaryValue
        }

        // Remove taken cards from bank (in reverse order to keep indices valid)
        let sortedTakenIndices = taken.sorted().reversed()
        for idx in sortedTakenIndices {
            paid.append(bank.remove(at: idx))
        }

        return paid
    }
}
