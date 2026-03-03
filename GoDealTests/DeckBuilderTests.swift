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
}
