import SwiftUI
import UIKit

// MARK: - Game Board View
// The main game screen. Laid out top-to-bottom:
//   Opponents → Deck area → Player properties → Player hand → Controls

struct GameBoardView: View {
    @Environment(GameViewModel.self) private var viewModel
    /// Called when the user taps the gear icon to return to the main menu.
    var onExit: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Background task token — keeps MC session alive while the screen is off.
    @State private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    @State private var selectedCardId: UUID? = nil
    @State private var showPlayAgainSetup = false
    @State private var pendingCard: Card? = nil       // triggers ActionTargetSheet via sheet(item:)
    @State private var pendingWildCard: Card? = nil   // triggers WildPropertyColorPicker via sheet(item:)
    @State private var showActionBankDialog = false
    @State private var pendingActionCard: Card? = nil

    @State private var pendingImprovementCard: Card? = nil  // corner store / tower block multi-set picker
    @State private var drawFeedbackCount: Int? = nil         // "+N" badge shown briefly after drawing
    @State private var handCountBeforeDraw: Int = 0
    @State private var dealForwardPending: Bool = false
    @State private var propertyLostFlash: Bool = false        // red glow on whole properties section
    @State private var flashingPropertyColors: Set<PropertyColor> = []  // red border on individual sets

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
    // Both card + targetIdx bundled atomically so the sheet body never sees a partial state.
    struct PreActionState: Identifiable {
        let id = UUID()
        let card: Card
        let targetIdx: Int
    }
    @State private var preActionState: PreActionState? = nil

    // Wild reassignment state
    @State private var longPressedSet: PropertySet? = nil
    @State private var wildToReassign: Card? = nil    // nested sheet inside longPressedSet sheet

    private let logger = GameLogger.shared

    // Brand palette (matches main menu)
    private let orange     = Color(red: 0.96, green: 0.65, blue: 0.22)
    private let orangeDark = Color(red: 0.82, green: 0.48, blue: 0.08)
    private let blue       = Color(red: 0.22, green: 0.62, blue: 0.92)
    private let felt       = Color(red: 0.07, green: 0.20, blue: 0.12)

    var body: some View {
        @Bindable var vm = viewModel

        GeometryReader { geo in
            // Scale all fixed heights proportionally relative to iPhone 17 Pro (852pt) baseline.
            // This ensures the layout adapts continuously across all iPhone sizes without
            // any sudden jumps — from iPhone SE (667pt) through 16e (844pt) to Pro Max (956pt+).
            let h = geo.size.height
            let scale = min(max(h / 852.0, 0.80), 1.20)  // clamp ±20% from baseline
            let opponentCount = viewModel.state.players.count - 1
            let opponentMaxH: CGFloat = 185 * scale
            let deckH: CGFloat = 100 * scale
            let divPad: CGFloat = h < 750 ? 1 : h < 900 ? 2 : 3

            ZStack {
                // Felt background
                felt.ignoresSafeArea()
                Canvas { ctx, size in
                    let suits = ["♠", "♥", "♦", "♣"]
                    let step: CGFloat = 58
                    let rows = Int(size.height / step) + 3
                    let cols = Int(size.width  / step) + 3
                    for row in 0..<rows {
                        let xOffset: CGFloat = row % 2 == 0 ? 0 : step / 2
                        for col in 0..<cols {
                            let suit = suits[(row + col) % 4]
                            let x = CGFloat(col) * step + xOffset - step
                            let y = CGFloat(row) * step - step
                            ctx.draw(
                                Text(suit).font(.system(size: 20)).foregroundStyle(Color.white.opacity(0.045)),
                                at: CGPoint(x: x, y: y), anchor: .center
                            )
                        }
                    }
                }
                .ignoresSafeArea()
                RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 180, endRadius: 500)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar
                    topBar
                        .padding(.horizontal)
                        .padding(.vertical, h < 750 ? 3 : h < 900 ? 4 : 6)

                    // Opponents — single opponent fills full width; 2+ paginate at ~70% so
                    // the edge of the next card peeks into view hinting scrollability.
                    let opponentCardWidth: CGFloat = opponentCount > 1
                        ? max(geo.size.width * 0.72, 260)
                        : max(geo.size.width - 40, 280)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.state.players.indices, id: \.self) { idx in
                                if idx != viewModel.localPlayerIndex {
                                    OpponentAreaView(
                                        player: viewModel.state.players[idx],
                                        isCurrentTurn: viewModel.state.currentPlayerIndex == idx
                                    )
                                    .frame(width: opponentCardWidth)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: opponentMaxH)

                    Divider().padding(.vertical, divPad)

                    // Flexible spacers absorb any extra vertical space so the
                    // activity / deck section floats centered between the two dividers.
                    Spacer(minLength: 0)

                    DeckAreaView(
                        deckCount: viewModel.state.deck.count,
                        topDiscard: viewModel.state.discardPile.last,
                        recentActivity: logger.activityFeed
                    )
                    .frame(height: deckH)

                    Spacer(minLength: 0)

                    Divider().padding(.vertical, divPad)

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
                                flashingColors: flashingPropertyColors,
                                onPropertyTap: { _, _ in },
                                onLongPress: viewModel.isHumanTurn ? { set in longPressedSet = set } : nil
                            )
                            .frame(maxHeight: 130 * scale)
                            .padding(.horizontal, 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(propertyLostFlash ? 0.10 : 0))
                                    .allowsHitTesting(false)
                            )

