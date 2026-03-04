import XCTest
@testable import GoDeal

final class DeckBuilderTests: XCTestCase {

    var deck: [Card]!
    var stats: DeckBuilder.DeckStats!

    override func setUp() {
        super.setUp()
        deck = DeckBuilder.buildDeck()
        stats = DeckBuilder.stats(for: deck)
    }

    // MARK: - Total Count

    func testDeckHas110Cards() {
        XCTAssertEqual(stats.total, 110, "Deck must have exactly 110 cards, got \(stats.total)")
    }

    // MARK: - Money Cards

    func testDeckHas20MoneyCards() {
        XCTAssertEqual(stats.moneyCount, 20, "Money cards should be 20, got \(stats.moneyCount)")
    }

    func testMoneyDenominations() {
        let moneyCards = deck.compactMap { card -> Int? in
            if case .money(let value) = card.type { return value }
            return nil
        }
        let counts = Dictionary(moneyCards.map { ($0, 1) }, uniquingKeysWith: +)
        XCTAssertEqual(counts[1], 6, "Should have 6x $1M cards")
        XCTAssertEqual(counts[2], 5, "Should have 5x $2M cards")
        XCTAssertEqual(counts[3], 3, "Should have 3x $3M cards")
        XCTAssertEqual(counts[4], 3, "Should have 3x $4M cards")
        XCTAssertEqual(counts[5], 2, "Should have 2x $5M cards")
        XCTAssertEqual(counts[10], 1, "Should have 1x $10M card")
    }

    // MARK: - Property Cards

    func testDeckHas28PropertyCards() {
        XCTAssertEqual(stats.propertyCount, 28, "Property cards should be 28, got \(stats.propertyCount)")
    }

    func testPropertyColorCounts() {
        let byColor: [PropertyColor: Int] = deck.reduce(into: [:]) { dict, card in
            if case .property(let color) = card.type {
                dict[color, default: 0] += 1
            }
        }
        XCTAssertEqual(byColor[.rustDistrict], 2)
        XCTAssertEqual(byColor[.skylineAve], 3)
        XCTAssertEqual(byColor[.neonRow], 3)
        XCTAssertEqual(byColor[.sunsetStrip], 3)
        XCTAssertEqual(byColor[.hotZone], 3)
        XCTAssertEqual(byColor[.goldRush], 3)
        XCTAssertEqual(byColor[.emeraldQuarter], 3)
        XCTAssertEqual(byColor[.blueChip], 2)
        XCTAssertEqual(byColor[.transitLine], 4)
        XCTAssertEqual(byColor[.powerAndWater], 2)
    }

    // MARK: - Wild Property Cards

    func testDeckHas11WildPropertyCards() {
        XCTAssertEqual(stats.wildPropertyCount, 11, "Wild property cards should be 11, got \(stats.wildPropertyCount)")
    }

    // MARK: - Rent Cards

    func testDeckHas10TwoColorRentCards() {
        XCTAssertEqual(stats.rentCount, 10, "Two-color rent cards should be 10, got \(stats.rentCount)")
    }

    func testDeckHas3WildRentCards() {
        XCTAssertEqual(stats.wildRentCount, 3, "Wild rent cards should be 3, got \(stats.wildRentCount)")
    }

    // MARK: - Action Cards

    func testDeckHas38ActionCards() {
        XCTAssertEqual(stats.actionCount, 38, "Action cards should be 38, got \(stats.actionCount)")
    }

    func testActionCardCounts() {
        XCTAssertEqual(stats.actionCounts[.dealForward], 10)
        XCTAssertEqual(stats.actionCounts[.dealSnatcher], 3)
        XCTAssertEqual(stats.actionCounts[.noDeal], 5)
        XCTAssertEqual(stats.actionCounts[.quickGrab], 3)
        XCTAssertEqual(stats.actionCounts[.swapIt], 3)
        XCTAssertEqual(stats.actionCounts[.collectNow], 3)
        XCTAssertEqual(stats.actionCounts[.bigSpender], 3)
        XCTAssertEqual(stats.actionCounts[.doubleUp], 2)
        XCTAssertEqual(stats.actionCounts[.cornerStore], 3)
        XCTAssertEqual(stats.actionCounts[.apartmentBuilding], 3)
    }

