import XCTest
@testable import GoDeal

final class WinCheckerTests: XCTestCase {

    // MARK: - Helpers

    func makeGameState(playerCount: Int = 2) -> GameState {
        let players = (0..<playerCount).map { i in
            Player(name: "Player \(i+1)", isHuman: i == 0)
        }
        let deck = DeckBuilder.buildDeck()
        return GameState(players: players, deck: deck)
    }

    func makeCompleteSet(color: PropertyColor) -> PropertySet {
        var set = PropertySet(color: color, properties: [])
        let cards: [Card] = (0..<color.setSize).map { i in
            Card(
                id: UUID(),
                type: .property(color),
                name: "Test \(color.rawValue) \(i)",
                description: "",
                monetaryValue: 1,
                assetKey: "test_\(color.rawValue)_\(i)"
            )
        }
        for card in cards { set.addProperty(card) }
        return set
    }

    // MARK: - No Win Conditions

    func testNoWinWithNoSets() {
        var state = makeGameState()
        XCTAssertNil(WinChecker.check(state))
    }

    func testNoWinWithTwoCompleteSets() {
        var state = makeGameState()
        state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        XCTAssertEqual(state.players[0].completedSets, 2)
        XCTAssertNil(WinChecker.check(state))
    }

    func testNoWinWithIncompleteThirdSet() {
        var state = makeGameState()
        state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        // Partial third set
        var partial = PropertySet(color: .hotZone, properties: [])
        partial.addProperty(Card(id: UUID(), type: .property(.hotZone), name: "Test", description: "", monetaryValue: 1, assetKey: "test_hz"))
        state.players[0].properties[.hotZone] = partial
        XCTAssertEqual(state.players[0].completedSets, 2)
        XCTAssertNil(WinChecker.check(state))
    }

    // MARK: - Win Conditions

    func testWinWithThreeCompleteSets() {
        var state = makeGameState()
        state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[0].properties[.hotZone] = makeCompleteSet(color: .hotZone)
        XCTAssertEqual(WinChecker.check(state), 0, "Player 0 should win with 3 complete sets")
    }

    func testWinWithMoreThanThreeCompleteSets() {
        var state = makeGameState()
        state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[0].properties[.hotZone] = makeCompleteSet(color: .hotZone)
        state.players[0].properties[.goldRush] = makeCompleteSet(color: .goldRush)
        XCTAssertEqual(WinChecker.check(state), 0)
    }

    func testWinReturnsCorrectPlayerIndex() {
        var state = makeGameState(playerCount: 2)
        // Player 1 (index 1) wins
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[1].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[1].properties[.hotZone] = makeCompleteSet(color: .hotZone)
        XCTAssertEqual(WinChecker.check(state), 1, "Player 1 should win")
    }

    // MARK: - Complete Set with Improvements

    func testCompleteSetWithCornerStoreCountsAsOne() {
        var state = makeGameState()
        var rustSet = makeCompleteSet(color: .rustDistrict)
        rustSet.hasCornerStore = true
        state.players[0].properties[.rustDistrict] = rustSet
        state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[0].properties[.hotZone] = makeCompleteSet(color: .hotZone)
        XCTAssertEqual(state.players[0].completedSets, 3)
        XCTAssertEqual(WinChecker.check(state), 0)
    }

    func testCompleteSetWithTowerBlockCountsAsOne() {
        var state = makeGameState()
        var rustSet = makeCompleteSet(color: .rustDistrict)
        rustSet.hasCornerStore = true
        rustSet.hasApartmentBuilding = true
        state.players[0].properties[.rustDistrict] = rustSet
        state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[0].properties[.hotZone] = makeCompleteSet(color: .hotZone)
        XCTAssertEqual(state.players[0].completedSets, 3)
        XCTAssertEqual(WinChecker.check(state), 0)
    }

    // MARK: - playerWins helper

    func testPlayerWinsHelper() {
        var player = Player(name: "Test", isHuman: true)
        XCTAssertFalse(WinChecker.playerWins(player))

        player.properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        player.properties[.blueChip] = makeCompleteSet(color: .blueChip)
        player.properties[.hotZone] = makeCompleteSet(color: .hotZone)

        XCTAssertTrue(WinChecker.playerWins(player))
    }

    // MARK: - Rent Calculations

    func testPropertySetRent() {
        // Rust District: 2 cards, full set = $3M (rentTable[2]=3)
        var set = makeCompleteSet(color: .rustDistrict)
        XCTAssertEqual(set.currentRent, 3)

        // With corner store: rentTable[3] = 6
        set.hasCornerStore = true
        XCTAssertEqual(set.currentRent, 6)

        // With apartment building: rentTable[4] = 10
        set.hasApartmentBuilding = true
        XCTAssertEqual(set.currentRent, 10)
    }

