# Go! Deal!

A fast-paced iOS card game inspired by Monopoly Deal. Collect 3 complete property sets before your opponents to win.

## Features

- **Solo play** — 1–3 CPU opponents with Easy and Medium AI difficulty
- **Local multiplayer** — play with friends on the same WiFi via Multipeer Connectivity (no internet required)
- **Online multiplayer** — play with friends anywhere using a 6-character room code powered by Game Center
- **10 property colors** with authentic rent tables
- **Full action card set** — Quick Grab, Deal Snatcher, Swap It, Rent Blitz, Double Up, No Deal!, and more
- **Customization** — rename street properties and upload custom card images
- **Tutorial** — in-app How to Play guide

## Tech Stack

- **Platform**: iOS 18+
- **Language**: Swift 5.9+
- **UI**: SwiftUI (MVVM)
- **Networking**: MultipeerConnectivity (local) + GameKit / GKMatch (online)
- **No third-party dependencies**

## Project Structure

```
GoDeal/
├── App/            # Entry point, Info.plist
├── Models/         # Card, Player, GameState, DeckBuilder
├── Engine/         # GameEngine, ActionResolver, PaymentResolver, WinChecker
├── AI/             # CPUPlayer, AIStrategy
├── ViewModels/     # GameViewModel, CustomizationViewModel
├── Network/        # NetworkSession, MultipeerSession, GameKitSession, GameKitMatchmaker
├── Views/
│   ├── Menu/       # MainMenuView, GameSetupView, LobbyView, GameKitLobbyView, TutorialView
│   ├── Game/       # GameBoardView, CardView, PlayerHandView, PlayerPropertyView
│   └── Overlays/   # ActionTargetSheet, PaymentSheet, NoDealResponseSheet, DiscardSheet
└── Customization/  # CardCustomizationView, PropertyNameEditorView
GoDealTests/        # 55 unit tests covering deck, engine, win conditions
```

## Game Rules

- Draw 2 cards at the start of your turn (draw 5 if your hand is empty)
- Play up to 3 cards per turn — to your bank, property area, or as actions
- Discard down to 7 cards at end of turn
- First player to collect **3 complete property sets** wins
- Play **No Deal!** from your hand to cancel any action targeting you

## Bundle ID

`com.tanmaysharma.godeal`
