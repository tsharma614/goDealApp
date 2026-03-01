import SwiftUI

// MARK: - Game Board View
// The main game screen. Laid out top-to-bottom:
//   Opponents → Deck area → Player properties → Player hand → Controls

struct GameBoardView: View {
    @Environment(GameViewModel.self) private var viewModel
    /// Called when the user taps the gear icon to return to the main menu.
    var onExit: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCardId: UUID? = nil
    @State private var showPlayAgainSetup = false
    @State private var pendingCard: Card? = nil       // triggers ActionTargetSheet via sheet(item:)
    @State private var pendingWildCard: Card? = nil   // triggers WildPropertyColorPicker via sheet(item:)
    @State private var showActionBankDialog = false
    @State private var pendingActionCard: Card? = nil
    @State private var showLogSheet = false
    @State private var pendingImprovementCard: Card? = nil  // corner store / tower block multi-set picker

    // Double rent prompt state
    @State private var showDoubleRentDialog = false
    @State private var pendingRentCard: Card? = nil
    @State private var pendingRentColor: PropertyColor? = nil
    @State private var pendingRentTargetIdx: Int? = nil

    // Rent color picker (shown before target selection)
    @State private var pendingRentColorPickCard: Card? = nil
    @State private var pendingRentColorChoices: [PropertyColor] = []
    @State private var pendingRentIsWild: Bool = false   // true = wildRent → needs target after color pick

    // Pre-action steal flow: human picks the specific card BEFORE target is prompted
    @State private var preActionCard: Card? = nil     // triggers pre-action PropertyPickerSheet
    @State private var preActionTargetIdx: Int? = nil

    // Wild reassignment state
    @State private var longPressedSet: PropertySet? = nil
    @State private var wildToReassign: Card? = nil    // nested sheet inside longPressedSet sheet

    private let logger = GameLogger.shared