    func testPartialSetRent() {
        var set = PropertySet(color: .hotZone, properties: [])
        // No properties = 0 rent
        XCTAssertEqual(set.currentRent, 0)

        // 1 property
        set.addProperty(Card(id: UUID(), type: .property(.hotZone), name: "T", description: "", monetaryValue: 3, assetKey: "t1"))
        XCTAssertEqual(set.currentRent, PropertyColor.hotZone.rentTable[0])

        // 2 properties
        set.addProperty(Card(id: UUID(), type: .property(.hotZone), name: "T", description: "", monetaryValue: 3, assetKey: "t2"))
        XCTAssertEqual(set.currentRent, PropertyColor.hotZone.rentTable[1])
    }

    // MARK: - Transit Line rent (4-card set, rent table uses index 3 for full set)

    func testTransitLinePartialAndCompleteRent() {
        var set = PropertySet(color: .transitLine, properties: [])
        func addStation() {
            set.addProperty(Card(id: UUID(), type: .property(.transitLine), name: "Station", description: "", monetaryValue: 2, assetKey: "tr_\(UUID())"))
        }

        XCTAssertEqual(set.currentRent, 0, "No stations")
        addStation(); XCTAssertEqual(set.currentRent, 1, "1 station")
        addStation(); XCTAssertEqual(set.currentRent, 2, "2 stations")
        addStation(); XCTAssertEqual(set.currentRent, 3, "3 stations")
        addStation(); XCTAssertEqual(set.currentRent, 4, "4 stations (complete) should use table[3]=4, not table[2]=3")
    }

    // MARK: - Improvements stripped when set becomes incomplete

    func testImprovementsClearedOnPropertyRemoval() {
        var player = Player(name: "Test", isHuman: true)
        // Build a complete Blue Chip set with improvements
        var set = makeCompleteSet(color: .blueChip)
        set.hasCornerStore = true
        set.hasApartmentBuilding = true
        player.properties[.blueChip] = set

        XCTAssertTrue(player.properties[.blueChip]!.hasCornerStore)
        XCTAssertTrue(player.properties[.blueChip]!.hasApartmentBuilding)

        // Remove one card — set becomes incomplete
        let cardToRemove = player.properties[.blueChip]!.properties.first!.id
        _ = player.removeProperty(id: cardToRemove)

        XCTAssertFalse(player.properties[.blueChip]?.isComplete ?? true, "Set should be incomplete")
        XCTAssertFalse(player.properties[.blueChip]?.hasCornerStore ?? true, "Corner Store must be cleared")
        XCTAssertFalse(player.properties[.blueChip]?.hasApartmentBuilding ?? true, "Tower Block must be cleared")
    }

    func testImprovementsPreservedWhenSetRemainsComplete() {
        var player = Player(name: "Test", isHuman: true)
        // Build a hot zone set with an extra card (setSize=3, add 4 cards) + improvements
        var set = makeCompleteSet(color: .hotZone)
        let extra = Card(id: UUID(), type: .property(.hotZone), name: "Extra", description: "", monetaryValue: 2, assetKey: "extra")
        set.addProperty(extra)
        set.hasCornerStore = true
        player.properties[.hotZone] = set

        // Remove the extra card — set still has 3 cards (still complete)
        _ = player.removeProperty(id: extra.id)

        XCTAssertTrue(player.properties[.hotZone]?.isComplete ?? false, "Set should still be complete")
        XCTAssertTrue(player.properties[.hotZone]?.hasCornerStore ?? false, "Corner Store should be preserved")
    }

    // MARK: - WinChecker current-player priority

    func testWinCheckerPrioritizesCurrentPlayer() {
        var state = makeGameState(playerCount: 2)
        // Both players have 3 complete sets — current player should win
        state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[0].properties[.hotZone] = makeCompleteSet(color: .hotZone)
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[1].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[1].properties[.hotZone] = makeCompleteSet(color: .hotZone)

        // With currentPlayerIndex = 0, player 0 should win
        state = GameState(players: state.players, deck: DeckBuilder.buildDeck())
        state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[0].properties[.hotZone] = makeCompleteSet(color: .hotZone)
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[1].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[1].properties[.hotZone] = makeCompleteSet(color: .hotZone)
        // currentPlayerIndex defaults to 0
        XCTAssertEqual(WinChecker.check(state), 0, "Current player (0) should win in a tie")
    }
}
