# Bug & Polish List (to fix next session)

## Status: IN PROGRESS — session 2 fixes applied 2026-02-27

### FIXED this session:
- **E2/E3**: CPUPlayer now has `resumeTurn()` + `resolvePropertyChoiceIfNeeded()`. `triggerCPUIfNeeded()` handles `.playing` and `.awaitingPropertyChoice` phases. Game no longer gets stuck after No Deal/Accept.
- **E1**: Created `PropertyPickerSheet.swift` (quickGrab, dealSnatcher, swapIt UI). Wired to `GameBoardView` via `isShowingPropertyChoiceSheet`. CPU auto-resolves property choices.
- **E5**: Collect Dues! (`.rent`) no longer shows target picker — auto-picks highest-rent color and charges all. Everyone Pays! (`.wildRent`) still shows target picker, auto-picks color.
- **C1**: `GameViewModel.discard()` sets `isShowingDiscardSheet = false` when discard is complete.
- **F2**: Action cards now have distinct colors per ActionType (dealSnatcher=red, noDeal=charcoal, quickGrab=teal, swapIt=pink, collectNow=gold, bigSpender=green, dealForward=sky blue, doubleUp=purple, cornerStore=brown, towerBlock=indigo).
- **F3**: `.rent([colors])` cards now gradient-colored by their property colors.
- **F4**: Custom card image now shows `$XM` overlay in top-left corner.
- **D1**: PropertySetView now shows only the top card with a `×N` count badge.
- **G2**: Removed `assetKey` display from customization rows.

### Round 2 bugs reported 2026-02-27 (in progress):
- **R1**: Corner Store/Tower Block should be bankable ← already works via confirmationDialog
- **R2**: Bank should show individual cards + total (scrollable) ← already done (BankView compact:false)
- **R3**: Play Now doesn't work — blank screen ← gameViewModel optional/timing issue → FIXED
- **R4**: Cards should animate from deck to hand ← B1 still pending
- **R5**: Big Spender with CPU $0 bank — property should go to player's property area ← PaymentResolver fix → FIXED
- **R6**: Everyone Pays blank modal ← two-step SwiftUI sheet bug → FIXED (use sheet(item:))
- **R7**: Collect Now does nothing ← two-step SwiftUI sheet bug → FIXED (skip dialog)
- **R8**: Everyone Pays naming confusion (charges ONE player) ← by design, wildRent charges one
- **R9**: Human should choose which cards to pay with ← PaymentChoiceSheet added → FIXED
- **R10**: Stuck state / error logging ← stuck state timer added to GameViewModel → FIXED

### STILL PENDING:

---

## Group A: Card Interaction & Hand UX — STILL PENDING

**A1. Hand banner covers highlighted cards**
- File: `GoDeal/Views/Game/PlayerHandView.swift`
- The action hint banner at the bottom overlaps the lifted (selected) card
- Fix: Move the hint above the scroll view, or use a floating tooltip that doesn't overlap

**A2. Tapping money card twice discards it instead of banking it**
- File: `GoDeal/Views/Game/GameBoardView.swift` → `handleCardPlay`
- First tap selects, second tap calls `onCardPlay` → `handleCardPlay` → `.money` → `playToBank`
- Could be a timing/state issue or the card is being treated as "played" but the engine discards it
- Check `GameEngine.playCard` bank case: it calls `state.discardPile.append(card)` AND `addToBank` — that's INTENTIONAL (bank = played, discard tracks history). Verify `addToBank` is also called. Bug might be in UI not re-rendering.

**A3. Card detail modal on tap**
- Files: `GoDeal/Views/Game/PlayerHandView.swift`, new `CardDetailSheet.swift`
- Tapping a card should show a modal with: large card image + full name + full description text
- The long-press or info button could trigger it (different from the "play" tap)
- Suggest: single tap = select, double tap or info button = detail modal

**A4. Wild property picker shows empty page**
- File: `GoDeal/Views/Game/GameBoardView.swift` → `WildPropertyColorPicker`, `handleCardPlay`
- Issue: `wildProperty(let colors)` — if `colors` is empty or the colors aren't valid for any set, shows empty list
- Fix: Validate `colors.count > 0` before showing picker; show "Cannot place this wild card" if no valid colors
- Also check DeckBuilder that wild cards always have ≥1 valid color

