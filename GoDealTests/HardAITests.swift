import XCTest
@testable import GoDeal

// MARK: - Hard AI Strategy Tests
//
// Covers edge cases in AIStrategy for .hard difficulty:
//   - Target selection (hunts the player closest to winning)
//   - Offensive Deal Snatcher use
//   - Double Up only played when rent is also in hand
//   - shouldPlayNoDeal differences between easy / medium / hard

final class HardAITests: XCTestCase {

    // MARK: - Helpers

    func makeState(playerCount: Int = 3) -> GameState {
        let players = (0..<playerCount).map { i in
            Player(name: "P\(i)", isHuman: i == 0)
        }
        var state = GameState(players: players, deck: DeckBuilder.buildDeck())
        state.phase = .playing
        state.cardsPlayedThisTurn = 0
        state.currentPlayerIndex = 0
        return state
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

    func makeNoDealCard() -> Card {
        makeCard(type: .action(.noDeal))
    }

    // MARK: - Leader Targeting

    func testHardTargetsLeaderWithDealSnatcher_TwoOpponents() {
        // P0 (hard CPU), P1 has 2 complete sets (leader), P2 has 0 sets.
        // Hard should Deal Snatcher P1, not P2.
        var state = makeState(playerCount: 3)
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[1].properties[.blueChip]     = makeCompleteSet(color: .blueChip)
        // P2 has nothing

        let snatcher = makeCard(type: .action(.dealSnatcher))
        state.players[0].addToHand(snatcher)

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertNotNil(decision, "Hard CPU should make a play")
        XCTAssertEqual(decision?.card.id, snatcher.id, "Should play Deal Snatcher")
        XCTAssertEqual(decision?.targetPlayerIndex, 1,
                       "Should target P1 (the leader with 2 complete sets), not P2")
    }

    func testHardTargetsCorrectLeader_WhenLeaderIsNotFirst() {
        // P0 (hard CPU), P1 has 1 set, P2 has 2 sets (the real leader).
        // Hard should Deal Snatcher P2, not P1.
        var state = makeState(playerCount: 3)
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[2].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[2].properties[.blueChip]     = makeCompleteSet(color: .blueChip)

        let snatcher = makeCard(type: .action(.dealSnatcher))
        state.players[0].addToHand(snatcher)

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertEqual(decision?.targetPlayerIndex, 2,
                       "Should target P2 (the real leader with 2 sets), not P1")
    }

    func testHardDoesNotDealSnatcterWhenLeaderHasOnlyOneSet() {
        // Leader blocker only fires at 2+ sets. With 1 set, hard should not use snatcher offensively.
        var state = makeState(playerCount: 3)
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict) // only 1

        let snatcher = makeCard(type: .action(.dealSnatcher))
        let moneyCard = makeCard(type: .money(3), value: 3)
        state.players[0].addToHand(snatcher)
        state.players[0].addToHand(moneyCard)

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        // Should not snatch — the defensive block threshold is 2+ sets.
        // May still bank money or make another play.
        if let d = decision, d.card.id == snatcher.id {
            // If it did choose snatcher, it must be because step 1 (win condition) fired,
            // which requires CPU itself to have 2 sets. CPU has 0, so this should NOT happen.
            XCTFail("Hard should not use Deal Snatcher offensively when leader has < 2 sets")
        }
    }

    func testHardDoesNotUseAbsentSnatcher() {
        // No Deal Snatcher in hand — hard must not crash and should still make a play.
        var state = makeState(playerCount: 3)
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[1].properties[.blueChip]     = makeCompleteSet(color: .blueChip)
        let moneyCard = makeCard(type: .money(2), value: 2)
        state.players[0].addToHand(moneyCard)

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertNotNil(decision, "Hard should still play something without a Deal Snatcher")
        if let d = decision {
            guard case .bank = d.destination else {
                XCTFail("Expected bank destination, got \(d.destination)")
                return
            }
        }
    }

    // MARK: - Double Up Logic