    // MARK: - Card Integrity

    func testNoDuplicateCardIds() {
        let ids = deck.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All card IDs must be unique")
    }

    func testAllAssetKeysNonEmpty() {
        for card in deck {
            XCTAssertFalse(card.assetKey.isEmpty, "Card \(card.name) has an empty asset key")
        }
    }

    func testAllAssetKeysUnique() {
        let keys = deck.map { $0.assetKey }
        let uniqueKeys = Set(keys)
        XCTAssertEqual(keys.count, uniqueKeys.count, "All asset keys must be unique")
    }

    func testAllCardNamesNonEmpty() {
        for card in deck {
            XCTAssertFalse(card.name.isEmpty, "Card type \(card.type) has an empty name")
        }
    }

    func testAllMonetaryValuesPositive() {
        for card in deck {
            XCTAssertGreaterThan(card.monetaryValue, 0, "Card \(card.name) has non-positive monetaryValue")
        }
    }

    // MARK: - Deck Math

    func testDeckCountsAddUp() {
        let total = stats.moneyCount + stats.propertyCount + stats.wildPropertyCount
                  + stats.rentCount + stats.wildRentCount + stats.actionCount
        XCTAssertEqual(total, stats.total, "Card type counts should sum to \(stats.total)")
    }

    // MARK: - Wild Property Card Specifics

    func testWildPropertyHasExactlyNineTwoColorWilds() {
        let twoColorWilds = deck.filter {
            if case .wildProperty(let colors) = $0.type { return colors.count == 2 }
            return false
        }
        XCTAssertEqual(twoColorWilds.count, 9, "Should have exactly 9 two-color wild property cards")
    }

    func testWildPropertyHasExactlyTwoRainbowWilds() {
        let rainbowWilds = deck.filter {
            if case .wildProperty(let colors) = $0.type {
                // Rainbow wilds are built with PropertyColor.allCases (10 colors)
                return colors.count == PropertyColor.allCases.count
            }
            return false
        }
        XCTAssertEqual(rainbowWilds.count, 2, "Should have exactly 2 rainbow wild property cards")
    }

    func testTwoColorWildsHaveExactlyTwoColors() {
        for card in deck {
            if case .wildProperty(let colors) = card.type, colors.count != PropertyColor.allCases.count {
                XCTAssertEqual(colors.count, 2,
                               "Two-color wild '\(card.name)' should have exactly 2 colors, got \(colors.count)")
            }
        }
    }

    func testExpectedTwoColorWildPairsExist() {
        // Verify each specific color pairing exists (Monopoly Deal standard wilds).
        let wilds = deck.compactMap { card -> Set<PropertyColor>? in
            if case .wildProperty(let colors) = card.type, colors.count == 2 {
                return Set(colors)
            }
            return nil
        }

        let expectedPairs: [Set<PropertyColor>] = [
            [.rustDistrict, .transitLine],
            [.skylineAve, .transitLine],
            [.powerAndWater, .transitLine],
            [.emeraldQuarter, .blueChip],
            [.emeraldQuarter, .transitLine],
            [.hotZone, .goldRush],
            [.neonRow, .sunsetStrip],
            [.sunsetStrip, .hotZone],
        ]

        for pair in expectedPairs {
            XCTAssertTrue(wilds.contains(pair),
                          "Missing two-color wild for pair: \(pair.map { $0.rawValue }.sorted())")
        }
    }

    func testSkylineTransitLineWildHasTwoCopies() {
        // skylineAve+transitLine has two copies (both present in deck).
        let count = deck.filter {
            if case .wildProperty(let colors) = $0.type {
                return Set(colors) == Set([PropertyColor.skylineAve, .transitLine])
            }
            return false
        }.count
        XCTAssertEqual(count, 2, "skylineAve+transitLine wild should have 2 copies in the deck")
    }

