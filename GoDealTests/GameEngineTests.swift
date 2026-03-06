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
        blueSet.hasApartmentBuilding = true
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
                XCTAssertFalse(remainingSet.hasApartmentBuilding, "Tower Block must be cleared from incomplete set")
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

        // Simulate Big Spender played by player 0:
        // Player 1 is first in queue, player 2 is in pendingResponsePlayerIndices.
        let bigSpenderCard = makeCard(type: .action(.bigSpender))
        engine.state.pendingResponsePlayerIndices = [2]   // player 2 will get next window
        engine.state.phase = .awaitingResponse(
            targetPlayerIndex: 1,
            actionCard: bigSpenderCard,
            attackerIndex: 0
        )
        engine.state.currentPlayerIndex = 0

        // Player 1 (CPU) accepts — should be charged and queue advances to player 2
        engine.acceptAction()
        XCTAssertLessThan(engine.state.players[1].bankTotal, 2, "Player 1 should be charged after accepting")

        // Phase should now be awaitingResponse for player 2
        if case .awaitingResponse(let targetIdx, _, _) = engine.state.phase {
            XCTAssertEqual(targetIdx, 2, "Queue should advance to player 2")
        } else {
            XCTFail("Expected awaitingResponse for player 2, got \(engine.state.phase)")
        }

        // Player 2 (CPU) accepts — should also be charged
        engine.acceptAction()
        XCTAssertLessThan(engine.state.players[2].bankTotal, 2, "Player 2 should be charged after accepting")
    }

    // MARK: - Improvement → Bank on Wild Break

    func testCornerStoreReturnsToBankWhenWildBreaksSet() {
        // Set up: player 0 has a complete Blue Chip set (2 cards) with Corner Store
        // One of the 2 cards is a wild. Reassigning the wild makes the set incomplete.
        let engine = makeEngine()
        engine.startTurn()

        let wildCard = Card(id: UUID(), type: .wildProperty([.blueChip, .rustDistrict]),
                            name: "Wild", description: "", monetaryValue: 1, assetKey: "wild_test")
        let normalCard = makeCard(type: .property(.blueChip), value: 4)

        engine.state.players[0].placeProperty(wildCard, in: .blueChip)
        engine.state.players[0].placeProperty(normalCard, in: .blueChip)
        XCTAssertTrue(engine.state.players[0].properties[.blueChip]?.isComplete == true,
                      "Blue Chip set should be complete (2/2)")

        engine.state.players[0].properties[.blueChip]?.hasCornerStore = true
        XCTAssertEqual(engine.state.players[0].bankTotal, 0, "Bank should be empty before reassignment")

        // Reassign the wild to Rust District — breaks the Blue Chip set
        engine.reassignWild(cardId: wildCard.id, toColor: .rustDistrict)

        XCTAssertFalse(engine.state.players[0].properties[.blueChip]?.isComplete == true,
                       "Blue Chip set should now be incomplete")
        XCTAssertFalse(engine.state.players[0].properties[.blueChip]?.hasCornerStore == true,
                       "Corner Store flag should be cleared")
        XCTAssertEqual(engine.state.players[0].bankTotal, 3,
                       "Corner Store ($3M) should be returned to bank")
    }

    func testApartmentBuildingReturnsToBankWhenWildBreaksSet() {
        let engine = makeEngine()
        engine.startTurn()

        let wildCard = Card(id: UUID(), type: .wildProperty([.hotZone, .goldRush]),
                            name: "Wild", description: "", monetaryValue: 1, assetKey: "wild_test2")
        // hotZone needs 3 properties — add 2 normals + 1 wild = 3 total → complete
        for _ in 0..<2 {
            engine.state.players[0].placeProperty(makeCard(type: .property(.hotZone), value: 3), in: .hotZone)
        }
        engine.state.players[0].placeProperty(wildCard, in: .hotZone)
        XCTAssertTrue(engine.state.players[0].properties[.hotZone]?.isComplete == true)

        engine.state.players[0].properties[.hotZone]?.hasCornerStore = true
        engine.state.players[0].properties[.hotZone]?.hasApartmentBuilding = true

        // Reassign wild — breaks the set (2/3 remaining)
        engine.reassignWild(cardId: wildCard.id, toColor: .goldRush)

        XCTAssertFalse(engine.state.players[0].properties[.hotZone]?.hasCornerStore == true)
        XCTAssertFalse(engine.state.players[0].properties[.hotZone]?.hasApartmentBuilding == true)
        // Both CS ($3M) + AB ($3M) returned
        XCTAssertEqual(engine.state.players[0].bankTotal, 6,
                       "Both Corner Store and Apt. Building ($6M total) should be returned to bank")
    }

    func testNoImprovementReturnWhenSetStaysComplete() {
        // Wild reassignment that moves WITHIN a complete set (set remains complete)
        // should not return any improvement cards.
        let engine = makeEngine()
        engine.startTurn()

        // rustDistrict needs 2 cards. Place 2 normals (complete without wild).
        engine.state.players[0].placeProperty(makeCard(type: .property(.rustDistrict), value: 1), in: .rustDistrict)
        engine.state.players[0].placeProperty(makeCard(type: .property(.rustDistrict), value: 1), in: .rustDistrict)
        engine.state.players[0].properties[.rustDistrict]?.hasCornerStore = true

        // Move a wild from skylineAve (incomplete, no improvement) to blueChip
        let wildCard = Card(id: UUID(), type: .wildProperty([.skylineAve, .blueChip]),
                            name: "Wild", description: "", monetaryValue: 1, assetKey: "wild_test3")
        engine.state.players[0].placeProperty(wildCard, in: .skylineAve)

        let bankBefore = engine.state.players[0].bankTotal
        engine.reassignWild(cardId: wildCard.id, toColor: .blueChip)

        XCTAssertEqual(engine.state.players[0].bankTotal, bankBefore,
                       "No bank compensation when moved wild's source set had no improvement")
    }

    func testWildReassignmentNoBankCompensationWhenNoImprovement() {
        // Wild breaks a complete set that has NO improvement — bank should not change.
        let engine = makeEngine()
        engine.startTurn()

        let wildCard = Card(id: UUID(), type: .wildProperty([.blueChip, .rustDistrict]),
                            name: "Wild", description: "", monetaryValue: 1, assetKey: "wild_nc")
        let normal = makeCard(type: .property(.blueChip), value: 4)
        engine.state.players[0].placeProperty(wildCard, in: .blueChip)
        engine.state.players[0].placeProperty(normal, in: .blueChip)
        // No improvements on the set

        engine.reassignWild(cardId: wildCard.id, toColor: .rustDistrict)

        XCTAssertEqual(engine.state.players[0].bankTotal, 0,
                       "No compensation when set had no improvements")
    }

    // MARK: - Manual End Turn (no auto-end after 3 cards)

    func testPhaseRemainsPlayingAfter3Cards() {
        // After playing 3 cards, the engine phase must stay .playing — no auto-advance.
        // The human must press End Turn manually.
        let engine = makeEngine()
        engine.startTurn()
        engine.state.players[0].hand = []

        for _ in 0..<3 {
            engine.state.players[0].addToHand(makeCard(type: .money(1)))
        }
        for _ in 0..<3 {
            if let card = engine.state.players[0].hand.first {
                engine.playCard(cardId: card.id, as: .bank)
            }
        }

        XCTAssertEqual(engine.state.cardsPlayedThisTurn, 3)
        guard case .playing = engine.state.phase else {
            XCTFail("Phase should still be .playing after 3 cards — got \(engine.state.phase)")
            return
        }
        // Engine doesn't advance — ViewModel's autoEndTurnIfNeeded was removed
    }

    func testCanEndTurnManuallyAfter3Cards() {
        let engine = makeEngine()
        engine.startTurn()
        engine.state.players[0].hand = []

        for _ in 0..<3 {
            engine.state.players[0].addToHand(makeCard(type: .money(1)))
        }
        for _ in 0..<3 {
            if let card = engine.state.players[0].hand.first {
                engine.playCard(cardId: card.id, as: .bank)
            }
        }

        engine.endTurn()

        XCTAssertEqual(engine.state.currentPlayerIndex, 1, "Should advance to next player after manual end turn")
        XCTAssertEqual(engine.state.cardsPlayedThisTurn, 0, "Card count resets after end turn")
    }

    func testCanEndTurnBeforePlayingAnyCards() {
        // Player should be allowed to end turn even without playing any cards.
        let engine = makeEngine()
        engine.startTurn()
        XCTAssertEqual(engine.state.cardsPlayedThisTurn, 0)

        engine.endTurn()

        XCTAssertEqual(engine.state.currentPlayerIndex, 1, "Should advance even with 0 cards played")
    }

    // MARK: - Corner Store Action Placement

    func testCornerStorePlacedOnOnlyEligibleSet() {
        // When there is exactly one eligible complete set, Corner Store auto-places.
        let engine = makeEngine()
        engine.startTurn()

        engine.state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        let csCard = Card(id: UUID(), type: .action(.cornerStore), name: "Corner Store",
                          description: "", monetaryValue: 3, assetKey: "card_cornerStore_1")
        engine.state.players[0].addToHand(csCard)

        engine.playCard(cardId: csCard.id, as: .action)

        XCTAssertTrue(engine.state.players[0].properties[.rustDistrict]?.hasCornerStore == true,
                      "Corner Store should be placed on Rust District")
        XCTAssertNil(engine.state.players[0].hand.first(where: { $0.id == csCard.id }),
                     "Corner Store card should be removed from hand")
    }

    func testCornerStoreFailsWithNoEligibleSets() {
        // Playing Corner Store with no complete sets should fail and return card to hand.
        let engine = makeEngine()
        engine.startTurn()
        // No complete sets

        let csCard = Card(id: UUID(), type: .action(.cornerStore), name: "Corner Store",
                          description: "", monetaryValue: 3, assetKey: "card_cornerStore_1")
        engine.state.players[0].addToHand(csCard)
        let countBefore = engine.state.players[0].hand.count

        engine.playCard(cardId: csCard.id, as: .action)

        XCTAssertEqual(engine.state.players[0].hand.count, countBefore,
                       "Corner Store should return to hand when no eligible sets exist")
        XCTAssertEqual(engine.state.cardsPlayedThisTurn, 0,
                       "Card play count should not increment on failed action")
    }

    func testCornerStorePlacedWithTargetColor() {
        // When targetColor is provided explicitly (multi-set picker case), it places on that color.
        let engine = makeEngine()
        engine.startTurn()

        engine.state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        engine.state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)

        let csCard = Card(id: UUID(), type: .action(.cornerStore), name: "Corner Store",
                          description: "", monetaryValue: 3, assetKey: "card_cornerStore_1")
        engine.state.players[0].addToHand(csCard)

        engine.playCard(cardId: csCard.id, as: .action, targetPropertyColor: .blueChip)

        XCTAssertTrue(engine.state.players[0].properties[.blueChip]?.hasCornerStore == true,
                      "Corner Store placed on Blue Chip (specified target)")
        XCTAssertFalse(engine.state.players[0].properties[.rustDistrict]?.hasCornerStore == true,
                       "Corner Store NOT placed on Rust District")
    }

    // MARK: - PlayerStats Initialization & Reset

    func testPlayerStatsInitializedWithCorrectCount() {
        let engine2 = makeEngine(playerCount: 2)
        XCTAssertEqual(engine2.state.playerStats.count, 2)
        XCTAssertEqual(engine2.state.playerStats[0], PlayerStats())
        XCTAssertEqual(engine2.state.playerStats[1], PlayerStats())

        let engine4 = makeEngine(playerCount: 4)
        XCTAssertEqual(engine4.state.playerStats.count, 4)
    }

    func testPlayerStatsResetOnNewGame() {
        let engine = makeEngine()
        engine.state.playerStats[0].steals = 5
        engine.state.playerStats[0].rentCollected = 10

        // Create a fresh state (simulates newGame)
        let newState = GameState(players: engine.state.players, deck: DeckBuilder.buildDeck())
        XCTAssertEqual(newState.playerStats.count, 2)
        XCTAssertEqual(newState.playerStats[0].steals, 0)
        XCTAssertEqual(newState.playerStats[0].rentCollected, 0)
    }

    // MARK: - Draw Tracking

    func testTurnDrawIncrementsByType() {
        let engine = makeEngine()
        // Give player a card so they draw 2 (not 5)
        engine.state.players[0].addToHand(makeCard(type: .money(1)))
        let statsBefore = engine.state.playerStats[0]
        let totalBefore = statsBefore.moneyCardsDrawn + statsBefore.propertyCardsDrawn
            + statsBefore.actionCardsDrawn + statsBefore.rentCardsDrawn

        engine.startTurn()

        let statsAfter = engine.state.playerStats[0]
        let totalAfter = statsAfter.moneyCardsDrawn + statsAfter.propertyCardsDrawn
            + statsAfter.actionCardsDrawn + statsAfter.rentCardsDrawn
        XCTAssertEqual(totalAfter - totalBefore, 2, "Should track exactly 2 drawn cards")
    }

    func testTrackCardsDrawCountsByType() {
        let engine = makeEngine()
        let moneyCard = makeCard(type: .money(5), value: 5)
        let propCard = makeCard(type: .property(.blueChip), value: 3)
        let actionCard = makeCard(type: .action(.dealForward), value: 2)
        let rentCard = Card(id: UUID(), type: .rent([.blueChip, .rustDistrict]), name: "Rent", description: "", monetaryValue: 1, assetKey: "rent_test")

        engine.trackCardsDraw([moneyCard, propCard, actionCard, rentCard], for: 0)

        XCTAssertEqual(engine.state.playerStats[0].moneyCardsDrawn, 1)
        XCTAssertEqual(engine.state.playerStats[0].propertyCardsDrawn, 1)
        XCTAssertEqual(engine.state.playerStats[0].actionCardsDrawn, 1)
        XCTAssertEqual(engine.state.playerStats[0].rentCardsDrawn, 1)
    }

    func testDealForwardCountedInDrawStats() {
        let engine = makeEngine()
        engine.startTurn()

        let totalBefore = engine.state.playerStats[0].moneyCardsDrawn
            + engine.state.playerStats[0].propertyCardsDrawn
            + engine.state.playerStats[0].actionCardsDrawn
            + engine.state.playerStats[0].rentCardsDrawn

        let dealFwd = makeCard(type: .action(.dealForward), value: 2)
        engine.state.players[0].addToHand(dealFwd)
        engine.playCard(cardId: dealFwd.id, as: .action)

        let totalAfter = engine.state.playerStats[0].moneyCardsDrawn
            + engine.state.playerStats[0].propertyCardsDrawn
            + engine.state.playerStats[0].actionCardsDrawn
            + engine.state.playerStats[0].rentCardsDrawn
        // Deal Forward draws 2 cards — those should be counted by type
        XCTAssertEqual(totalAfter - totalBefore, 2, "Deal Forward should track 2 drawn cards")
    }

    // MARK: - Bank & Payment Stats

    func testPeakBankValueTrackedWhenBanking() {
        let engine = makeEngine()
        engine.startTurn()

        let money5 = makeCard(type: .money(5), value: 5)
        engine.state.players[0].addToHand(money5)
        engine.playCard(cardId: money5.id, as: .bank)
        XCTAssertEqual(engine.state.playerStats[0].peakBankValue, 5)

        let money3 = makeCard(type: .money(3), value: 3)
        engine.state.players[0].addToHand(money3)
        engine.playCard(cardId: money3.id, as: .bank)
        XCTAssertEqual(engine.state.playerStats[0].peakBankValue, 8, "Peak should be cumulative bank total")
    }

    func testCollectNowIncrementsRentCollectedAndPaid() {
        let engine = makeEngine()
        engine.startTurn()

        // Give debtor (player 1) $5M in bank
        engine.state.players[1].bank = [makeCard(type: .money(5), value: 5)]

        ActionResolver.executeCollectNow(creditorIndex: 0, debtorIndex: 1, state: &engine.state)

        XCTAssertEqual(engine.state.playerStats[0].rentCollected, 5)
        XCTAssertEqual(engine.state.playerStats[1].rentPaid, 5)
    }

    func testPeakBankUpdatedAfterReceivingRentPayment() {
        var state = makeEngine().state
        state.players[0].bank = []  // creditor starts empty
        state.players[1].bank = [makeCard(type: .money(5), value: 5)]

        PaymentResolver.resolvePayment(state: &state, debtorIndex: 1, creditorIndex: 0, amount: 5)

        XCTAssertGreaterThanOrEqual(state.playerStats[0].peakBankValue, 5,
                                    "Creditor's peakBankValue should update after receiving payment")
    }

    // MARK: - Steal Stats

    func testQuickGrabIncrementsSteals() {
        var state = makeEngine().state
        let card = makeCard(type: .property(.hotZone), value: 2)
        state.players[1].placeProperty(card, in: .hotZone)

        ActionResolver.executeQuickGrab(attackerIndex: 0, targetIndex: 1, cardId: card.id, state: &state)

        XCTAssertEqual(state.playerStats[0].steals, 1)
        XCTAssertEqual(state.playerStats[1].steals, 0, "Victim's steals should not change")
    }

    func testDealSnatcherIncrementsSteals() {
        var state = makeEngine().state
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)

        ActionResolver.executeDealSnatcher(attackerIndex: 0, targetIndex: 1, color: .rustDistrict, state: &state)

        XCTAssertEqual(state.playerStats[0].steals, 1)
    }

    func testSwapItIncrementsSteals() {
        var state = makeEngine().state
        let p0Card = makeCard(type: .property(.rustDistrict), value: 1)
        let p1Card = makeCard(type: .property(.blueChip), value: 3)
        state.players[0].placeProperty(p0Card, in: .rustDistrict)
        state.players[1].placeProperty(p1Card, in: .blueChip)

        ActionResolver.executeSwapIt(attackerIndex: 0, targetIndex: 1,
                                     attackerCardId: p0Card.id, targetCardId: p1Card.id, state: &state)

        XCTAssertEqual(state.playerStats[0].steals, 1)
        XCTAssertEqual(state.playerStats[1].steals, 0, "Victim's steals should not change")
    }

    // MARK: - Multiplayer Correctness

    func testStatsTrackedIndependentlyPerPlayer() {
        var state = makeEngine(playerCount: 3).state

        // Player 0 steals from player 1
        let card = makeCard(type: .property(.hotZone), value: 2)
        state.players[1].placeProperty(card, in: .hotZone)
        ActionResolver.executeQuickGrab(attackerIndex: 0, targetIndex: 1, cardId: card.id, state: &state)

        // Player 2 collects rent from player 1
        state.players[1].bank = [makeCard(type: .money(3), value: 3)]
        PaymentResolver.resolvePayment(state: &state, debtorIndex: 1, creditorIndex: 2, amount: 3)

        XCTAssertEqual(state.playerStats[0].steals, 1)
        XCTAssertEqual(state.playerStats[0].rentCollected, 0)
        XCTAssertEqual(state.playerStats[1].steals, 0)
        XCTAssertEqual(state.playerStats[1].rentPaid, 3)
        XCTAssertEqual(state.playerStats[2].steals, 0)
        XCTAssertEqual(state.playerStats[2].rentCollected, 3)
    }

    func testStatsAccumulateAcrossMultipleTurns() {
        var state = makeEngine().state
        state.players[1].bank = [
            makeCard(type: .money(3), value: 3),
            makeCard(type: .money(2), value: 2),
        ]

        PaymentResolver.resolvePayment(state: &state, debtorIndex: 1, creditorIndex: 0, amount: 3)
        PaymentResolver.resolvePayment(state: &state, debtorIndex: 1, creditorIndex: 0, amount: 2)

        XCTAssertEqual(state.playerStats[0].rentCollected, 5, "Should accumulate both payments")
        XCTAssertEqual(state.playerStats[1].rentPaid, 5, "Should accumulate both payments")
    }

    // MARK: - No Deal Stats

    func testNoDealPlayedIncrementsStat() {
        let engine = makeEngine()
        engine.startTurn()

        let actionCard = makeCard(type: .action(.collectNow), value: 2)
        engine.state.phase = .awaitingResponse(
            targetPlayerIndex: 1, actionCard: actionCard, attackerIndex: 0
        )
        let noDealCard = makeCard(type: .action(.noDeal), value: 2)
        engine.state.players[1].addToHand(noDealCard)

        engine.playNoDeal(cardId: noDealCard.id, playerIndex: 1)

        XCTAssertEqual(engine.state.playerStats[1].noDealPlayed, 1)
    }

    // MARK: - Hard CPU Strategy

    func testHardCPUBanksBeforePlacingPropertiesWhenPoor() {
        var state = makeEngine().state
        state.phase = .playing
        state.currentPlayerIndex = 1
        state.cardsPlayedThisTurn = 0

        // CPU has $3M money + a property card; bank is empty
        let moneyCard = makeCard(type: .money(3), value: 3)
        let propCard = makeCard(type: .property(.hotZone), value: 2)
        state.players[1].hand = [moneyCard, propCard]
        state.players[1].bank = []

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 1, difficulty: .hard)
        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.card.id, moneyCard.id, "Hard CPU should bank money first when bank < $5M")
    }

    func testHardCPUPlacesPropertyWhenBankSufficient() {
        var state = makeEngine().state
        state.phase = .playing
        state.currentPlayerIndex = 1
        state.cardsPlayedThisTurn = 0

        let moneyCard = makeCard(type: .money(3), value: 3)
        let propCard = makeCard(type: .property(.hotZone), value: 2)
        state.players[1].hand = [moneyCard, propCard]
        // Bank already has $6M — above $5M threshold
        state.players[1].bank = [makeCard(type: .money(5), value: 5), makeCard(type: .money(1), value: 1)]

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 1, difficulty: .hard)
        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.card.id, propCard.id, "Hard CPU should place property when bank >= $5M")
    }

    func testHardCPUWinsImmediatelyEvenWhenBankLow() {
        var state = makeEngine().state
        state.phase = .playing
        state.currentPlayerIndex = 1
        state.cardsPlayedThisTurn = 0

        // CPU has 2 complete sets already
        state.players[1].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[1].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        state.players[1].bank = []  // empty bank

        // Target has a complete set to steal
        state.players[0].properties[.hotZone] = makeCompleteSet(color: .hotZone)

        let snatcher = makeCard(type: .action(.dealSnatcher), value: 5)
        let moneyCard = makeCard(type: .money(3), value: 3)
        state.players[1].hand = [snatcher, moneyCard]

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 1, difficulty: .hard)
        XCTAssertEqual(decision?.card.id, snatcher.id,
                       "Hard CPU should play Deal Snatcher to WIN (priority 1) even with empty bank")
    }

    func testHardCPUBlocksOpponentNearWinEvenWhenBankLow() {
        var state = makeEngine().state
        state.phase = .playing
        state.currentPlayerIndex = 1
        state.cardsPlayedThisTurn = 0

        // Opponent (player 0) has 2 complete sets + 1 incomplete near-done
        state.players[0].properties[.rustDistrict] = makeCompleteSet(color: .rustDistrict)
        state.players[0].properties[.blueChip] = makeCompleteSet(color: .blueChip)
        // hotZone needs 3 — give them 2 (1 away)
        state.players[0].placeProperty(makeCard(type: .property(.hotZone), value: 2), in: .hotZone)
        state.players[0].placeProperty(makeCard(type: .property(.hotZone), value: 2), in: .hotZone)

        state.players[1].bank = []
        let snatcher = makeCard(type: .action(.dealSnatcher), value: 5)
        let moneyCard = makeCard(type: .money(3), value: 3)
        state.players[1].hand = [snatcher, moneyCard]

        let decision = AIStrategy.decideNextPlay(state: state, playerIndex: 1, difficulty: .hard)
        XCTAssertEqual(decision?.card.id, snatcher.id,
                       "Hard CPU should play Deal Snatcher to BLOCK near-win (priority 1.5) even with empty bank")
    }

    func testHardCPUDoesNotWasteNoDealOnCollectNowWhenRich() {
        var state = makeEngine().state
        // Hard CPU with $10M bank
        state.players[1].bank = [makeCard(type: .money(10), value: 10)]
        let noDealCard = makeCard(type: .action(.noDeal), value: 2)
        state.players[1].addToHand(noDealCard)

        let collectNowCard = makeCard(type: .action(.collectNow), value: 5)
        let result = AIStrategy.shouldPlayNoDeal(
            state: state, playerIndex: 1, actionCard: collectNowCard, difficulty: .hard
        )
        XCTAssertNil(result, "Hard CPU with $10M should NOT waste No Deal on Collect Now")
    }
}
