import Foundation

// MARK: - Property Set

struct PropertySet: Hashable, Identifiable {
    var id: PropertyColor { color }
    let color: PropertyColor
    var properties: [Card]
    var hasCornerStore: Bool = false
    var hasTowerBlock: Bool = false

    var isComplete: Bool {
        properties.count >= color.setSize
    }

    // Current rent based on number of properties + improvements
    var currentRent: Int {
        guard !properties.isEmpty else { return 0 }
        let count = properties.count
        let table = color.rentTable

        if isComplete {
            if hasTowerBlock && table.count >= 5 {
                return table[4]
            } else if hasCornerStore && table.count >= 4 {
                return table[3]
            } else {
                // Use the correct full-set index for each color:
                // 2-card sets get a bonus (index 2), 3-card = index 2, 4-card (Transit) = index 3
                let fullSetIndex = max(color.setSize - 1, 2)
                return table[min(fullSetIndex, table.count - 1)]
            }
        } else {
            let index = min(count - 1, table.count - 1)
            return table[index]
        }
    }

    // Can a Corner Store be added? (requires complete set, no corner store yet)
    var canAddCornerStore: Bool {
        isComplete && !hasCornerStore &&
        color != .transitLine && color != .powerAndWater
    }

    // Can a Tower Block be added? (requires complete set + corner store)
    var canAddTowerBlock: Bool {
        isComplete && hasCornerStore && !hasTowerBlock &&
        color != .transitLine && color != .powerAndWater
    }

    // Mutating helpers
    mutating func addProperty(_ card: Card) {
        properties.append(card)
    }

    mutating func removeProperty(withId id: UUID) -> Card? {
        if let index = properties.firstIndex(where: { $0.id == id }) {
            return properties.remove(at: index)
        }
        return nil
    }
}
