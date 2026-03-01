# Go! Deal! — Testing Guide

## Test Target
- **Name**: `GoDealTests`
- **Location**: `GoDealTests/`
- **Run**: `xcodebuild test -scheme GoDeal -destination 'platform=iOS Simulator,name=iPhone 15'`
- **Quick run**: `xcodebuild test -scheme GoDeal -destination 'platform=iOS Simulator,OS=latest,name=iPhone 15' 2>&1 | xcpretty`

## Test Modules

### DeckBuilderTests.swift
- Deck has exactly 110 cards
- Correct counts: 28 property, 20 money, 10 rent, 3 wildRent, 11 wildProperty, 13 action (dealForward×3, cornerStore×3, towerBlock×2, doubleUp×3, others×1-2)
- No duplicate card IDs
- Every assetKey is non-empty and unique

### GameEngineTests.swift
- Draw 2 cards at turn start (5 if hand empty)
- Max 3 cards per turn enforced
- End-of-turn discard to 7 triggered if hand > 7
- No Deal! chain: attacker plays action → target cancels → attacker counter-cancels → action executes
- Payment: bank-first ordering, no-change rule, partial payment accepted
- Property steal (quickGrab) moves card between players' property sets
- Set-complete detection after steal/place

### WinCheckerTests.swift
- 3 complete sets returns win for correct player
- 2 complete sets returns nil (no win)
- Complete set with Corner Store / Tower Block still counts as 1 set
- Win check after every card play

## Mock Factories
```swift
// Create minimal test players
func makePlayer(name: String, isHuman: Bool = false) -> Player
func makeGameState(playerCount: Int = 2) -> GameState

// Useful: build a state where a player is 1 property away from winning
func makeNearWinState() -> GameState
```

## AI Smoke Tests
```swift
// CPUPlayer must always produce a legal move or pass
// Game with 2 CPUs must terminate in ≤ 200 turns
func testCPUAlwaysMakesLegalMove()
func testGameTerminatesInReasonableTurns()
```

## Key Assertions
```swift
XCTAssertEqual(deck.count, 110)
XCTAssertNil(WinChecker.check(state))       // no win yet
XCTAssertEqual(WinChecker.check(state), 0)  // player 0 wins
```
