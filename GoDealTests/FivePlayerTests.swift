import XCTest
@testable import GoDeal

// MARK: - Five Player Tests
//
// Verifies that the game engine handles 5 players correctly:
// turn ordering, draw phases, win detection, and multi-target actions.

final class FivePlayerTests: XCTestCase {

    // MARK: - Helpers

    func makeEngine(playerCount: Int = 5) -> GameEngine {
        let players = (0..<playerCount).map { i in
            Player(name: "P\(i)", isHuman: i == 0)
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

    // MARK: - Initialization

    func testFivePlayerEngineInitializes() {
        let engine = makeEngine()
        XCTAssertEqual(engine.state.players.count, 5)
    }

    func testFivePlayerNamesAreDistinct() {
        let engine = makeEngine()
        let names = engine.state.players.map { $0.name }
        XCTAssertEqual(Set(names).count, 5, "All 5 player names must be distinct")
    }

    func testFivePlayerCurrentPlayerStartsAtZero() {
        let engine = makeEngine()
        XCTAssertEqual(engine.state.currentPlayerIndex, 0)
    }

    func testFivePlayerOtherIndicesReturns4() {
        let engine = makeEngine()
        engine.state.currentPlayerIndex = 0
        let others = engine.state.otherPlayerIndices()
        XCTAssertEqual(others.count, 4, "With 5 players, otherPlayerIndices should return 4 indices")
        XCTAssertFalse(others.contains(0), "otherPlayerIndices must not include the current player")
    }

    // MARK: - Turn Ordering

    func testFivePlayerTurnAdvancesThrough_AllFive() {
        let engine = makeEngine()
        var turnOrder: [Int] = []
        for _ in 0..<5 {
            engine.state.players[engine.state.currentPlayerIndex]
                .addToHand(makeCard(type: .money(1)))
            engine.startTurn()
            turnOrder.append(engine.state.currentPlayerIndex)
            engine.endTurn()
        }
        // After 5 endTurns from player 0, we should have visited all 5 players.
        XCTAssertEqual(Set(turnOrder).count, 5, "All 5 players should take a turn in 5 cycles")
    }

    func testFivePlayerTurnWrapsAroundCorrectly() {
        let engine = makeEngine()
        // Advance 5 times — should land back on player 0
        engine.state.currentPlayerIndex = 0
        for _ in 0..<5 {
            engine.state.players[engine.state.currentPlayerIndex]
                .addToHand(makeCard(type: .money(1)))
            engine.startTurn()
            engine.endTurn()
        }
        XCTAssertEqual(engine.state.currentPlayerIndex, 0,
                       "After 5 full turns, current player should wrap back to 0")
    }

    // MARK: - Draw Phase

    func testAllFivePlayersCanDrawCards() {
        let engine = makeEngine()
        for playerIndex in 0..<5 {
            engine.state.currentPlayerIndex = playerIndex
            let handBefore = engine.state.players[playerIndex].hand.count
            engine.state.players[playerIndex].addToHand(makeCard(type: .money(1))) // non-empty → draw 2
            engine.startTurn()
            XCTAssertGreaterThan(engine.state.players[playerIndex].hand.count, handBefore,
                                 "Player \(playerIndex) should draw cards at turn start")
        }
    }

    func testFivePlayerDrawPhaseMovesToPlaying() {
        let engine = makeEngine()
        engine.state.players[0].addToHand(makeCard(type: .money(1)))
        engine.startTurn()
        XCTAssertEqual(engine.state.phase, .playing)
    }

    // MARK: - Win Detection

    func testFivePlayerWinDetection_LastPlayer() {
        let engine = makeEngine()
        // Player 4 (last) wins with 3 complete sets
        engine.state.players[4].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        engine.state.players[4].properties[.blueChip]     = makeCompleteSet(color: .blueChip)
        engine.state.players[4].properties[.hotZone]      = makeCompleteSet(color: .hotZone)
        let winner = WinChecker.check(engine.state)
        XCTAssertEqual(winner, 4, "Player 4 should be detected as winner")
    }

    func testFivePlayerWinDetection_MiddlePlayer() {
        let engine = makeEngine()
        // Player 2 (middle) wins
        engine.state.players[2].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        engine.state.players[2].properties[.blueChip]     = makeCompleteSet(color: .blueChip)
        engine.state.players[2].properties[.hotZone]      = makeCompleteSet(color: .hotZone)
        let winner = WinChecker.check(engine.state)
        XCTAssertEqual(winner, 2, "Player 2 should be detected as winner")
    }

    func testFivePlayerNoWinner_AllWithTwoSets() {
        let engine = makeEngine()
        // All 5 players have 2 sets — nobody wins yet
        for i in 0..<5 {
            engine.state.players[i].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
            engine.state.players[i].properties[.blueChip]     = makeCompleteSet(color: .blueChip)
        }
        XCTAssertNil(WinChecker.check(engine.state), "No player should win with only 2 sets")
    }

    // MARK: - Big Spender in 5-Player Game

    func testFivePlayerBigSpenderChargesAllFourOpponents() {
        let engine = makeEngine()
        engine.startTurn()  // starts player 0's turn

        // Give all 4 opponents some money
        for i in 1..<5 {
            engine.state.players[i].bank = [makeCard(type: .money(2), value: 2)]
        }

        let bigSpenderCard = makeCard(type: .action(.bigSpender))

        // Queue opponents 2, 3, 4 for sequential responses; player 1 gets first window
        engine.state.pendingResponsePlayerIndices = [2, 3, 4]
        engine.state.phase = .awaitingResponse(
            targetPlayerIndex: 1,
            actionCard: bigSpenderCard,
            attackerIndex: 0
        )
        engine.state.currentPlayerIndex = 0

        // P1 accepts → charged, queue advances to P2
        engine.acceptAction()
        XCTAssertLessThan(engine.state.players[1].bankTotal, 2, "P1 should be charged")

        if case .awaitingResponse(let nextTarget, _, _) = engine.state.phase {
            XCTAssertEqual(nextTarget, 2, "Should advance to P2")
        } else {
            XCTFail("Expected awaitingResponse for P2, got \(engine.state.phase)")
        }

        // P2 accepts → charged, queue advances to P3
        engine.acceptAction()
        XCTAssertLessThan(engine.state.players[2].bankTotal, 2, "P2 should be charged")

        if case .awaitingResponse(let nextTarget, _, _) = engine.state.phase {
            XCTAssertEqual(nextTarget, 3, "Should advance to P3")
        } else {
            XCTFail("Expected awaitingResponse for P3, got \(engine.state.phase)")
        }

        // P3 accepts → charged, queue advances to P4
        engine.acceptAction()
        XCTAssertLessThan(engine.state.players[3].bankTotal, 2, "P3 should be charged")

        if case .awaitingResponse(let nextTarget, _, _) = engine.state.phase {
            XCTAssertEqual(nextTarget, 4, "Should advance to P4")
        } else {
            XCTFail("Expected awaitingResponse for P4, got \(engine.state.phase)")
        }

        // P4 accepts → charged, all done
        engine.acceptAction()
        XCTAssertLessThan(engine.state.players[4].bankTotal, 2, "P4 should be charged")
    }

    // MARK: - Card Play Limits in 5-Player Game

    func testFivePlayerCardLimitStillThree() {
        let engine = makeEngine()
        engine.startTurn()
        for _ in 0..<5 {
            engine.state.players[0].addToHand(makeCard(type: .money(1)))
        }
        for _ in 0..<3 {
            if let card = engine.state.players[0].hand.first {
                engine.playCard(cardId: card.id, as: .bank)
            }
        }
        XCTAssertFalse(engine.state.canPlayCard, "3-card limit should apply in 5-player games too")
    }

    // MARK: - AI Strategy in 5-Player Game

    func testHardAI_CorrectlyFindsLeaderAmong4Opponents() {
        // Ensures the leader-detection logic works with 4 opponents (indices 1-4).
        let players = (0..<5).map { i in Player(name: "P\(i)", isHuman: i == 0) }
        var state = GameState(players: players, deck: DeckBuilder.buildDeck())
        state.phase = .playing
        state.cardsPlayedThisTurn = 0
        state.currentPlayerIndex = 0

        // P3 is the leader (2 sets); everyone else has 0 or 1
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[3].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[3].properties[.blueChip]     = makeCompleteSet(color: .blueChip)

        let snatcher = makeCard(type: .action(.dealSnatcher))
        state.players[0].addToHand(snatcher)

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 0, difficulty: .hard)
        XCTAssertEqual(decision?.targetPlayerIndex, 3,
                       "Hard should target P3 (the leader with 2 sets among 4 opponents)")
    }
}
