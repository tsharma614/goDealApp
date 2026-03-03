import Foundation

// MARK: - Deck Builder
// Constructs the canonical 110-card Go! Deal! deck.
//
// Card counts (matches Monopoly Deal):
//   Money: 20 cards (6×$1M, 5×$2M, 3×$3M, 3×$4M, 2×$5M, 1×$10M) = 20
//   Properties: 28 cards (2 brown, 3 sky, 3 pink, 3 orange, 3 red, 3 yellow, 3 green, 2 dark blue, 4 railroad, 2 utility) = 28
//   Wild Properties: 11 cards (2-color combos + rainbow wilds) = 11
//   Rent cards: 13 cards (2 per two-color pair × 5 pairs + 3 rainbow) = 13
//   Action cards: 38 cards
//     - Deal Snatcher: 3
//     - No Deal: 3
//     - Quick Grab: 3
//     - Swap It: 3
//     - Collect Now: 3
//     - Big Spender: 3
//     - Deal Forward: 3
//     - Double Up: 2
//     - Corner Store: 3
//     - Apartment Building: 2
//   Total action: 28 ... hmm let me recount
//
// Standard Monopoly Deal: 110 cards
// Money: 20
// Properties: 28
// Action: 34 (pass go×3, deal breaker×2, sly deal×3, forced deal×3, debt×3, birthday×3, rent×2×5=10, multicolor×3, house×3, hotel×2, just say no×3)
// Let me use the standard distribution:

struct DeckBuilder {

    static func buildDeck() -> [Card] {
        var cards: [Card] = []

        cards += buildMoneyCards()
        cards += buildPropertyCards()
        cards += buildWildPropertyCards()
        cards += buildRentCards()
        cards += buildActionCards()

        return cards.shuffled()
    }

    // MARK: - Money Cards (20 total)
    // $1M × 6, $2M × 5, $3M × 3, $4M × 3, $5M × 2, $10M × 1
    private static func buildMoneyCards() -> [Card] {
        var cards: [Card] = []
        let denominations: [(Int, Int)] = [(1,6),(2,5),(3,3),(4,3),(5,2),(10,1)]
        for (value, count) in denominations {
            for i in 1...count {
                cards.append(Card(
                    id: UUID(),
                    type: .money(value),
                    name: "$\(value)M",
                    description: "Add to your bank.",
                    monetaryValue: value,
                    assetKey: "card_money_\(value)_\(i)"
                ))
            }
        }
        return cards  // 20 cards
    }

    // MARK: - Property Cards (28 total)
    private static func buildPropertyCards() -> [Card] {
        var cards: [Card] = []
        let colorCounts: [(PropertyColor, Int, Int)] = [
            // (color, count, monetaryValue)
            (.rustDistrict,   2, 1),
            (.skylineAve,     3, 1),
            (.neonRow,        3, 2),
            (.sunsetStrip,    3, 2),
            (.hotZone,        3, 3),
            (.goldRush,       3, 3),
            (.emeraldQuarter, 3, 4),
            (.blueChip,       2, 4),
            (.transitLine,    4, 2),
            (.powerAndWater,  2, 2),
        ]

        for (color, count, value) in colorCounts {
            let streetNames = PropertyNameStore.names(for: color)
            for i in 0..<count {
                let streetName = i < streetNames.count ? streetNames[i] : "\(color.displayName) \(i+1)"
                cards.append(Card(
                    id: UUID(),
                    type: .property(color),
                    name: streetName,
                    description: "\(color.displayName) property. Rent: \(color.rentTable.prefix(count).map{"$\($0)M"}.joined(separator: "/"))",
                    monetaryValue: value,
                    assetKey: "card_prop_\(color.rawValue)_\(i+1)"
                ))
            }
        }
        return cards  // 28 cards
    }