                            BankView(player: humanPlayer, compact: false)
                                .padding(.horizontal, 4)
                        }
                    }

                    Divider().padding(.vertical, divPad)

                    // Human hand
                    if let humanPlayer = viewModel.humanPlayer {
                        PlayerHandView(
                            cards: humanPlayer.hand,
                            canPlay: viewModel.isHumanTurn && viewModel.state.canPlayCard,
                            selectedCardId: selectedCardId,
                            isCardPlayable: { card in viewModel.isCardLegallyPlayable(card) },
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
                        .padding(.vertical, h < 750 ? 3 : h < 900 ? 4 : 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .colorScheme(.dark)

                // Game Over overlay
                if case .gameOver(let winnerIdx) = viewModel.state.phase {
                    gameOverOverlay(winnerIndex: winnerIdx)
                }
            }
        }
        .sheet(isPresented: $vm.isShowingNoDealSheet, onDismiss: {
            // If the sheet was swiped away without the user tapping a button, auto-accept
            // so the game never freezes. Guard on noDealInteracted to prevent this firing
            // when onDismiss is triggered after a button tap (Accept/No Deal!) due to the
            // next awaitingResponse phase already being active at dismissal time.
            if !viewModel.noDealInteracted,
               case .awaitingResponse(let targetIdx, _, _) = viewModel.state.phase,
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
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            preActionState = PreActionState(card: card, targetIdx: targetIdx)
                        }
                        return
                    }
                    if case .action(.dealSnatcher) = card.type {
                        pendingCard = nil
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            preActionState = PreActionState(card: card, targetIdx: targetIdx)
                        }
                        return
                    }
                    if case .action(.swapIt) = card.type {
                        pendingCard = nil
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            preActionState = PreActionState(card: card, targetIdx: targetIdx)
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
        .sheet(item: $preActionState) { state in
            if let humanPlayer = viewModel.humanPlayer,
               state.targetIdx < viewModel.state.players.count {
                let card = state.card
                let targetIdx = state.targetIdx
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
                        preActionState = nil
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
                        preActionState = nil
                        selectedCardId = nil
                    }
                )
                .presentationDetents([.large])
            } else {
                // Guard failed — targetIdx out of range (shouldn't happen with atomic state)
                Color.clear.onAppear {
                    logger.error("Pre-action steal sheet blank — targetIdx=\(state.targetIdx) players=\(viewModel.state.players.count)")
                    preActionState = nil
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
                        let isCornerStore: Bool = { if case .action(.cornerStore) = card.type { return true }; return false }()
                        let isApartmentBuilding: Bool = { if case .action(.apartmentBuilding) = card.type { return true }; return false }()
                        pendingActionCard = nil
                        if isCornerStore || isApartmentBuilding {
                            let myProps = viewModel.humanPlayer?.properties ?? [:]
                            let eligibleCount = isCornerStore
                                ? myProps.filter { $0.value.canAddCornerStore }.count
                                : myProps.filter { $0.value.canAddApartmentBuilding }.count
                            if eligibleCount > 1 {
                                // Multiple eligible sets — let user pick which one
                                pendingImprovementCard = card
                            } else {
                                viewModel.playAction(cardId: card.id)
                                selectedCardId = nil
                            }
                        } else {
                            let isDealForward: Bool = {
                                if case .action(.dealForward) = card.type { return true }
                                return false
                            }()
                            if isDealForward {
                                handCountBeforeDraw = viewModel.humanPlayer?.hand.count ?? 0
                                dealForwardPending = true
                            }
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

                        // ── Rent & set-size summary ──────────────────────────────
                        VStack(spacing: 0) {
                            // Current rent row
                            HStack {
                                Label("Current rent", systemImage: "dollarsign.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("$\(set.currentRent)M")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(set.isComplete ? .green : .primary)
                            }
                            .padding()

                            Divider()

                            // Progress row
                            HStack {
                                Label("Properties", systemImage: "house.fill")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(set.properties.count) / \(set.color.setSize)")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(set.isComplete ? .green : .orange)
                                if set.isComplete {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding()

                            Divider()

                            // Full rent table — base tiers + improvements
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Rent table")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                // Build tiers based on color type.
                                // table[0..setSize-1] = partial tiers,
                                // table[2]            = complete set base (always, even for 2-card sets),
                                // table[3]            = + Corner Store,
                                // table[4]            = + Apartment Building.
                                let table = set.color.rentTable
                                let isTransit  = set.color == .transitLine
                                let isUtility  = set.color == .powerAndWater
                                let supportsImprovements = !isTransit && !isUtility

                                // Each tuple: (short label, rent, isActive)
                                let tiers: [(String, Int, Bool)] = {
                                    var rows: [(String, Int, Bool)] = []

                                    if isTransit {
                                        // 4 equal tiers, no improvements
                                        for i in 0..<4 {
                                            let active = set.isComplete ? i == 3 : set.properties.count == i + 1
                                            rows.append((i == 3 ? "Full" : "\(i+1)", table[i], active))
                                        }
                                    } else if isUtility {
                                        // 2 tiers, no improvements; complete uses table[2] by engine convention
                                        rows.append(("1", table[0], !set.isComplete && set.properties.count == 1))
                                        rows.append(("Full", table[2], set.isComplete))
                                    } else {
                                        // Partial tiers up to (setSize - 1) — 2-card sets have only 1 partial tier
                                        for i in 0..<(set.color.setSize - 1) {
                                            let active = !set.isComplete && set.properties.count == i + 1
                                            rows.append(("\(i+1)", table[i], active))
                                        }
                                        // Complete base (engine always uses table[2] for non-transit)
                                        let baseActive = set.isComplete && !set.hasCornerStore && !set.hasApartmentBuilding
                                        rows.append(("Full", table[2], baseActive))
                                        // Improvements
                                        rows.append(("+ CS", table[3], set.isComplete && set.hasCornerStore && !set.hasApartmentBuilding))
                                        rows.append(("+ AB", table[4], set.isComplete && set.hasApartmentBuilding))
                                    }

                                    return rows
                                }()

                                HStack(spacing: 3) {
                                    ForEach(Array(tiers.enumerated()), id: \.offset) { _, tier in
                                        let isActive = tier.2
                                        VStack(spacing: 2) {
                                            Text(tier.0)
                                                .font(.system(size: 9))
                                                .foregroundStyle(isActive ? .primary : .secondary)
                                                .multilineTextAlignment(.center)
                                                .minimumScaleFactor(0.7)
                                                .lineLimit(2)
                                            Text("$\(tier.1)M")
                                                .font(.caption.weight(isActive ? .bold : .regular))
                                                .foregroundStyle(isActive ? Color(set.color.uiColor) : .secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(isActive ? Color(set.color.uiColor).opacity(0.15) : Color.clear)
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            .padding()
                        }
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        // ── Cards in this set ────────────────────────────────────
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

                        Text("Long press a wild card to move it to a different district — free action.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
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
                    return props.filter { $0.value.canAddApartmentBuilding }.keys.sorted { $0.displayName < $1.displayName }
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
                .navigationTitle(isCornerStore ? "Add Corner Store" : "Add Apartment Building")
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
        // Multiplayer: a player dropped mid-game
        .alert("Player Disconnected", isPresented: $vm.playerDisconnectedAlert) {
            Button("End Game", role: .destructive) { onExit?() }
            Button("Keep Playing") { vm.playerDisconnectedAlert = false }
        } message: {
            Text("A player lost connection. You can keep playing without them or end the game.")
        }
        .onChange(of: viewModel.humanPropertyCardCounts) { old, new in
            // Find colors that lost cards (stolen or paid as debt)
            var lost: Set<PropertyColor> = []
            for (color, oldCount) in old {
                let newCount = new[color] ?? 0
                if newCount < oldCount { lost.insert(color) }
            }
            guard !lost.isEmpty else { return }
            SoundManager.steal()
            withAnimation(.easeIn(duration: 0.08)) {
                propertyLostFlash = true
                flashingPropertyColors = lost
            }
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.easeOut(duration: 0.35)) {
                    propertyLostFlash = false
                    flashingPropertyColors = []
                }
            }
        }
        .onChange(of: viewModel.state.phase) { oldPhase, _ in
            // Show "+N cards" badge when human finishes drawing
            if case .drawing = oldPhase, viewModel.isHumanTurn {
                let drawn = (viewModel.humanPlayer?.hand.count ?? 0) - handCountBeforeDraw
                if drawn > 0 {
                    withAnimation(.spring(response: 0.3)) {
                        drawFeedbackCount = drawn
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        withAnimation(.easeOut(duration: 0.4)) {
                            drawFeedbackCount = nil
                        }
                    }
                }
            }
            viewModel.handlePhaseChange()
        }
        .onChange(of: viewModel.humanPlayer?.hand.count ?? 0) { _, newCount in
            guard dealForwardPending else { return }
            dealForwardPending = false
            let drawn = newCount - handCountBeforeDraw
            if drawn > 0 {
                withAnimation(.spring(response: 0.3)) { drawFeedbackCount = drawn }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation(.easeOut(duration: 0.4)) { drawFeedbackCount = nil }
                }
            }
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
        .onChange(of: scenePhase) { _, newPhase in
            guard viewModel.networkSession != nil else { return }
            switch newPhase {
            case .background:
                // Request background execution time so the MC session stays alive
                // while the screen is off. iOS grants ~30 seconds.
                guard bgTaskID == .invalid else { return }
                bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "MC-keepalive") {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                    bgTaskID = .invalid
                }
            case .active:
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                    bgTaskID = .invalid
                }
            default:
                break
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Gear menu — exit + share diagnostics
            Menu {
                if let url = logger.logFileURL {
                    ShareLink(item: url, subject: Text("Go! Deal! Diagnostics")) {
                        Label("Share Log", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                }
                Button(role: .destructive) {
                    if let onExit { onExit() } else { dismiss() }
                } label: {
                    Label("Exit Game", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 4)

            HStack(spacing: 6) {
                Image("GoDealLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
                Text("GO! DEAL!")
                    .font(.headline.weight(.black))
                    .foregroundStyle(blue)
            }

            Spacer()

            // Turn info — always show player's actual name
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(viewModel.currentPlayer.name)'s Turn")
                    .font(.caption.weight(.semibold))
                Text("\(viewModel.state.cardsPlayedThisTurn)/3 cards · T\(viewModel.state.turnNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 12) {
            // Draw button (start of turn)
            if viewModel.isHumanTurn, case .drawing = viewModel.state.phase {
                Button {
                    handCountBeforeDraw = viewModel.humanPlayer?.hand.count ?? 0
                    viewModel.startTurn()
                } label: {
                    Label("Draw Cards", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
            }

            // "+N cards" badge shown briefly after drawing
            if let n = drawFeedbackCount {
                Text("+\(n) cards")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(orange.opacity(0.5), lineWidth: 1))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
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
                        .background(
                            LinearGradient(colors: [orange, orangeDark], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
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

    private func gameOverOverlay(winnerIndex: Int) -> some View {
        let winnerName = viewModel.state.players[winnerIndex].name
        return ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text("🏆").font(.system(size: 52))
                        Text("\(winnerName) Wins!")
                            .font(.largeTitle.bold()).foregroundStyle(.white)
                        Text("3 complete sets · Turn \(viewModel.state.turnNumber) · \(viewModel.state.players.count) players")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 40)

                    // Per-player stat cards
                    ForEach(viewModel.state.players.indices, id: \.self) { idx in
                        playerEndCard(playerIndex: idx, winnerIndex: winnerIndex)
                    }

                    // Share + Play Again + Quit
                    VStack(spacing: 12) {
                        ShareLink(item: shareText(winnerIndex: winnerIndex)) {
                            Label("Share Results", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(width: 200)
                                .padding()
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.black)
                        }

                        if viewModel.networkSession != nil {
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
                                            .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                                            .foregroundStyle(.white)
                                    }
                                }
                            } else {
                                Text("Waiting for host…")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        } else {
                            Button {
                                showPlayAgainSetup = true
                            } label: {
                                Text("Play Again")
                                    .font(.headline)
                                    .frame(width: 200)
                                    .padding()
                                    .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(.white)
                            }
                        }

                        Button {
                            onExit?()
                        } label: {
                            Text("Quit to Menu")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func playerEndCard(playerIndex: Int, winnerIndex: Int) -> some View {
        let player = viewModel.state.players[playerIndex]
        let stats = playerIndex < viewModel.state.playerStats.count
            ? viewModel.state.playerStats[playerIndex] : PlayerStats()
        let isWinner = playerIndex == winnerIndex
        let badges = superlatives(for: playerIndex, winnerIndex: winnerIndex)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(isWinner ? "🏆 " : "")\(player.name)")
                    .font(.headline.bold()).foregroundStyle(.white)
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge).font(.caption2).foregroundStyle(.yellow)
                }
            }
            Divider().overlay(Color.white.opacity(0.2))
            HStack {
                statCell("💰 Collected", "$\(stats.rentCollected)M")
                statCell("💸 Paid", "$\(stats.rentPaid)M")
            }
            HStack {
                statCell("🏦 Peak Bank", "$\(stats.peakBankValue)M")
                statCell("🤏 Deals", "\(stats.steals)")
            }
            HStack {
                statCell("🚫 Blocks", "\(stats.noDealPlayed)")
                statCell("🃏 Drew", "\(stats.moneyCardsDrawn)💵 \(stats.propertyCardsDrawn)🏠 \(stats.actionCardsDrawn)⚡ \(stats.rentCardsDrawn)🏘")
            }
        }
        .padding(12)
        .background(isWinner ? Color.yellow.opacity(0.15) : Color.white.opacity(0.08),
                     in: RoundedRectangle(cornerRadius: 12))
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.caption).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func superlatives(for playerIndex: Int, winnerIndex: Int) -> [String] {
        let all = viewModel.state.playerStats
        guard playerIndex < all.count else { return [] }
        let s = all[playerIndex]
        let n = all.count
        var result: [String] = []

        func isTop<T: Comparable>(_ kp: KeyPath<PlayerStats, T>) -> Bool {
            n < 2 || all.indices.allSatisfy { $0 == playerIndex || all[$0][keyPath: kp] <= s[keyPath: kp] }
        }

        if isTop(\.steals) && s.steals >= 2              { result.append("Property Pirate 🤏") }
        if isTop(\.noDealPlayed) && s.noDealPlayed >= 2   { result.append("Deal Blocker 🚫") }
        if isTop(\.rentCollected) && s.rentCollected > 0  { result.append("Rent Machine 💰") }
        if isTop(\.peakBankValue) && s.peakBankValue > 0  { result.append("Cash Baron 💵") }
        if playerIndex == winnerIndex && viewModel.state.turnNumber <= 12 { result.append("Speed Racer ⚡") }
        if playerIndex == winnerIndex && result.isEmpty    { result.append("Property Mogul 🏠") }
        if s.rentPaid >= 8                                { result.append("Human ATM 🏧") }
        if s.steals == 0 && n > 1                         { result.append("Too Nice 😇") }
        if s.noDealPlayed == 0 && n > 1                   { result.append("Took the Hits 😤") }
        if result.isEmpty { result.append(playerIndex == winnerIndex ? "Property Mogul 🏠" : "Better Luck Next Time 🎲") }
        return result
    }

    private func shareText(winnerIndex: Int) -> String {
        let stats = winnerIndex < viewModel.state.playerStats.count
            ? viewModel.state.playerStats[winnerIndex] : PlayerStats()
        let w = viewModel.state.players[winnerIndex].name
        return """
        🎉 Go! Deal!
        \(w) won in \(viewModel.state.turnNumber) turns!
        💰 $\(stats.rentCollected)M collected · 💸 $\(stats.rentPaid)M paid · 🤏 \(stats.steals) deals
        """
    }

    // MARK: - Card Interaction

    // True when the pending action card can actually be played (not just banked)
    private var pendingActionCanPlay: Bool {
        guard let card = pendingActionCard else { return true }
        switch card.type {
        case .action(.cornerStore):
            return !(viewModel.humanPlayer?.properties.filter { $0.value.canAddCornerStore }.isEmpty ?? true)
        case .action(.apartmentBuilding):
            return !(viewModel.humanPlayer?.properties.filter { $0.value.canAddApartmentBuilding }.isEmpty ?? true)
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
            case .cornerStore, .apartmentBuilding:
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
