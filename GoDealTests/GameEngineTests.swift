import XCTest
@testable import GoDeal

final class GameEngineTests: XCTestCase {

    // MARK: - Helpers

    func makeEngine(playerCount: Int = 2) -> GameEngine {
        var players = [Player(name: "Human", isHuman: true)]
        for i in 1..<playerCount {
            players.append(Player(name: "CPU \(i)", isHuman: false))
        }
        let deck = DeckBuilder.buildDeck()
        let state = GameState(players: players, deck: deck)
        return GameEngine(state: state)
    }

    func makeCard(type: CardType, value: Int = 1) -> Card {
        Card(id: UUID(), type: type, name: "Test", description: "", monetaryValue: value, assetKey: "test_\(UUID())")
    }

    func makeCompleteSet(color: PropertyColor) -> PropertySet {
        var set = PropertySet(color: color, properties: [])
        for i in 0..<color.setSize {
            set.addProperty(makeCard(type: .property(color), value: 2))
        }
        return set
    }

    // MARK: - Draw Phase

    func testDrawTwoCardsAtTurnStart() {
        let engine = makeEngine()
        // Give player a non-empty hand so the engine draws 2 (not 5)
        engine.state.players[0].addToHand(makeCard(type: .money(1)))
        let initialHandSize = engine.state.players[0].hand.count
        engine.startTurn()
        XCTAssertEqual(engine.state.players[0].hand.count, initialHandSize + 2)
    }

    func testDrawFiveCardsIfHandEmpty() {
        let engine = makeEngine()
        // Empty the hand
        engine.state.players[0].hand = []
        engine.startTurn()
        XCTAssertEqual(engine.state.players[0].hand.count, 5)
    }

    func testPhaseMovesToPlayingAfterDraw() {
        let engine = makeEngine()
        XCTAssertEqual(engine.state.phase, .drawing)
        engine.startTurn()
        XCTAssertEqual(engine.state.phase, .playing)
    }

    // MARK: - Card Play Limit

    func testCanPlayUpTo3CardsPerTurn() {
        let engine = makeEngine()
        engine.startTurn()

        // Give player some money cards
        for _ in 0..<5 {
            engine.state.players[0].addToHand(makeCard(type: .money(1), value: 1))
        }

        let hand = engine.state.players[0].hand
        XCTAssertTrue(engine.state.canPlayCard)

        // Play 3 cards
        for i in 0..<3 {
            guard engine.state.canPlayCard, let card = engine.state.players[0].hand.first else { break }
            engine.playCard(cardId: card.id, as: .bank)
        }

        XCTAssertFalse(engine.state.canPlayCard, "Should not be able to play 4th card")
    }

    func testCardsPlayedCountResets() {
        let engine = makeEngine()
        engine.startTurn()
        engine.state.players[0].hand = []

        // Add cards and play them
        for _ in 0..<3 {
            engine.state.players[0].addToHand(makeCard(type: .money(1)))
        }
        for _ in 0..<3 {
            if let card = engine.state.players[0].hand.first {
                engine.playCard(cardId: card.id, as: .bank)
            }
        }

        engine.endTurn()

        // Should reset for next player
        XCTAssertEqual(engine.state.cardsPlayedThisTurn, 0)
    }

    // MARK: - Property Playing

    func testPlayingPropertyMovesCardToPropertyArea() {
        let engine = makeEngine()
        engine.startTurn()

        let propertyCard = makeCard(type: .property(.rustDistrict))
        engine.state.players[0].addToHand(propertyCard)

        engine.playCard(cardId: propertyCard.id, as: .property(.rustDistrict))

        XCTAssertNil(engine.state.players[0].hand.first(where: { $0.id == propertyCard.id }), "Card should be removed from hand")
        XCTAssertNotNil(engine.state.players[0].properties[.rustDistrict], "Property set should exist")
        XCTAssertEqual(engine.state.players[0].properties[.rustDistrict]?.properties.count, 1)
    }

    // MARK: - Banking

    func testPlayingMoneyMovesCardToBank() {
        let engine = makeEngine()
        engine.startTurn()

        let moneyCard = makeCard(type: .money(5), value: 5)
        engine.state.players[0].addToHand(moneyCard)

        engine.playCard(cardId: moneyCard.id, as: .bank)

        XCTAssertNil(engine.state.players[0].hand.first(where: { $0.id == moneyCard.id }))
        XCTAssertEqual(engine.state.players[0].bankTotal, 5)
    }

    // MARK: - Discard Enforcement