    // MARK: - Wild Property Cards (11 total)
    // 2-color wilds: [brown+railroad, light blue+railroad, utility+railroad,
    //                 light blue+railroad (2nd copy), green+dark blue,
    //                 green+railroad, red+yellow, pink+orange,
    //                 orange+red] = 9
    // Rainbow (any color): 2
    private static func buildWildPropertyCards() -> [Card] {
        var cards: [Card] = []

        let pairs: [([PropertyColor], Int, String)] = [
            ([.rustDistrict, .transitLine],    1, "wild_brown_railroad"),
            ([.skylineAve, .transitLine],      1, "wild_sky_railroad"),
            ([.powerAndWater, .transitLine],   1, "wild_utility_railroad"),
            ([.skylineAve, .transitLine],      1, "wild_sky_railroad_2"),
            ([.emeraldQuarter, .blueChip],     1, "wild_green_darkblue"),
            ([.emeraldQuarter, .transitLine],  1, "wild_green_railroad"),
            ([.hotZone, .goldRush],            1, "wild_red_yellow"),
            ([.neonRow, .sunsetStrip],         1, "wild_pink_orange"),
            ([.sunsetStrip, .hotZone],         1, "wild_orange_red"),
        ]

        for (colors, _, assetKey) in pairs {
            let colorNames = colors.map { $0.displayName }.joined(separator: "/")
            cards.append(Card(
                id: UUID(),
                type: .wildProperty(colors),
                name: "Wild: \(colorNames)",
                description: "Can be placed in either \(colorNames) district.",
                monetaryValue: 1,
                assetKey: "card_\(assetKey)"
            ))
        }

        // 2 rainbow wild properties (can be any color)
        for i in 1...2 {
            cards.append(Card(
                id: UUID(),
                type: .wildProperty(PropertyColor.allCases),
                name: "Rainbow Wild",
                description: "Can be placed in any property district.",
                monetaryValue: 2,
                assetKey: "card_wild_rainbow_\(i)"
            ))
        }

        return cards  // 11 cards
    }

    // MARK: - Rent Cards (13 total)
    // 2-color rent pairs × 2 each = 10; rainbow (any 1 player) × 3 = 3
    private static func buildRentCards() -> [Card] {
        var cards: [Card] = []

        let rentPairs: [([PropertyColor], String)] = [
            ([.rustDistrict, .blueChip],          "rent_brown_darkblue"),
            ([.skylineAve, .transitLine],          "rent_sky_railroad"),
            ([.neonRow, .sunsetStrip],             "rent_pink_orange"),
            ([.hotZone, .goldRush],                "rent_red_yellow"),
            ([.emeraldQuarter, .powerAndWater],    "rent_green_utility"),
        ]

        for (colors, assetBase) in rentPairs {
            let colorNames = colors.map { $0.displayName }.joined(separator: " & ")
            for i in 1...2 {
                cards.append(Card(
                    id: UUID(),
                    type: .rent(colors),
                    name: "Collect Dues!",
                    description: "Charge all players rent for your \(colorNames) properties.",
                    monetaryValue: 1,
                    assetKey: "card_\(assetBase)_\(i)"
                ))
            }
        }

        // 3 wild (rainbow) rent cards — charge one player, any color
        for i in 1...3 {
            cards.append(Card(
                id: UUID(),
                type: .wildRent,
                name: "Rent Blitz!",
                description: "Pick any district you own and charge one player rent for it.",
                monetaryValue: 1,
                assetKey: "card_rent_wild_\(i)"
            ))
        }

        return cards  // 13 cards
    }