**A5. Any action card can be banked (by its monetary value)**
- Files: `GoDeal/Views/Game/GameBoardView.swift` → `handleCardPlay`, `GoDeal/Engine/GameEngine.swift`
- For action cards, add "Bank it ($XM)" as an option alongside "Play as action"
- In `handleCardPlay` for `.action`, instead of always triggering the action sheet, give option to bank
- Engine already supports `.bank` destination for any card — just need UI to offer it

---

## Group B: Animations

**B1. Animate cards being drawn from deck to hand**
- Files: `GoDeal/Views/Game/DeckAreaView.swift`, `GoDeal/Views/Game/PlayerHandView.swift`, `GoDeal/ViewModels/GameViewModel.swift`
- On `startTurn()`, animate cards flying from deck position to hand
- Use `matchedGeometryEffect` or a custom animation with `withAnimation` + `offset`
- Opponent draw animation is nice-to-have but not required

**B2. Property payment animation (property goes from debtor to creditor)**
- Files: `GoDeal/Views/Game/PlayerPropertyView.swift`, `GoDeal/Engine/PaymentResolver.swift`
- When a player pays with property, animate it leaving their area and entering the other player's area
- Can be a simpler slide/fade for now

---

## Group C: Discard & End-of-Turn

**C1. Discard sheet auto-dismisses when hand reaches 7**
- File: `GoDeal/Views/Overlays/DiscardSheet.swift`
- Currently relies on the engine transitioning phase, but the sheet stays visible
- In `GameBoardView`, the `isShowingDiscardSheet` binding should become false when `hand.count <= 7`
- Fix: Add `.onChange(of: hand.count)` in DiscardSheet or observe phase change to auto-dismiss

---

## Group D: Property Display

**D1. Stacked properties — show only top card, keep all opaque**
- File: `GoDeal/Views/Game/PlayerPropertyView.swift` → `PropertySetView`
- Currently cards stack with offset so all names are semi-visible
- Fix: Show only the TOP card fully. For sets with wilds, split card display (half each color)
- Wild property cards should stay as-is (rainbow)
- Consider showing a count badge "×3" instead of stacking

---

## Group E: Action Cards & Game Logic

**E1. Quick Grab menu doesn't work**
- Files: `GoDeal/Views/Game/GameBoardView.swift`, `GoDeal/Engine/ActionResolver.swift`
- Quick Grab should show a picker of the target's individual properties to steal
- Current flow: play action → awaitingResponse → acceptAction → awaitingPropertyChoice → resolvePropertyChoice
- Check that `ActionTargetSheet` and `PropertyChoiceSheet` are wired up for quickGrab
- May need a `PropertyChoiceSheet` that shows individual cards from the target's sets

**E2. No Deal card breaks game — CPU never ends its turn**
- Files: `GoDeal/Engine/GameEngine.swift` → `playNoDeal()`, `GoDeal/AI/CPUPlayer.swift`
- After `playNoDeal`, `state.phase` returns to `.playing`. Then `triggerCPUIfNeeded()` is called.
- Bug: If it's the CPU's turn after No Deal, the CPU task may not be running
- Check: `playNoDeal` in `GameViewModel` calls `triggerCPUIfNeeded()` — verify this fires correctly
- Also check `CPUPlayer.executeTurn()` handles the case where it resumes after No Deal

**E3. Accepting action (not playing No Deal) also breaks game**
- Same root cause as E2 — after `acceptAction()`, game gets stuck
- Check `GameEngine.acceptAction()` → `executeQueuedAction()` → state transitions
- Then `triggerCPUIfNeeded()` must fire and CPU must see the correct phase

**E4. Greyed-out unavailable actions**
- Files: `GoDeal/Views/Game/GameBoardView.swift` → `handleCardPlay`
- Corner Store / Tower Block: grey out if no complete set owned
- Check engine/ActionResolver for the condition: player must have a complete set for cornerStore, complete set + cornerStore for towerBlock
- Visual: reduce opacity and show "No complete set" toast on tap attempt

