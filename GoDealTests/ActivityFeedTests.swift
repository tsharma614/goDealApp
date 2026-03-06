import XCTest
@testable import GoDeal

// MARK: - Activity Feed Tests
//
// Covers GameLogger feed mechanics (max-8, ordering, clear, set) and
// every game action that writes to the feed via GameEngine.

final class ActivityFeedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        GameLogger.shared.clearActivity()
    }

    // MARK: - Helpers

    func makeEngine(playerCount: Int = 2) -> GameEngine {
        var players = [Player(name: "Alice", isHuman: true)]
        for i in 1..<playerCount {
            players.append(Player(name: "CPU \(i)", isHuman: false))
        }
        var state = GameState(players: players, deck: DeckBuilder.buildDeck())
        state.currentPlayerIndex = 0  // pin for deterministic tests
        return GameEngine(state: state)
    }

    func makeCard(type: CardType, value: Int = 1) -> Card {
        Card(id: UUID(), type: type, name: "TestCard", description: "",
             monetaryValue: value, assetKey: "test_\(UUID())")
    }

    func makeCompleteSet(color: PropertyColor) -> PropertySet {
        var set = PropertySet(color: color, properties: [])
        for _ in 0..<color.setSize {
            set.addProperty(makeCard(type: .property(color), value: 2))
        }
        return set
    }

    // MARK: - GameLogger Feed Mechanics

    func testFeedStartsEmpty() {
        XCTAssertTrue(GameLogger.shared.activityFeed.isEmpty)
    }

    func testFeedIsNewestFirst() {
        GameLogger.shared.addActivity("first")
        GameLogger.shared.addActivity("second")
        XCTAssertEqual(GameLogger.shared.activityFeed[0], "second")
        XCTAssertEqual(GameLogger.shared.activityFeed[1], "first")
    }

    func testFeedMaxEightEntries() {
        for i in 1...9 {
            GameLogger.shared.addActivity("entry \(i)")
        }
        XCTAssertEqual(GameLogger.shared.activityFeed.count, 8, "Feed must cap at 8 entries")
        XCTAssertEqual(GameLogger.shared.activityFeed[0], "entry 9", "Newest entry should be first")
        XCTAssertFalse(GameLogger.shared.activityFeed.contains("entry 1"), "Oldest entry should be evicted")
    }

    func testFeedMaxEnforced_ExactlyEight() {
        for i in 1...8 { GameLogger.shared.addActivity("e\(i)") }
        XCTAssertEqual(GameLogger.shared.activityFeed.count, 8)
    }

    func testFeedMaxEnforced_ManyOver() {
        for i in 1...30 { GameLogger.shared.addActivity("e\(i)") }
        XCTAssertEqual(GameLogger.shared.activityFeed.count, 8)
        XCTAssertEqual(GameLogger.shared.activityFeed[0], "e30")
    }

    func testClearResetsToEmpty() {
        GameLogger.shared.addActivity("something")
        GameLogger.shared.clearActivity()
        XCTAssertTrue(GameLogger.shared.activityFeed.isEmpty)
    }

    func testClearAlreadyEmptyIsSafe() {
        // Should not crash
        GameLogger.shared.clearActivity()
        GameLogger.shared.clearActivity()
        XCTAssertTrue(GameLogger.shared.activityFeed.isEmpty)
    }

    func testSetActivityFeedReplacesSingle() {
        GameLogger.shared.addActivity("old")
        GameLogger.shared.setActivityFeed(["new a", "new b"])
        XCTAssertEqual(GameLogger.shared.activityFeed.count, 2)
        XCTAssertEqual(GameLogger.shared.activityFeed, ["new a", "new b"])
    }

    func testSetActivityFeedWithEmptyArrayClearsAll() {
        GameLogger.shared.addActivity("something")
        GameLogger.shared.setActivityFeed([])
        XCTAssertTrue(GameLogger.shared.activityFeed.isEmpty)
    }

    func testSetActivityFeedPreservesOrder() {
        // Simulates multiplayer guest receiving a snapshot from the host.
        let snapshot = ["latest", "middle", "oldest"]
        GameLogger.shared.setActivityFeed(snapshot)
        XCTAssertEqual(GameLogger.shared.activityFeed, snapshot,
                       "setActivityFeed must preserve the exact order it receives")
    }

    // MARK: - Draw Activity

    func testDrawTwoCardsAddsActivity() {
        let engine = makeEngine()
        engine.state.players[0].addToHand(makeCard(type: .money(1))) // non-empty → draw 2
        engine.startTurn()
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("Alice") && $0.contains("drew") }),
                      "Draw should add an activity entry")
    }

    func testDrawFiveCardsShowsCountInFeed() {
        let engine = makeEngine()
        engine.state.players[0].hand = []  // empty hand → draws 5
        engine.startTurn()
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("5") && $0.contains("drew") }),
                      "Drawing 5 cards should mention 5 in the activity entry")
    }

    func testDrawTwoCardsShowsCountInFeed() {
        let engine = makeEngine()
        engine.state.players[0].addToHand(makeCard(type: .money(1)))  // non-empty → draw 2
        engine.startTurn()
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("2") && $0.contains("drew") }),
                      "Drawing 2 cards should mention 2 in the activity entry")
    }

    // MARK: - Bank Activity

    func testBankMoneyAddsActivity() {
        let engine = makeEngine()
        engine.startTurn()
        let moneyCard = makeCard(type: .money(3), value: 3)
        engine.state.players[0].addToHand(moneyCard)
        engine.playCard(cardId: moneyCard.id, as: .bank)
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("banked") && $0.contains("Alice") }),
                      "Banking money should appear in the feed")
    }

    func testBankMoneyIncludesAmount() {
        let engine = makeEngine()
        engine.startTurn()
        let moneyCard = makeCard(type: .money(5), value: 5)
        engine.state.players[0].addToHand(moneyCard)
        engine.playCard(cardId: moneyCard.id, as: .bank)
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("5") }),
                      "Bank entry should include the dollar amount")
    }

    // MARK: - Property Activity

    func testPlayPropertyAddsActivityWithArrow() {
        let engine = makeEngine()
        engine.startTurn()
        let propCard = makeCard(type: .property(.blueChip))
        engine.state.players[0].addToHand(propCard)
        engine.playCard(cardId: propCard.id, as: .property(.blueChip))
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("Alice") && $0.contains("→") }),
                      "Playing a property should add an arrow entry")
    }

    func testRegularPropertyNeverShowsRainbow() {
        let engine = makeEngine()
        engine.startTurn()
        let propCard = makeCard(type: .property(.rustDistrict))
        engine.state.players[0].addToHand(propCard)
        engine.playCard(cardId: propCard.id, as: .property(.rustDistrict))
        let feed = GameLogger.shared.activityFeed
        XCTAssertFalse(feed.contains(where: { $0.contains("🌈") }),
                       "Regular property should not show the rainbow emoji")
    }

    // MARK: - Wild Property Activity

    func testAssignTwoColorWildAddsRainbowEmoji() {
        let engine = makeEngine()
        engine.startTurn()
        let wildCard = Card(id: UUID(),
                            type: .wildProperty([.rustDistrict, .blueChip]),
                            name: "Wild", description: "", monetaryValue: 1, assetKey: "wild_test")
        engine.state.players[0].addToHand(wildCard)
        engine.assignWildColor(cardId: wildCard.id, color: .rustDistrict)
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("🌈") && $0.contains("Alice") }),
                      "Wild property should show the 🌈 emoji in the activity feed")
    }

    func testAssignRainbowWild_EmptyColors_AddsRainbowEmoji() {
        let engine = makeEngine()
        engine.startTurn()
        let rainbowCard = Card(id: UUID(),
                               type: .wildProperty([]),  // empty array = rainbow (all colors)
                               name: "Rainbow Wild", description: "", monetaryValue: 1,
                               assetKey: "rainbow_test")
        engine.state.players[0].addToHand(rainbowCard)
        engine.assignWildColor(cardId: rainbowCard.id, color: .emeraldQuarter)
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("🌈") }),
                      "Rainbow wild (empty colors) should also show 🌈")
    }

    func testWildNotPlacedAfterThreeCardLimit() {
        // Edge case: wild should not be placed or added to feed if card limit reached.
        let engine = makeEngine()
        engine.startTurn()
        for _ in 0..<3 {
            let m = makeCard(type: .money(1))
            engine.state.players[0].addToHand(m)
            engine.playCard(cardId: m.id, as: .bank)
        }
        XCTAssertFalse(engine.state.canPlayCard)
        GameLogger.shared.clearActivity()  // reset to isolate this assertion

        let wildCard = Card(id: UUID(), type: .wildProperty([.rustDistrict, .blueChip]),
                            name: "Wild", description: "", monetaryValue: 1, assetKey: "wild_limit")
        engine.state.players[0].addToHand(wildCard)
        engine.assignWildColor(cardId: wildCard.id, color: .rustDistrict)

        // Feed should still be empty — wild was rejected
        XCTAssertTrue(GameLogger.shared.activityFeed.isEmpty,
                      "Wild rejected by card-limit should not appear in activity feed")
    }

    // MARK: - Action Activity

    func testPlayActionAddsActivity() {
        let engine = makeEngine()
        engine.startTurn()
        let dealFwd = makeCard(type: .action(.dealForward))
        engine.state.players[0].addToHand(dealFwd)
        engine.playCard(cardId: dealFwd.id, as: .action)
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("Alice") }),
                      "Playing an action card should add an activity entry for the player")
    }

    // MARK: - Rent Activity

    func testPlayRentAddsCollectingActivity() {
        let engine = makeEngine()
        engine.startTurn()
        // Place a property so rent is valid, then add a matching rent card.
        let propCard = makeCard(type: .property(.blueChip))
        engine.state.players[0].placeProperty(propCard, in: .blueChip)
        let rentCard = makeCard(type: .rent([.blueChip, .emeraldQuarter]))
        engine.state.players[0].addToHand(rentCard)
        engine.playCard(cardId: rentCard.id, as: .rent(.blueChip))
        let feed = GameLogger.shared.activityFeed
        XCTAssertTrue(feed.contains(where: { $0.contains("collecting rent") && $0.contains("Alice") }),
                      "Rent play should add 'collecting rent' to the feed")
    }

    // MARK: - Feed Persistence Across Turns

    func testFeedGrowsAcrossMultipleTurns() {
        let engine = makeEngine()
        // Turn 1: player 0 draws
        engine.state.players[0].addToHand(makeCard(type: .money(1)))
        engine.startTurn()
        let countAfterTurn1 = GameLogger.shared.activityFeed.count

        // End turn + start turn 2 (player 1 draws)
        engine.endTurn()
        engine.state.players[1].addToHand(makeCard(type: .money(1)))
        engine.startTurn()
        let countAfterTurn2 = GameLogger.shared.activityFeed.count

        XCTAssertGreaterThan(countAfterTurn2, countAfterTurn1,
                             "Activity feed should grow across turns")
    }

    func testFeedNeverExceedsEightAcrossLongGame() {
        let engine = makeEngine()
        // Simulate several turns with actions to push many entries
        for _ in 0..<5 {
            engine.state.players[0].addToHand(makeCard(type: .money(1)))
            engine.startTurn()
            for _ in 0..<3 {
                let m = makeCard(type: .money(1))
                engine.state.players[0].addToHand(m)
                if engine.state.canPlayCard { engine.playCard(cardId: m.id, as: .bank) }
            }
            engine.endTurn()
            engine.state.players[1].addToHand(makeCard(type: .money(1)))
            engine.startTurn()
            engine.endTurn()
        }
        XCTAssertLessThanOrEqual(GameLogger.shared.activityFeed.count, 8,
                                 "Feed must never exceed 8 entries")
    }
}