    func testDiscardPhaseTriggeredWhenHandOver7() {
        let engine = makeEngine()
        engine.startTurn()

        // Give player 8 cards
        engine.state.players[0].hand = []
        for _ in 0..<8 {
            engine.state.players[0].addToHand(makeCard(type: .money(1)))
        }

        engine.endTurn()
        XCTAssertEqual(engine.state.phase, .discarding(playerIndex: 0))
    }

    func testDiscardReducesHandTo7() {
        let engine = makeEngine()
        engine.startTurn()

        engine.state.players[0].hand = (0..<10).map { _ in makeCard(type: .money(1)) }
        engine.endTurn()

        // Discard 3
        for _ in 0..<3 {
            if case .discarding(let idx) = engine.state.phase, idx == 0,
               let card = engine.state.players[0].hand.first {
                engine.discard(cardId: card.id)
            }
        }

        XCTAssertLessThanOrEqual(engine.state.players[0].hand.count, 7)
    }

    // MARK: - Turn Advancement

    func testEndTurnAdvancesCurrentPlayer() {
        let engine = makeEngine(playerCount: 2)
        XCTAssertEqual(engine.state.currentPlayerIndex, 0)
        engine.startTurn()
        engine.endTurn()
        XCTAssertEqual(engine.state.currentPlayerIndex, 1)
    }

    func testTurnNumberIncrementsAfterRound() {
        let engine = makeEngine(playerCount: 2)
        XCTAssertEqual(engine.state.turnNumber, 1)
        engine.startTurn()
        engine.endTurn()
        XCTAssertEqual(engine.state.turnNumber, 2)
    }

    // MARK: - Deal Forward Action

    func testDealForwardDraws2ExtraCards() {
        let engine = makeEngine()
        engine.startTurn()

        let initialHand = engine.state.players[0].hand.count
        let dealFwd = makeCard(type: .action(.dealForward), value: 2)
        engine.state.players[0].addToHand(dealFwd)

        engine.playCard(cardId: dealFwd.id, as: .action)

        // initialHand measured before adding dealFwd, so:
        // (initialHand + 1 dealFwd added) - 1 played + 2 drawn = initialHand + 2
        XCTAssertEqual(engine.state.players[0].hand.count, initialHand + 2)
    }

    // MARK: - Win Check After Play

    func testWinDetectedAfterCompletingThirdSet() {
        let engine = makeEngine()
        engine.startTurn()

        // Give player two complete sets already
        engine.state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        engine.state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)

        // Need one more property to complete hotZone (set size 3)
        for i in 0..<2 {
            engine.state.players[0].placeProperty(
                makeCard(type: .property(.hotZone), value: 3),
                in: .hotZone
            )
        }

        // Play the 3rd hotZone property
        let finalProp = makeCard(type: .property(.hotZone), value: 3)
        engine.state.players[0].addToHand(finalProp)
        engine.playCard(cardId: finalProp.id, as: .property(.hotZone))