**E5. "Everyone Pays" and multi-target rent should NOT prompt for victim selection**
- File: `GoDeal/Views/Game/GameBoardView.swift` → `handleCardPlay` for `.rent` and `.wildRent`
- `wildRent` charges ALL players — remove target selection, call `engine.playCard(cardId:, as: .rent(nil))` directly
- For `rent([colors])` (two-color card that charges everyone), also skip target selection
- For "Collect Now" (single target), KEEP target selection

---

## Group F: UI Polish

**F1. Show individual bank cards (scrollable)**
- File: `GoDeal/Views/Game/BankView.swift`
- Already has a `fullView` with scrollable money chips — but only showing in compact mode in GameBoardView
- Fix: In the human player section of GameBoardView, show `BankView(player:, compact: false)` or allow tap-to-expand
- Or add a dedicated bank section below properties

**F2. Action cards colored distinctly**
- File: `GoDeal/Views/Game/CardView.swift` → `cardBackground`
- Each `ActionType` should have a distinct color not used by properties
- Suggested palette (avoids all 10 property colors):
  - dealSnatcher → deep red (#CC0000)
  - noDeal → charcoal/dark gray
  - quickGrab → teal
  - swapIt → magenta/hot pink
  - collectNow → gold/amber
  - bigSpender → lime green
  - dealForward → sky blue
  - doubleUp → purple
  - cornerStore → warm brown/sienna
  - towerBlock → navy

**F3. Rent cards colored by their property color**
- File: `GoDeal/Views/Game/CardView.swift` → `cardBackground`
- For `.rent([colors])`, use the color of the associated properties (or split gradient for 2-color)
- Wild rent keeps its current red-orange-yellow gradient
- For single-color rent, use that property's `uiColor`

**F4. Playing image shouldn't hide the dollar value**
- File: `GoDeal/Views/Game/CardView.swift` → `cardFront` with custom image
- Currently custom image fills the card and the label only shows the name at bottom
- Fix: Overlay the `$XM` value in the top-left corner even when custom image is shown

---

## Group G: Customization

**G1. Customization by card category, not individual cards**
- File: `GoDeal/Customization/CardCustomizationView.swift`
- Instead of listing all 110 cards, group by type:
  - Each action type (one image applies to all copies of that action)
  - Each property color (one image per district, applied to all cards of that color)
  - Money denominations ($1M, $2M, etc.)
- Asset key for category: use a canonical key per category (e.g., `card_action_noDeal`, `card_prop_rustDistrict`, `card_money_5`)

**G2. Don't show internal asset key in customization UI**
- File: `GoDeal/Customization/CardCustomizationView.swift` → `CardCustomizationRow`
- Remove the `Text(card.assetKey)` line

**G3. Crop/resize image to standard card ratio on upload**
- File: `GoDeal/Customization/CardCustomizationView.swift`, `GoDeal/Customization/CardImageStore.swift`
- Card ratio is 5:7 (width:height) based on our CardView sizes (80×112 normal)
- After picking photo, present a crop UI before saving
- Use `UIGraphicsImageRenderer` to resize+crop to standard dimensions before saving

---

## Files Reference
- Main game view: `GoDeal/Views/Game/GameBoardView.swift`
- Card rendering: `GoDeal/Views/Game/CardView.swift`
- Hand view: `GoDeal/Views/Game/PlayerHandView.swift`
- Property view: `GoDeal/Views/Game/PlayerPropertyView.swift`
- Bank view: `GoDeal/Views/Game/BankView.swift`
- Deck area: `GoDeal/Views/Game/DeckAreaView.swift`
- Game engine: `GoDeal/Engine/GameEngine.swift`
- Action resolver: `GoDeal/Engine/ActionResolver.swift`
- Payment resolver: `GoDeal/Engine/PaymentResolver.swift`
- AI player: `GoDeal/AI/CPUPlayer.swift`
- AI strategy: `GoDeal/AI/AIStrategy.swift`
- VM: `GoDeal/ViewModels/GameViewModel.swift`
- Discard sheet: `GoDeal/Views/Overlays/DiscardSheet.swift`
- No Deal sheet: `GoDeal/Views/Overlays/NoDealResponseSheet.swift`
- Action target: `GoDeal/Views/Overlays/ActionTargetSheet.swift`
- Customization: `GoDeal/Customization/CardCustomizationView.swift`, `CardImageStore.swift`
