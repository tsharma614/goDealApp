# Go! Deal! — iOS Card Game

## Project
- **Name**: Go! Deal!  |  **Bundle ID**: com.tanmaysharma.godeal
- **iOS Target**: 18+  |  **Swift**: 5.9+  |  **UI**: SwiftUI, MVVM
- **No third-party dependencies**

## Folder Structure
```
GoDeal/
├── App/          # GoDealApp.swift, ContentView.swift
├── Models/       # Card, PropertyColor, PropertySet, Player, GameState, DeckBuilder, PropertyNameStore
├── Engine/       # GameEngine, ActionResolver, PaymentResolver, WinChecker
├── AI/           # CPUPlayer, AIStrategy
├── ViewModels/   # GameViewModel, CustomizationViewModel
├── Views/
│   ├── Menu/     # MainMenuView, GameSetupView
│   ├── Game/     # GameBoardView, CardView, PlayerHandView, PlayerPropertyView, OpponentAreaView, DeckAreaView, BankView
│   └── Overlays/ # ActionTargetSheet, PaymentSheet, NoDealResponseSheet, DiscardSheet
└── Customization/ # CardCustomizationView, PropertyNameEditorView, CardImageStore, PropertyNameStore
GoDealTests/       # DeckBuilderTests, GameEngineTests, WinCheckerTests
```

## Key Facts
- **Win condition**: 3 complete property sets
- **Players**: 1 human vs 1 CPU (architecture supports 2–4)
- **Card limit per turn**: 3 cards max (draw 2 at start, 5 if hand empty)
- **Hand limit**: 7 cards at end of turn
- **Custom images**: Stored in Documents/{assetKey}.jpg|png
- **Custom street names**: Stored in UserDefaults under `streetNames.{color.rawValue}`

## Debugging with Logs
- **Always use game logs to diagnose bugs before making code changes.** Check the log file first.
- Log file location: `~/Library/Developer/CoreSimulator/Devices/86758717-E7D8-4C6A-A6FC-FF74391D1A30/data/Containers/Data/Application/*/Documents/godeal_game.log`
- Use `GameLogger.shared.event(...)` for normal events and `.warn(...)` for unexpected states.
- Once bugs are fixed and verified, clear the log: `> path/to/godeal_game.log`

## See Also
- `.claude/coding.md` — MVVM patterns, GameEngine rules, naming conventions
- `.claude/testing.md` — Test targets, how to run, what each test covers