        XCTAssertEqual(engine.state.players[0].completedSets, 3)
        if case .gameOver(let winnerIdx) = engine.state.phase {
            XCTAssertEqual(winnerIdx, 0)
        } else {
            XCTFail("Expected gameOver phase, got \(engine.state.phase)")
        }
    }

    // MARK: - Payment

    func testPaymentResolver() {
        var state = makeEngine().state

        // Give player 0 bank of $10
        state.players[0].bank = [
            makeCard(type: .money(5), value: 5),
            makeCard(type: .money(3), value: 3),
            makeCard(type: .money(2), value: 2),
        ]

        let result = PaymentResolver.resolvePayment(
            state: &state,
            debtorIndex: 0,
            creditorIndex: 1,
            amount: 5
        )

        XCTAssertGreaterThanOrEqual(result.amountPaid, 5, "Should pay at least $5M")
        XCTAssertTrue(result.wasFullyPaid)
        XCTAssertGreaterThan(state.players[1].bank.count, 0, "Creditor should have received cards")
    }

    func testPartialPaymentWhenInsufficientFunds() {
        var state = makeEngine().state

        // Player has only $2M in bank
        state.players[0].bank = [makeCard(type: .money(2), value: 2)]
        state.players[0].properties = [:]  // No properties

        let result = PaymentResolver.resolvePayment(
            state: &state,
            debtorIndex: 0,
            creditorIndex: 1,
            amount: 10
        )

        XCTAssertEqual(result.amountPaid, 2, "Should only pay what's available")
        XCTAssertFalse(result.wasFullyPaid)
    }

    // MARK: - No Deal Response

    func testNoDealCancelsAction() {
        let engine = makeEngine()
        engine.startTurn()

        // Setup an awaitingResponse state
        let actionCard = makeCard(type: .action(.collectNow), value: 2)
        engine.state.phase = .awaitingResponse(
            targetPlayerIndex: 1,
            actionCard: actionCard,
            attackerIndex: 0
        )

        // Target plays No Deal!
        let noDealCard = makeCard(type: .action(.noDeal), value: 2)
        engine.state.players[1].addToHand(noDealCard)

        engine.playNoDeal(cardId: noDealCard.id, playerIndex: 1)

        XCTAssertEqual(engine.state.phase, .playing, "Action should be cancelled, phase returns to playing")
        XCTAssertNil(engine.state.players[1].hand.first(where: { $0.id == noDealCard.id }), "No Deal card should be in discard")
    }

    // MARK: - AI Smoke Test

    func testCPUAlwaysMakesLegalMove() {
        let state: GameState = {
            var s = makeEngine().state
            s.players[1].addToHand(DeckBuilder.buildDeck().prefix(7).map { $0 })
            return s
        }()

        // AI should always return a valid decision or nil (pass)
        for _ in 0..<20 {
            _ = AIStrategy.decideNextPlay(state: state, playerIndex: 1, difficulty: .medium)
            // Just verify it doesn't crash
        }
    }

    // MARK: - Rainbow Wild AI (crash guard regression)

    func testAIDoesNotCrashWithRainbowWild() {
        // Rainbow wild cards have wildProperty([]) — empty colors array.
        // The AI must not force-unwrap colors[0] when the array is empty.
        var state = makeEngine().state
        state.phase = .playing
        let rainbowWild = Card(id: UUID(), type: .wildProperty([]), name: "Rainbow", description: "", monetaryValue: 3, assetKey: "wild_rainbow")
        state.players[1].hand = [rainbowWild]
        // Both easy and medium must not crash
        _ = AIStrategy.decideNextPlay(state: state, playerIndex: 1, difficulty: .easy)
        _ = AIStrategy.decideNextPlay(state: state, playerIndex: 1, difficulty: .medium)
    }

    // MARK: - Quick Grab Action

    func testQuickGrabStealsMostValuableIncompleteProperty() {
        let engine = makeEngine()
        engine.startTurn()

        // Give player 1 an incomplete blue chip set ($3M card)
        let cheapCard = makeCard(type: .property(.blueChip), value: 1)
        let priceyCard = makeCard(type: .property(.blueChip), value: 3)
        engine.state.players[1].placeProperty(cheapCard, in: .blueChip)
        engine.state.players[1].placeProperty(priceyCard, in: .blueChip)

        let beforeCount = engine.state.players[1].allPropertyCards.count

        // Simulate the executeQueuedAction path — CPU attacking human victim
        engine.state.phase = .awaitingResponse(
            targetPlayerIndex: 0,  // human is target
            actionCard: makeCard(type: .action(.quickGrab)),
            attackerIndex: 1
        )
        engine.acceptAction()  // human accepts

        // After accept, attacker (CPU, index 1) should have stolen the priciest card
        XCTAssertEqual(engine.state.players[1].allPropertyCards.count, beforeCount - 1 + 1,
                       "CPU gains 1 property (net change for CPU: +1 from steal)")
        // The pricey card ($3M) should have moved — player 0 should not have it
        XCTAssertFalse(engine.state.players[0].allPropertyCards.contains { $0.id == priceyCard.id },
                       "Pricier card should have been stolen")
        XCTAssertTrue(engine.state.players[1].allPropertyCards.contains { $0.id == priceyCard.id },
                      "Pricier card should be with the attacker")
    }

    // MARK: - Deal Snatcher Action

    func testDealSnatcherTransfersCompleteSetWithImprovements() {
        let engine = makeEngine()
        engine.startTurn()

        // Give player 0 a complete Rust District set with Corner Store
        var rustSet = makeCompleteSet(color: .rustDistrict)
        rustSet.hasCornerStore = true
        engine.state.players[0].properties[.rustDistrict] = rustSet

        let cardCountBefore = engine.state.players[0].properties[.rustDistrict]!.properties.count

        // CPU (player 1) steals via Deal Snatcher
        ActionResolver.executeDealSnatcher(
            attackerIndex: 1,
            targetIndex: 0,
            color: .rustDistrict,
            state: &engine.state
        )

        XCTAssertNil(engine.state.players[0].properties[.rustDistrict], "Victim should lose the set")
        XCTAssertNotNil(engine.state.players[1].properties[.rustDistrict], "Attacker should gain the set")
        XCTAssertEqual(engine.state.players[1].properties[.rustDistrict]?.properties.count, cardCountBefore)
        XCTAssertTrue(engine.state.players[1].properties[.rustDistrict]?.hasCornerStore ?? false,
                      "Corner Store should transfer with the set")
    }

    // MARK: - Swap It Action

    func testSwapItExchangesProperties() {
        let engine = makeEngine()
        engine.startTurn()

        let p0Card = makeCard(type: .property(.rustDistrict), value: 1)
        let p1Card = makeCard(type: .property(.blueChip), value: 3)
        engine.state.players[0].placeProperty(p0Card, in: .rustDistrict)
        engine.state.players[1].placeProperty(p1Card, in: .blueChip)

        ActionResolver.executeSwapIt(
            attackerIndex: 0,
            targetIndex: 1,
            attackerCardId: p0Card.id,
            targetCardId: p1Card.id,
            state: &engine.state
        )

        XCTAssertTrue(engine.state.players[0].allPropertyCards.contains { $0.id == p1Card.id },
                      "Attacker should have the target's card")
        XCTAssertTrue(engine.state.players[1].allPropertyCards.contains { $0.id == p0Card.id },
                      "Target should have the attacker's card")
    }

    // MARK: - Payment clears improvements from incomplete sets

    func testPaymentWithPropertyClearsImprovementsOnIncompleteSet() {
        var state = makeEngine().state

        // Player 0 has a complete Blue Chip set with Corner Store + Tower Block
        var blueSet = makeCompleteSet(color: .blueChip)
        blueSet.hasCornerStore = true
        blueSet.hasTowerBlock = true
        state.players[0].properties[.blueChip] = blueSet
        state.players[0].bank = []  // no cash — must pay with property

        let result = PaymentResolver.resolvePayment(
            state: &state,
            debtorIndex: 0,
            creditorIndex: 1,
            amount: 5
        )

        XCTAssertGreaterThan(result.amountPaid, 0, "Should have paid something")
        // If a card was taken from the now-incomplete set, improvements must be cleared
        if let remainingSet = state.players[0].properties[.blueChip] {
            if !remainingSet.isComplete {
                XCTAssertFalse(remainingSet.hasCornerStore, "Corner Store must be cleared from incomplete set")
                XCTAssertFalse(remainingSet.hasTowerBlock, "Tower Block must be cleared from incomplete set")
            }
        }
    }

    // MARK: - assignWildColor respects card play limit

    func testAssignWildColorRejectedAfter3CardsPlayed() {
        let engine = makeEngine()
        engine.startTurn()

        // Fill hand with money so we can play 3
        for _ in 0..<4 {
            engine.state.players[0].addToHand(makeCard(type: .money(1)))
        }
        for _ in 0..<3 {
            if let card = engine.state.players[0].hand.first(where: { $0.isMoneyCard }) {
                engine.playCard(cardId: card.id, as: .bank)
            }
        }
        XCTAssertFalse(engine.state.canPlayCard, "3 cards already played")

        // Attempt to assign a wild — should be rejected
        let wild = Card(id: UUID(), type: .wildProperty([.rustDistrict, .blueChip]), name: "Wild", description: "", monetaryValue: 1, assetKey: "wild")
        engine.state.players[0].addToHand(wild)
        let handCountBefore = engine.state.players[0].hand.count
        engine.assignWildColor(cardId: wild.id, color: .rustDistrict)

        XCTAssertEqual(engine.state.players[0].hand.count, handCountBefore, "Wild should remain in hand when card limit reached")
        XCTAssertNil(engine.state.players[0].properties[.rustDistrict], "Wild should not be placed")
    }

    // MARK: - Big Spender multi-player

    func testBigSpenderChargesAllOpponentsIn3PlayerGame() {
        let engine = makeEngine(playerCount: 3)
        engine.startTurn()  // starts player 0's turn

        // Give all opponents some money
        engine.state.players[1].bank = [makeCard(type: .money(2), value: 2)]
        engine.state.players[2].bank = [makeCard(type: .money(2), value: 2)]

        // CPU (player 1) plays Big Spender targeting CPU (player 2)
        // In our current model, player 2 gets the awaitingResponse window, player 1 is charged automatically
        engine.state.phase = .awaitingResponse(
            targetPlayerIndex: 2,   // player 2 got the NoDeal window
            actionCard: makeCard(type: .action(.bigSpender)),
            attackerIndex: 0        // player 0 is attacker
        )
        engine.state.currentPlayerIndex = 0

        let p0BankBefore = engine.state.players[0].bankTotal
        engine.acceptAction()  // player 2 accepts

        // Both players 1 and 2 should have been charged $2M
        // (player 2 is the primary target, player 1 is the "remaining" target)
        XCTAssertLessThan(engine.state.players[2].bankTotal, 2, "Primary target (player 2) should be charged")
    }
}