    // MARK: - Action Cards (38 total)
    // dealSnatcher×3, noDeal×3, quickGrab×3, swapIt×3, collectNow×3,
    // bigSpender×3, dealForward×3, doubleUp×2, cornerStore×3, apartmentBuilding×2
    // Total: 3+3+3+3+3+3+3+2+3+2 = 28 ... we need 38.
    // Let me recalculate to reach 110:
    // Money(20) + Properties(28) + Wilds(11) + Rent(13) = 72
    // Action needed: 110 - 72 = 38
    // Adjustment: dealSnatcher×2, noDeal×3, quickGrab×3, swapIt×3, collectNow×3,
    //             bigSpender×3, dealForward×3, doubleUp×2, cornerStore×3, apartmentBuilding×2
    //             + extra 11: add more of some types
    // Actually let's match original MD counts:
    // Pass Go×10 equivalent = dealForward×10? No.
    // Standard: PassGo×10, DealBreaker×2, SlyDeal×3, ForcedDeal×3, DebtCollector×3, Birthday×3,
    //           House×3, Hotel×2, DoubleRent×2, JustSayNo×3 = 34... but we have more.
    // Let me use: dealForward×10, dealSnatcher×2, noDeal×3, quickGrab×3, swapIt×3,
    //             collectNow×3, bigSpender×3, doubleUp×2, cornerStore×3, apartmentBuilding×2 = 34
    // Hmm still short. Let me just match the total exactly.
    // Money20 + Prop28 + Wild11 + Rent13 = 72, need 38 actions.
    // Use: dealForward×10, dealSnatcher×3, noDeal×3, quickGrab×3, swapIt×3,
    //      collectNow×3, bigSpender×3, doubleUp×2, cornerStore×3, apartmentBuilding×3 = 36
    // +2 more: noDeal has 3, add 2 more noDeal = 5? Or add 2 more quickGrab.
    // Let's go: dealForward×10, dealSnatcher×3, noDeal×5, quickGrab×3, swapIt×3,
    //           collectNow×3, bigSpender×3, doubleUp×2, cornerStore×3, apartmentBuilding×3 = 38
    private static func buildActionCards() -> [Card] {
        var cards: [Card] = []

        let actionSpecs: [(ActionType, Int)] = [
            (.dealForward,  10),
            (.dealSnatcher,  3),
            (.noDeal,        5),
            (.quickGrab,     3),
            (.swapIt,        3),
            (.collectNow,    3),
            (.bigSpender,    3),
            (.doubleUp,      2),
            (.cornerStore,   3),
            (.apartmentBuilding,    3),
        ]
        // Total: 10+3+5+3+3+3+3+2+3+3 = 38 ✓

        for (action, count) in actionSpecs {
            let monetaryValue: Int = {
                switch action {
                case .cornerStore, .apartmentBuilding: return 3
                case .dealSnatcher: return 5
                default: return 2
                }
            }()
            for i in 1...count {
                cards.append(Card(
                    id: UUID(),
                    type: .action(action),
                    name: action.displayName,
                    description: action.description,
                    monetaryValue: monetaryValue,
                    assetKey: "card_\(action.rawValue)_\(i)"
                ))
            }
        }

        return cards  // 38 cards
    }
}

// MARK: - Deck Validation (for tests)
extension DeckBuilder {
    struct DeckStats {
        let total: Int
        let moneyCount: Int
        let propertyCount: Int
        let wildPropertyCount: Int
        let rentCount: Int
        let wildRentCount: Int
        let actionCount: Int
        let actionCounts: [ActionType: Int]
    }

    static func stats(for deck: [Card]) -> DeckStats {
        var money = 0, property = 0, wild = 0, rent = 0, wildRent = 0, action = 0
        var actionCounts: [ActionType: Int] = [:]

        for card in deck {
            switch card.type {
            case .money:         money += 1
            case .property:      property += 1
            case .wildProperty:  wild += 1
            case .rent:          rent += 1
            case .wildRent:      wildRent += 1
            case .action(let t):
                action += 1
                actionCounts[t, default: 0] += 1
            }
        }

        return DeckStats(
            total: deck.count,
            moneyCount: money,
            propertyCount: property,
            wildPropertyCount: wild,
            rentCount: rent,
            wildRentCount: wildRent,
            actionCount: action,
            actionCounts: actionCounts
        )
    }
}