    func testWildPropertyMonetaryValues() {
        // Two-color wilds: $1M; Rainbow wilds: $2M.
        for card in deck {
            guard case .wildProperty(let colors) = card.type else { continue }
            if colors.count == PropertyColor.allCases.count {
                XCTAssertEqual(card.monetaryValue, 2,
                               "Rainbow wild '\(card.name)' should have monetary value $2M")
            } else {
                XCTAssertEqual(card.monetaryValue, 1,
                               "Two-color wild '\(card.name)' should have monetary value $1M")
            }
        }
    }

    // MARK: - Rent Card Specifics

    func testExpectedRentPairsExist() {
        // Each of the 5 color pairs must appear with 2 copies in the deck.
        let rentColorSets = deck.compactMap { card -> Set<PropertyColor>? in
            if case .rent(let colors) = card.type { return Set(colors) }
            return nil
        }

        let expectedPairs: [Set<PropertyColor>] = [
            [.rustDistrict, .blueChip],
            [.skylineAve, .transitLine],
            [.neonRow, .sunsetStrip],
            [.hotZone, .goldRush],
            [.emeraldQuarter, .powerAndWater],
        ]

        for pair in expectedPairs {
            let count = rentColorSets.filter { $0 == pair }.count
            XCTAssertEqual(count, 2,
                           "Rent pair \(pair.map { $0.rawValue }.sorted()) should have exactly 2 copies, got \(count)")
        }
    }

    func testEveryPropertyColorCoveredByTwoColorRent() {
        // Every PropertyColor must appear in at least one two-color rent card
        // so players can always charge rent without relying solely on wild rent.
        var coveredColors = Set<PropertyColor>()
        for card in deck {
            if case .rent(let colors) = card.type {
                colors.forEach { coveredColors.insert($0) }
            }
        }
        for color in PropertyColor.allCases {
            XCTAssertTrue(coveredColors.contains(color),
                          "PropertyColor.\(color.rawValue) has no two-color rent card — it can only be charged with wild rent")
        }
    }

    func testRentCardMonetaryValue() {
        for card in deck {
            if case .rent = card.type {
                XCTAssertEqual(card.monetaryValue, 1,
                               "Two-color rent card '\(card.name)' should have monetary value $1M")
            }
        }
    }

    func testWildRentCardMonetaryValue() {
        for card in deck {
            if case .wildRent = card.type {
                XCTAssertEqual(card.monetaryValue, 1,
                               "Wild rent card '\(card.name)' should have monetary value $1M")
            }
        }
    }

    func testRentCardsHaveExactlyTwoColors() {
        for card in deck {
            if case .rent(let colors) = card.type {
                XCTAssertEqual(colors.count, 2,
                               "Two-color rent card '\(card.name)' must have exactly 2 colors, got \(colors.count)")
            }
        }
    }

    // MARK: - Property Card Values

    func testPropertyMonetaryValuesByColor() {
        // Expected monetary value per color per DeckBuilder spec.
        let expectedValues: [PropertyColor: Int] = [
            .rustDistrict:    1,
            .skylineAve:      1,
            .neonRow:         2,
            .sunsetStrip:     2,
            .hotZone:         3,
            .goldRush:        3,
            .emeraldQuarter:  4,
            .blueChip:        4,
            .transitLine:     2,
            .powerAndWater:   2,
        ]
        for card in deck {
            guard case .property(let color) = card.type else { continue }
            if let expected = expectedValues[color] {
                XCTAssertEqual(card.monetaryValue, expected,
                               "\(color.rawValue) property '\(card.name)' should be $\(expected)M, got $\(card.monetaryValue)M")
            }
        }
    }

    func testPropertyCardSetSizeMatchesColorDefinition() {
        // The number of property cards for each color must equal that color's setSize
        // so every set can be completed.
        let byColor: [PropertyColor: Int] = deck.reduce(into: [:]) { dict, card in
            if case .property(let color) = card.type { dict[color, default: 0] += 1 }
        }
        for color in PropertyColor.allCases {
            let count = byColor[color] ?? 0
            XCTAssertEqual(count, color.setSize,
                           "\(color.rawValue): deck has \(count) property cards but setSize is \(color.setSize)")
        }
    }

    // MARK: - Action Card Monetary Values