    var body: some View {
        @Bindable var vm = viewModel

        GeometryReader { geo in
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(UIColor.systemBackground), Color.green.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar
                    topBar
                        .padding(.horizontal)
                        .padding(.vertical, 6)

                    // Opponents
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.state.players.indices, id: \.self) { idx in
                                if idx != viewModel.localPlayerIndex {
                                    OpponentAreaView(
                                        player: viewModel.state.players[idx],
                                        isCurrentTurn: viewModel.state.currentPlayerIndex == idx
                                    )
                                    .frame(width: max(geo.size.width - 40, 280))
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: 200)

                    Divider().padding(.vertical, 4)

                    // Deck + discard + activity feed in the middle
                    DeckAreaView(
                        deckCount: viewModel.state.deck.count,
                        topDiscard: viewModel.state.discardPile.last,
                        recentActivity: logger.activityFeed
                    )
                    .frame(height: 120)
                    .padding(.top, 6)

                    Divider().padding(.vertical, 4)

                    // Human player properties
                    if let humanPlayer = viewModel.humanPlayer {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Your Properties")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Label("\(humanPlayer.completedSets)/3 sets", systemImage: "house.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(humanPlayer.completedSets >= 2 ? .orange : .secondary)
                            }
                            .padding(.horizontal)

                            PlayerPropertyView(
                                player: humanPlayer,
                                isInteractive: true,
                                onPropertyTap: { _, _ in },
                                onLongPress: viewModel.isHumanTurn ? { set in longPressedSet = set } : nil
                            )
                            .frame(height: 130)
                            .padding(.horizontal, 4)

                            BankView(player: humanPlayer, compact: false)
                                .padding(.horizontal, 4)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // Human hand
                    if let humanPlayer = viewModel.humanPlayer {
                        PlayerHandView(
                            cards: humanPlayer.hand,
                            canPlay: viewModel.isHumanTurn && viewModel.state.canPlayCard,
                            selectedCardId: selectedCardId,
                            onCardTap: { card in
                                handleCardTap(card)
                            },
                            onCardPlay: { card in
                                handleCardPlay(card)
                            }
                        )
                    }

                    // Controls bar
                    controlsBar
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }

                // Game Over overlay
                if case .gameOver(let winnerIdx) = viewModel.state.phase {
                    gameOverOverlay(winnerName: viewModel.state.players[winnerIdx].name)
                }
            }
        }
        .sheet(isPresented: $vm.isShowingNoDealSheet, onDismiss: {
            // If the sheet was swiped away without choosing, auto-accept so game never freezes
            if case .awaitingResponse(let targetIdx, _, _) = viewModel.state.phase,
               targetIdx == viewModel.localPlayerIndex {
                viewModel.acceptAction()
            }
        }) {
            if let card = viewModel.pendingActionCard {
                NoDealResponseSheet(
                    actionCard: card,
                    attackerName: viewModel.pendingNoDealAttackerName,
                    actionDetail: viewModel.pendingNoDealActionDetail,
                    noDealCards: viewModel.pendingNoDealCards,
                    onPlayNoDeal: { viewModel.playNoDeal(cardId: $0) },
                    onAccept: { viewModel.acceptAction() }
                )
                .presentationDetents([.medium, .large])
            } else {
                // Sheet presented but context is missing — log and auto-dismiss
                Color.clear.onAppear {
                    logger.error("NoDeal sheet blank — pendingActionCard=nil, phase=\(String(describing: viewModel.state.phase))")
                    vm.isShowingNoDealSheet = false
                }
            }
        }
        .sheet(item: $pendingCard) { card in
            ActionTargetSheet(
                actionCard: card,
                players: viewModel.state.players,
                currentPlayerIndex: viewModel.state.currentPlayerIndex,
                onSelectTarget: { targetIdx in
                    // quickGrab / dealSnatcher / swapIt: let human pick the exact property
                    // BEFORE the card is played so they can cancel without losing the card.
                    if case .action(.quickGrab) = card.type {
                        pendingCard = nil
                        preActionTargetIdx = targetIdx
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            preActionCard = card
                        }
                        return
                    }
                    if case .action(.dealSnatcher) = card.type {
                        pendingCard = nil
                        preActionTargetIdx = targetIdx
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            preActionCard = card
                        }
                        return
                    }
                    if case .action(.swapIt) = card.type {
                        pendingCard = nil
                        preActionTargetIdx = targetIdx
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            preActionCard = card
                        }
                        return
                    }

                    if case .wildRent = card.type {
                        // Rent Blitz! — use the color chosen in the rent color picker
                        if let color = pendingRentColor {
                            viewModel.playRent(cardId: card.id, color: color, targetPlayerIndex: targetIdx)
                        }
                        pendingRentColor = nil
                    } else {
                        viewModel.playAction(cardId: card.id, targetPlayerIndex: targetIdx)
                    }
                    pendingCard = nil
                    selectedCardId = nil
                },
                onCancel: {
                    pendingCard = nil
                    pendingRentColor = nil
                    selectedCardId = nil
                },
                onBank: {
                    viewModel.playToBank(cardId: card.id)
                    pendingCard = nil
                    pendingRentColor = nil
                    selectedCardId = nil
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $pendingWildCard) { card in
            WildPropertyColorPicker(
                card: card,
                onSelect: { color in
                    pendingWildCard = nil
                    viewModel.playWildProperty(cardId: card.id, color: color)
                    selectedCardId = nil
                },
                onCancel: {
                    pendingWildCard = nil
                    selectedCardId = nil
                }
            )
            .presentationDetents([.large])
        }
        .sheet(item: $pendingRentColorPickCard) { card in
            RentColorPickerSheet(
                card: card,
                availableColors: pendingRentColorChoices,
                playerProperties: viewModel.humanPlayer?.properties ?? [:],
                onSelect: { color in
                    pendingRentColorPickCard = nil
                    if pendingRentIsWild {
                        // Rent Blitz! — needs target player next. Store color, then open ActionTargetSheet after delay.
                        pendingRentColor = color
                        if canOfferDoubleRent {
                            pendingRentCard = card
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                showDoubleRentDialog = true
                            }
                        } else {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                pendingCard = card
                            }
                        }
                    } else {
                        // Collect Dues! — play directly or offer double rent
                        if canOfferDoubleRent {
                            pendingRentCard = card
                            pendingRentColor = color
                            showDoubleRentDialog = true
                        } else {
                            viewModel.playRent(cardId: card.id, color: color, targetPlayerIndex: nil)
                            selectedCardId = nil
                        }
                    }
                },
                onCancel: {
                    pendingRentColorPickCard = nil
                    selectedCardId = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $vm.isShowingPropertyChoiceSheet) {
            if case .awaitingPropertyChoice(let chooserIdx, let purpose) = viewModel.state.phase,
               chooserIdx == viewModel.localPlayerIndex {
                let targetIdx: Int = {
                    switch purpose {
                    case .quickGrab(let idx): return idx
                    case .dealSnatcher(let idx): return idx
                    case .swapIt(let idx): return idx
                    case .quickGrabVictim(let attackerIdx): return attackerIdx
                    case .dealSnatcherVictim(let attackerIdx): return attackerIdx
                    case .swapItVictim(let attackerIdx): return attackerIdx
                    default: return 0
                    }
                }()
                PropertyPickerSheet(
                    purpose: purpose,
                    humanPlayer: viewModel.state.players[viewModel.localPlayerIndex],
                    targetPlayer: viewModel.state.players[targetIdx],
                    onResolve: { cardId, color, secondaryId in
                        viewModel.resolvePropertyChoice(
                            purpose: purpose,
                            selectedCardId: cardId,
                            selectedColor: color,
                            secondaryCardId: secondaryId
                        )
                    },
                    onCancel: {
                        // Must resolve the engine phase, not just hide the sheet.
                        // Passing nil selections skips the action and returns to .playing.
                        viewModel.resolvePropertyChoice(purpose: purpose)
                    }
                )
                .presentationDetents([PresentationDetent.large])
            } else {
                // Sheet presented but phase condition not met — log and auto-dismiss
                Color.clear.onAppear {
                    logger.error("PropertyChoice sheet blank — phase=\(String(describing: viewModel.state.phase))")
                    vm.isShowingPropertyChoiceSheet = false
                }
            }
        }
        // Pre-action steal picker: human chooses specific card BEFORE the action card is played
        .sheet(item: $preActionCard) { card in
            if let targetIdx = preActionTargetIdx,
               let humanPlayer = viewModel.humanPlayer,
               targetIdx < viewModel.state.players.count {
                let targetPlayer = viewModel.state.players[targetIdx]
                let purpose: PropertyChoicePurpose = {
                    if case .action(.quickGrab) = card.type { return .quickGrab(targetPlayerIndex: targetIdx) }
                    if case .action(.dealSnatcher) = card.type { return .dealSnatcher(targetPlayerIndex: targetIdx) }
                    return .swapIt(targetPlayerIndex: targetIdx)
                }()
                PropertyPickerSheet(
                    purpose: purpose,
                    humanPlayer: humanPlayer,
                    targetPlayer: targetPlayer,
                    onResolve: { selectedPropId, selectedColor, secondaryPropId in
                        preActionCard = nil
                        preActionTargetIdx = nil

                        viewModel.playActionWithPreSelection(
                            cardId: card.id,
                            targetPlayerIndex: targetIdx,
                            stealCardId: selectedPropId,
                            stealColor: selectedColor,
                            stealSecondaryCardId: secondaryPropId
                        )
                        selectedCardId = nil
                    },
                    onCancel: {
                        // Card stays in hand — no action taken
                        preActionCard = nil
                        preActionTargetIdx = nil
                        selectedCardId = nil
                    }
                )
                .presentationDetents([.large])
            } else {
                // Guard failed (targetIdx nil or out of range) — log and auto-dismiss
                Color.clear.onAppear {
                    logger.error("Pre-action steal sheet blank — preActionTargetIdx=\(String(describing: preActionTargetIdx)) players=\(viewModel.state.players.count)")
                    preActionCard = nil
                    preActionTargetIdx = nil
                }
            }
        }
        .sheet(isPresented: $vm.isShowingPaymentSheet) {
            if let humanPlayer = viewModel.humanPlayer,
               let creditorIdx = viewModel.pendingPaymentCreditorIndex,
               let reason = viewModel.pendingPaymentReason,
               creditorIdx < viewModel.state.players.count {
                let creditor = viewModel.state.players[creditorIdx]
                PaymentSheet(
                    debtor: humanPlayer,
                    creditor: creditor,
                    amountOwed: viewModel.pendingPaymentAmount,
                    reason: reason,
                    onPay: { bankIds, propIds in
                        viewModel.submitHumanPayment(bankCardIds: bankIds, propertyCardIds: propIds)
                    }
                )
                .presentationDetents([.large])
                .interactiveDismissDisabled()
            } else {
                // Sheet presented but context is missing — log and auto-dismiss
                Color.clear.onAppear {
                    logger.error("Payment sheet blank — creditorIdx=\(String(describing: viewModel.pendingPaymentCreditorIndex)) reason=\(String(describing: viewModel.pendingPaymentReason))")
                    vm.isShowingPaymentSheet = false
                }
            }
        }
        .sheet(isPresented: $vm.isShowingDiscardSheet) {
            if let humanPlayer = viewModel.humanPlayer {
                let excess = humanPlayer.hand.count - 7
                DiscardSheet(
                    hand: humanPlayer.hand,
                    mustDiscard: max(0, excess),
                    onDiscard: { viewModel.discard(cardId: $0) },
                    onPlayMore: viewModel.state.cardsPlayedThisTurn < 3 ? { viewModel.cancelDiscard() } : nil
                )
                .presentationDetents([.large])
            }
        }
        .confirmationDialog(
            pendingActionCard.map { "Play \($0.name)?" } ?? "Play card?",
            isPresented: $showActionBankDialog,
            titleVisibility: .visible
        ) {
            if let card = pendingActionCard {
                Button("Bank it ($\(card.monetaryValue)M)") {
                    viewModel.playToBank(cardId: card.id)
                    pendingActionCard = nil
                    selectedCardId = nil
                }
                if pendingActionCanPlay {
                    Button("Play as action") {
                        let myProps = viewModel.humanPlayer?.properties ?? [:]
                        let isCornerStore: Bool = { if case .action(.cornerStore) = card.type { return true }; return false }()
                        let eligibleCount = isCornerStore
                            ? myProps.filter { $0.value.canAddCornerStore }.count
                            : myProps.filter { $0.value.canAddTowerBlock }.count
                        pendingActionCard = nil
                        if eligibleCount > 1 {
                            // Multiple eligible sets — let user pick which one
                            pendingImprovementCard = card
                        } else {
                            viewModel.playAction(cardId: card.id)
                            selectedCardId = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) { pendingActionCard = nil }
            }
        }
        .confirmationDialog(
            "Double the Rent?",
            isPresented: $showDoubleRentDialog,
            titleVisibility: .visible
        ) {
            if let rentCard = pendingRentCard {
                Button("Double it! (costs 1 extra action)") {
                    // Auto-play Double Up card first, then proceed with rent
                    if let doubleUpCard = doubleUpCardInHand {
                        viewModel.playAction(cardId: doubleUpCard.id)
                    }
                    commitRent(rentCard)
                }
                Button("No, just collect normally") { commitRent(rentCard) }
                Button("Cancel", role: .cancel) {
                    pendingRentCard = nil
                    pendingRentColor = nil
                    pendingRentTargetIdx = nil
                }
            }
        } message: {
            if let rentCard = pendingRentCard {
                let rent = pendingRentColor.flatMap { viewModel.humanPlayer?.properties[$0]?.currentRent } ?? 0
                if case .rent = rentCard.type {
                    Text("Double Up uses 1 extra action. Doubled rent: $\(rent * 2)M from all players.")
                } else {
                    Text("Double Up uses 1 extra action. Choose target to double their rent.")
                }
            }
        }
        // Wild reassignment: long-press set → choose wild → pick new color
        .sheet(item: $longPressedSet) { set in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Long press a wild card to move it to another district — free action.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        let wilds = set.properties.filter { if case .wildProperty = $0.type { return true }; return false }
                        let normals = set.properties.filter { if case .wildProperty = $0.type { return false }; return true }

                        if !wilds.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Wild cards (tap to reassign):")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(wilds) { card in
                                            Button {
                                                wildToReassign = card
                                                // Don't nil longPressedSet — use nested sheet instead
                                            } label: {
                                                VStack(spacing: 4) {
                                                    CardView(card: card, size: .normal)
                                                    Text("Tap to move")
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        if !normals.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Regular properties:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(normals) { card in CardView(card: card, size: .normal) }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .navigationTitle("\(set.color.displayName) Set")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { longPressedSet = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            // Nested sheet: color picker for wild reassignment (avoids chained-sheet blank bug)
            .sheet(item: $wildToReassign) { card in
                WildPropertyColorPicker(
                    card: card,
                    onSelect: { color in
                        viewModel.reassignWild(cardId: card.id, toColor: color)
                        wildToReassign = nil
                        longPressedSet = nil
                    },
                    onCancel: {
                        wildToReassign = nil
                    }
                )
                .presentationDetents([.large])
            }
        }
        .alert("Can't play that", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showPlayAgainSetup) {
            GameSetupView { setup in
                showPlayAgainSetup = false
                viewModel.newGame(setup: setup)
                selectedCardId = nil
            }
        }
        // Improvement card picker: shown when player has multiple eligible sets
        .sheet(item: $pendingImprovementCard) { card in
            let isCornerStore: Bool = { if case .action(.cornerStore) = card.type { return true }; return false }()
            let eligible: [PropertyColor] = {
                let props = viewModel.humanPlayer?.properties ?? [:]
                if isCornerStore {
                    return props.filter { $0.value.canAddCornerStore }.keys.sorted { $0.displayName < $1.displayName }
                } else {
                    return props.filter { $0.value.canAddTowerBlock }.keys.sorted { $0.displayName < $1.displayName }
                }
            }()
            NavigationStack {
                List {
                    ForEach(eligible, id: \.self) { color in
                        let set = viewModel.humanPlayer?.properties[color]
                        Button {
                            pendingImprovementCard = nil
                            viewModel.playAction(cardId: card.id, targetPropertyColor: color)
                            selectedCardId = nil
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(color.uiColor).frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(color.displayName).font(.body.weight(.semibold))
                                    Text("\(set?.properties.count ?? 0)/\(color.setSize) properties · $\(set?.currentRent ?? 0)M rent")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationTitle(isCornerStore ? "Add Corner Store" : "Add Tower Block")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { pendingImprovementCard = nil }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        // Multiplayer: guest confirms play-again request from host
        .alert("Play Again?", isPresented: $vm.showPlayAgainConfirmation) {
            Button("Accept") { viewModel.confirmPlayAgain() }
            Button("Decline", role: .cancel) { vm.showPlayAgainConfirmation = false }
        } message: {
            Text("The host wants to play another round with the same players.")
        }
        .onChange(of: viewModel.state.phase) { _, _ in
            viewModel.handlePhaseChange()
        }
        .onAppear {
            // Kick off phase handling on first display (onChange only fires on changes, not initial value).
            if case .drawing = viewModel.state.phase {
                if viewModel.networkSession != nil {
                    viewModel.handlePhaseChange()
                } else if !viewModel.isHumanTurn {
                    viewModel.triggerCPUIfNeeded()
                }
                // Solo human turn: Draw button is visible; no auto-draw
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Gear / back-to-menu button — sits beside the logo
            Button {
                if let onExit { onExit() } else { dismiss() }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)

            Text("Go! Deal!")
                .font(.headline.weight(.black))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )

            Spacer()

            // Turn info — always show player's actual name
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(viewModel.currentPlayer.name)'s Turn")
                    .font(.caption.weight(.semibold))
                Text("\(viewModel.state.cardsPlayedThisTurn)/3 cards · T\(viewModel.state.turnNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Debug log button (shows badge when issues exist)
            Button {
                showLogSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "ladybug")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if logger.issueCount > 0 {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .sheet(isPresented: $showLogSheet) {
            GameLogSheet()
                .presentationDetents([.large])
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 12) {
            // Draw button (start of turn)
            if viewModel.isHumanTurn, case .drawing = viewModel.state.phase {
                Button {
                    viewModel.startTurn()
                } label: {
                    Label("Draw Cards", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
            }

            // End turn button
            if viewModel.canEndTurn {
                Button {
                    viewModel.endTurn()
                    selectedCardId = nil
                } label: {
                    Label("End Turn", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
            }

            // Deselect
            if selectedCardId != nil {
                Button {
                    selectedCardId = nil
                } label: {
                    Label("Deselect", systemImage: "xmark.circle")
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Game Over

    private func gameOverOverlay(winnerName: String) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)

                Text(winnerName == viewModel.humanPlayer?.name ? "You Win!" : "\(winnerName) Wins!")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(.white)

                Text("3 complete property sets!")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                if viewModel.networkSession != nil {
                    // Multiplayer: coordinate with all players
                    if viewModel.isHost {
                        if viewModel.isWaitingForPlayAgain {
                            Text("Waiting for others…")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                            Button("Cancel") { viewModel.cancelWaitingForPlayAgain() }
                                .foregroundStyle(.white.opacity(0.5))
                        } else {
                            Button {
                                viewModel.requestPlayAgain()
                            } label: {
                                Text("Play Again")
                                    .font(.headline)
                                    .frame(width: 200)
                                    .padding()
                                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(.black)
                            }
                        }
                    } else {
                        Text("Waiting for host…")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    // Solo: open setup screen
                    Button {
                        showPlayAgainSetup = true
                    } label: {
                        Text("Play Again")
                            .font(.headline)
                            .frame(width: 200)
                            .padding()
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(40)
        }
    }

    // MARK: - Card Interaction

    // True when the pending action card can actually be played (not just banked)
    private var pendingActionCanPlay: Bool {
        guard let card = pendingActionCard else { return true }
        switch card.type {
        case .action(.cornerStore):
            return !(viewModel.humanPlayer?.properties.filter { $0.value.canAddCornerStore }.isEmpty ?? true)
        case .action(.towerBlock):
            return !(viewModel.humanPlayer?.properties.filter { $0.value.canAddTowerBlock }.isEmpty ?? true)
        case .rent(let colors):
            // Can only play if player owns at least one property in the valid colors
            let myProps = viewModel.humanPlayer?.properties ?? [:]
            return colors.contains { myProps[$0]?.properties.isEmpty == false }
        default:
            return true
        }
    }

    // True when human has a Double Up card AND enough action slots (rent + doubleUp = 2 actions)
    private var canOfferDoubleRent: Bool {
        guard viewModel.state.cardsPlayedThisTurn <= 1 else { return false }
        return doubleUpCardInHand != nil
    }

    private var doubleUpCardInHand: Card? {
        viewModel.humanPlayer?.hand.first { if case .action(.doubleUp) = $0.type { return true }; return false }
    }

    /// Actually execute the rent card after the double-rent dialog resolves.
    private func commitRent(_ card: Card) {
        pendingRentCard = nil
        pendingRentTargetIdx = nil
        selectedCardId = nil
        if case .rent = card.type, let color = pendingRentColor {
            pendingRentColor = nil
            viewModel.playRent(cardId: card.id, color: color, targetPlayerIndex: nil)
        } else if case .wildRent = card.type {
            // Still need target — open ActionTargetSheet.
            // Keep pendingRentColor set so ActionTargetSheet.onSelectTarget can use it.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                pendingCard = card
            }
        }
    }

    private func handleCardTap(_ card: Card) {
        withAnimation(.spring(response: 0.2)) {
            selectedCardId = card.id
        }
    }

    private func handleCardPlay(_ card: Card) {
        guard viewModel.isHumanTurn, viewModel.state.canPlayCard else { return }

        switch card.type {
        case .money:
            viewModel.playToBank(cardId: card.id)
            selectedCardId = nil

        case .property(let color):
            viewModel.playProperty(cardId: card.id, color: color)
            selectedCardId = nil

        case .wildProperty(let colors):
            guard !colors.isEmpty else {
                viewModel.errorMessage = "This wild card has no valid district."
                return
            }
            if colors.count == 1 {
                viewModel.playWildProperty(cardId: card.id, color: colors[0])
                selectedCardId = nil
            } else {
                pendingWildCard = card
            }

        case .action(let type):
            switch type {
            case .noDeal:
                return
            case .cornerStore, .towerBlock:
                // Always show dialog — user can bank even without an eligible set
                pendingActionCard = card
                showActionBankDialog = true
            case .dealForward, .bigSpender, .doubleUp:
                // No target needed — offer bank or play
                pendingActionCard = card
                showActionBankDialog = true
            default:
                // Target-needing actions (collectNow, quickGrab, dealSnatcher, swapIt):
                // Go directly to ActionTargetSheet — skipping the dialog avoids SwiftUI's
                // two-step sheet presentation bug that causes blank modals.
                pendingCard = card
            }

        case .rent(let colors):
            // Collect Dues! — charges ALL players. Let player pick which of their valid colors to use.
            let myProps = viewModel.humanPlayer?.properties ?? [:]
            let ownedColors = colors.filter { myProps[$0]?.properties.isEmpty == false }
            if ownedColors.isEmpty {
                // No matching properties — only option is to bank the card
                pendingActionCard = card
                showActionBankDialog = true
                return
            }
            if ownedColors.count == 1, let color = ownedColors.first {
                // Only one valid color — auto-select it
                if canOfferDoubleRent {
                    pendingRentCard = card
                    pendingRentColor = color
                    showDoubleRentDialog = true
                } else {
                    viewModel.playRent(cardId: card.id, color: color, targetPlayerIndex: nil)
                    selectedCardId = nil
                }
            } else {
                // Multiple valid colors — show picker
                pendingRentIsWild = false
                pendingRentColorChoices = ownedColors.sorted {
                    (myProps[$0]?.currentRent ?? 0) > (myProps[$1]?.currentRent ?? 0)
                }
                pendingRentColorPickCard = card
            }

        case .wildRent:
            // Rent Blitz! — charges ONE player for any color. Pick color first, then target.
            let myProps = viewModel.humanPlayer?.properties ?? [:]
            let ownedColors = myProps.keys
                .filter { myProps[$0]?.properties.isEmpty == false }
                .sorted { (myProps[$0]?.currentRent ?? 0) > (myProps[$1]?.currentRent ?? 0) }
            if ownedColors.isEmpty {
                viewModel.errorMessage = "You don't own any properties to charge rent for."
                return
            }
            pendingRentIsWild = true
            pendingRentColorChoices = ownedColors
            pendingRentColorPickCard = card
        }
    }
}

// MARK: - Rent Color Picker Sheet

struct RentColorPickerSheet: View {
    let card: Card
    let availableColors: [PropertyColor]
    let playerProperties: [PropertyColor: PropertySet]
    let onSelect: (PropertyColor) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CardView(card: card, size: .normal)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                Text("Which district to charge rent for?")
                    .font(.headline)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(availableColors, id: \.self) { color in
                            let set = playerProperties[color]
                            let rent = set?.currentRent ?? 0
                            let count = set?.properties.count ?? 0
                            Button {
                                onSelect(color)
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(color.uiColor)
                                        .frame(width: 22, height: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(color.displayName)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("\(count)/\(color.setSize) properties")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("$\(rent)M")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.green)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(color.uiColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Collect Rent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

// MARK: - Wild Property Color Picker

struct WildPropertyColorPicker: View {
    let card: Card
    let onSelect: (PropertyColor) -> Void
    let onCancel: () -> Void

    var validColors: [PropertyColor] {
        if case .wildProperty(let colors) = card.type { return colors }
        return []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CardView(card: card, size: .large)
                        .padding(.top)

                    Text("Which district to place in?")
                        .font(.headline)

                    ForEach(validColors, id: \.self) { color in
                        Button {
                            onSelect(color)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(color.uiColor)
                                    .frame(width: 20, height: 20)
                                Text(color.displayName)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("Rent: \(color.rentTable.prefix(color.setSize).map { "$\($0)M" }.joined(separator: "/"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(color.uiColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.uiColor.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 20)
                }
                .padding(.bottom)
            }
            .navigationTitle("Place Wild Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

#Preview {
    GameBoardView()
        .environment(GameViewModel())
}