    func testHardPlaysDoubleUpOnlyWhenRentIsAvailable() {
        var state = makeState(playerCount: 2)
        // Give CPU a property set so rent is meaningful
        let propCard = makeCard(type: .property(.blueChip))
        state.players[0].placeProperty(propCard, in: .blueChip)

        let doubleUp = makeCard(type: .action(.doubleUp))
        let rentCard = makeCard(type: .rent([.blueChip, .emeraldQuarter]))
        state.players[0].addToHand(doubleUp)
        state.players[0].addToHand(rentCard)

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.card.id, doubleUp.id,
                       "Hard should play Double Up first when rent is also in hand")
    }

    func testHardDoesNotPlayDoubleUpWithoutRentInHand() {
        var state = makeState(playerCount: 2)
        let propCard = makeCard(type: .property(.blueChip))
        state.players[0].placeProperty(propCard, in: .blueChip)

        let doubleUp = makeCard(type: .action(.doubleUp))
        let moneyCard = makeCard(type: .money(2), value: 2)
        state.players[0].addToHand(doubleUp)
        state.players[0].addToHand(moneyCard)
        // No rent card in hand

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertNotNil(decision)
        XCTAssertNotEqual(decision?.card.id, doubleUp.id,
                          "Hard should NOT play Double Up when no rent is available")
    }

    func testHardDoesNotPlayDoubleUpWithoutProperties() {
        var state = makeState(playerCount: 2)
        // No properties placed — Double Up before rent is pointless
        let doubleUp = makeCard(type: .action(.doubleUp))
        let rentCard = makeCard(type: .rent([.blueChip, .emeraldQuarter]))
        let moneyCard = makeCard(type: .money(1), value: 1)
        state.players[0].addToHand(doubleUp)
        state.players[0].addToHand(rentCard)
        state.players[0].addToHand(moneyCard)

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertNotNil(decision)
        XCTAssertNotEqual(decision?.card.id, doubleUp.id,
                          "Hard should not play Double Up when CPU owns no properties")
    }

    // MARK: - Offensive Steal

    func testHardPlaysOffensiveQuickGrabAgainstLeader() {
        // Hard should Quick Grab the leader's property even when it doesn't complete our own set.
        var state = makeState(playerCount: 3)
        // P1 is the leader (2 sets) and has an incomplete third set
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[1].properties[.blueChip]     = makeCompleteSet(color: .blueChip)
        var partialHotZone = PropertySet(color: .hotZone, properties: [])
        partialHotZone.addProperty(makeCard(type: .property(.hotZone)))
        state.players[1].properties[.hotZone] = partialHotZone

        let grabCard = makeCard(type: .action(.quickGrab))
        let moneyCard = makeCard(type: .money(1), value: 1)
        state.players[0].addToHand(grabCard)
        state.players[0].addToHand(moneyCard)
        // CPU (P0) has no matching hotZone properties, so this does not complete our set.

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertNotNil(decision)
        // Hard mode should still play it offensively against the leader
        XCTAssertEqual(decision?.card.id, grabCard.id,
                       "Hard should play Quick Grab offensively against the leader")
        XCTAssertEqual(decision?.targetPlayerIndex, 1,
                       "Offensive steal should target the leader")
    }

    // MARK: - shouldPlayNoDeal Differences

    func testHardNoDeal_BlocksQuickGrabEvenWithOneProperty() {
        // Hard blocks quickGrab when target has any property.
        // Medium would NOT block unless near-complete.
        var state = makeState(playerCount: 2)
        var partial = PropertySet(color: .hotZone, properties: [])
        partial.addProperty(makeCard(type: .property(.hotZone)))  // just 1 out of 3
        state.players[0].properties[.hotZone] = partial
        // Not near-complete for medium (hotZone needs 3, have 1 — not >= setSize - 1 = 2)

        let noDeal = makeNoDealCard()
        state.players[0].addToHand(noDeal)
        let attackCard = makeCard(type: .action(.quickGrab))

        let hardResult = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .hard)
        let mediumResult = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .medium)

        XCTAssertNotNil(hardResult, "Hard should block Quick Grab even with 1 property")
        XCTAssertNil(mediumResult, "Medium should NOT block — property count (1) < setSize-1 (2)")
    }

    func testHardNoDeal_BlocksSwapItWithAnyProperties() {
        // Hard blocks swapIt whenever properties exist; medium only when a complete set exists.
        var state = makeState(playerCount: 2)
        var incomplete = PropertySet(color: .hotZone, properties: [])
        incomplete.addProperty(makeCard(type: .property(.hotZone)))
        state.players[0].properties[.hotZone] = incomplete  // incomplete, no complete sets

        let noDeal = makeNoDealCard()
        state.players[0].addToHand(noDeal)
        let attackCard = makeCard(type: .action(.swapIt))

        let hardResult = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .hard)
        let mediumResult = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .medium)

        XCTAssertNotNil(hardResult, "Hard should block Swap It to protect any property")
        XCTAssertNil(mediumResult, "Medium only blocks Swap It when a complete set is at stake")
    }

    func testHardNoDeal_BlocksCollectNowWithSomeMoney() {
        // Hard blocks CollectNow when bankTotal > 1.
        // Medium only blocks when bankTotal < 2.
        var state = makeState(playerCount: 2)
        let moneyCard = makeCard(type: .money(3), value: 3)
        state.players[0].bank = [moneyCard]  // bankTotal = 3

        let noDeal = makeNoDealCard()
        state.players[0].addToHand(noDeal)
        let attackCard = makeCard(type: .action(.collectNow))

        let hardResult = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .hard)
        let mediumResult = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .medium)

        XCTAssertNotNil(hardResult, "Hard should block CollectNow when bankTotal > 1")
        XCTAssertNil(mediumResult, "Medium doesn't protect when bankTotal >= 2")
    }

    func testHardNoDeal_DoesNotBlockCollectNowWithNoMoney() {
        // Hard still won't play NoDeal when there's nothing to protect.
        var state = makeState(playerCount: 2)
        state.players[0].bank = []  // bankTotal = 0

        let noDeal = makeNoDealCard()
        state.players[0].addToHand(noDeal)
        let attackCard = makeCard(type: .action(.collectNow))

        let result = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .hard)
        XCTAssertNil(result, "Hard should not waste NoDeal when bank is empty")
    }

    func testHardNoDeal_AlwaysBlocksDealSnatcterOnCompleteSet() {
        // Both medium and hard should block DealSnatcher when we have a complete set.
        var state = makeState(playerCount: 2)
        state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)

        let noDeal = makeNoDealCard()
        state.players[0].addToHand(noDeal)
        let attackCard = makeCard(type: .action(.dealSnatcher))

        let hardResult = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .hard)
        let mediumResult = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .medium)

        XCTAssertNotNil(hardResult, "Hard should block Deal Snatcher on complete set")
        XCTAssertNotNil(mediumResult, "Medium should also block Deal Snatcher on complete set")
    }

    func testEasyNoDeal_NeverBlocksWithEmptyHand() {
        // Easy AI has no No Deal card → returns nil regardless.
        var state = makeState(playerCount: 2)
        state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        let attackCard = makeCard(type: .action(.dealSnatcher))

        let result = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 0, actionCard: attackCard, difficulty: .easy)
        XCTAssertNil(result, "Should return nil when no NoDeal card in hand")
    }

    // MARK: - Hard Returns nil When No Valid Plays

    func testHardReturnsNilWhenCardLimitReached() {
        var state = makeState(playerCount: 2)
        state.cardsPlayedThisTurn = 3   // already at limit → canPlayCard = false

        let snatcher = makeCard(type: .action(.dealSnatcher))
        state.players[0].addToHand(snatcher)

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertNil(decision, "Hard should return nil when card limit is reached")
    }

    func testHardReturnsNilWhenHandIsEmpty() {
        var state = makeState(playerCount: 2)
        state.players[0].hand = []

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertNil(decision, "Hard should return nil when hand is empty")
    }
}