    func testActionCardMonetaryValues() {
        for card in deck {
            guard case .action(let type) = card.type else { continue }
            let expected: Int
            switch type {
            case .cornerStore, .apartmentBuilding: expected = 3
            case .dealSnatcher:                    expected = 5
            default:                               expected = 2
            }
            XCTAssertEqual(card.monetaryValue, expected,
                           "Action '\(type.rawValue)' should be $\(expected)M, got $\(card.monetaryValue)M")
        }
    }

    func testAllActionTypesHaveAtLeastOneCard() {
        // Guards against adding a new ActionType to the enum without adding it to the deck.
        let presentTypes = Set(deck.compactMap { card -> ActionType? in
            if case .action(let t) = card.type { return t }
            return nil
        })
        for actionType in ActionType.allCases {
            XCTAssertTrue(presentTypes.contains(actionType),
                          "ActionType.\(actionType.rawValue) has no cards in the deck")
        }
    }

    // MARK: - Shuffle / Randomness

    func testDeckIsShuffled_MultipleBuildsHaveDifferentOrders() {
        // Build 3 decks — their card-ID orderings should not all be identical.
        // The probability of any two 110-card decks being in the same order by chance
        // is 1/110! ≈ 0, so any collision is a determinism bug.
        let deck1 = DeckBuilder.buildDeck().map { $0.assetKey }
        let deck2 = DeckBuilder.buildDeck().map { $0.assetKey }
        let deck3 = DeckBuilder.buildDeck().map { $0.assetKey }

        let allSame = (deck1 == deck2) && (deck2 == deck3)
        XCTAssertFalse(allSame, "Three separately built decks should not all have the same card order")
    }

    func testDeckShufflePreservesAllCards() {
        // Shuffling changes order but must not add, drop, or duplicate any card.
        let sortedOriginal = deck.map { $0.assetKey }.sorted()
        let rebuilt = DeckBuilder.buildDeck()
        // Compare sorted asset keys — same multiset of cards, potentially different order.
        let sortedRebuilt = rebuilt.map { $0.assetKey }.sorted()
        XCTAssertEqual(sortedOriginal, sortedRebuilt,
                       "Shuffled deck must contain the same cards as any other build (same composition)")
    }

    func testConsistentCompositionAcrossMultipleBuilds() {
        // Deck composition (counts per type) must be deterministic regardless of shuffle.
        for _ in 0..<5 {
            let fresh = DeckBuilder.buildDeck()
            let s = DeckBuilder.stats(for: fresh)
            XCTAssertEqual(s.total, 110)
            XCTAssertEqual(s.moneyCount, 20)
            XCTAssertEqual(s.propertyCount, 28)
            XCTAssertEqual(s.wildPropertyCount, 11)
            XCTAssertEqual(s.rentCount, 10)
            XCTAssertEqual(s.wildRentCount, 3)
            XCTAssertEqual(s.actionCount, 38)
        }
    }

    func testShuffledDeckHasUniqueIds() {
        // A bug in buildDeck could cause UUIDs to be re-used across builds if
        // cards are cached instead of freshly constructed.
        let deck1 = DeckBuilder.buildDeck()
        let deck2 = DeckBuilder.buildDeck()
        let allIds = (deck1 + deck2).map { $0.id }
        XCTAssertEqual(allIds.count, Set(allIds).count,
                       "Each buildDeck() call must create fresh UUIDs — no ID shared across builds")
    }

    // MARK: - Color Coverage / Completeness

    func testAllPropertyColorsRepresented() {
        let colorsInDeck = Set(deck.compactMap { card -> PropertyColor? in
            if case .property(let color) = card.type { return color }
            return nil
        })
        for color in PropertyColor.allCases {
            XCTAssertTrue(colorsInDeck.contains(color),
                          "PropertyColor.\(color.rawValue) has no property cards in the deck")
        }
    }

    func testNoUnknownPropertyColors() {
        // Every property card color must be a known PropertyColor case.
        for card in deck {
            if case .property(let color) = card.type {
                XCTAssertTrue(PropertyColor.allCases.contains(color),
                              "Property card '\(card.name)' has unexpected color '\(color.rawValue)'")
            }
        }
    }
}
