# Go! Deal! — Coding Patterns & Architecture

## MVVM Rules
- **Models**: Plain Swift structs/enums, no SwiftUI imports, value types only
- **Engine**: Class-based state machine (`GameEngine`), mutates `GameState` directly, synchronous
- **ViewModels**: `@Observable` classes wrapping `GameEngine`, expose `@Published`-equivalent state to SwiftUI
- **Views**: SwiftUI structs only, read from ViewModel, call ViewModel methods for actions

## GameEngine Pattern
```swift
// GameEngine is the single source of truth mutator
class GameEngine {
    private(set) var state: GameState
    func playCard(_ card: Card, from player: Player, target: ...) throws
    func endTurn()
    func drawCards(for playerIndex: Int)
}
// Never mutate GameState outside of GameEngine
```

## State Flow
```
GameViewModel (@Observable)
  └── GameEngine (owns GameState)
        ├── ActionResolver (stateless, takes inout GameState)
        ├── PaymentResolver (stateless, takes inout GameState)
        └── WinChecker (stateless, pure function)
```

## Adding a New Card Type
1. Add case to `ActionType` enum in `Card.swift`
2. Add card construction in `DeckBuilder.swift`
3. Add handling in `ActionResolver.swift`
4. Add AI priority in `AIStrategy.swift`

## Naming Conventions
- Models: `Card`, `Player`, `GameState` (no suffix)
- Engine: `GameEngine`, `ActionResolver` (Engine suffix only on main driver)
- ViewModels: `GameViewModel`, `CustomizationViewModel` (ViewModel suffix)
- Views: `GameBoardView`, `CardView` (View suffix)
- Enums: `PropertyColor`, `ActionType`, `GamePhase` (no suffix, descriptive)

## PropertyColor Pattern
```swift
// Each color knows its own rules
enum PropertyColor: String, CaseIterable {
    case rustDistrict
    var setSize: Int { ... }
    var rentTable: [Int] { ... }  // indexed: [1prop, 2prop, full, +store, +tower]
    var displayName: String { ... }
    var color: Color { ... }      // SwiftUI Color (in Views only)
}
```

## Wild Property Cards
- Wild properties can be assigned to one of their valid colors
- Stored in `Player.properties[chosenColor]` once assigned
- Assignment is permanent (cannot be moved once placed)

## No Deal! Chain
```
Attacker plays action
  → awaitingResponse(targetIndex)
  → Target may play No Deal! → cancel action
      → Attacker may play No Deal! → cancel the No Deal! → action proceeds
```

## Payment Rule (no change rule)
- Player pays from bank first (exact cards preferred), then from properties
- No change given — overpayment kept by collector
- If still short, collector receives whatever the debtor has

## CardImageStore Pattern
```swift
// Always use assetKey, never card.id for image lookup
CardImageStore.image(for card.assetKey)  // checks Documents/ first, then Assets.xcassets
```

## SwiftUI Conventions
- Use `@Environment(GameViewModel.self)` to inject ViewModel
- Sheets use `@Binding<Bool>` for isPresented
- Card animations: use `.matchedGeometryEffect` for card movement
- Keep view bodies under ~80 lines; extract subviews aggressively
