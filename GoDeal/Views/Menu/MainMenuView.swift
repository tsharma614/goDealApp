import SwiftUI
import GameKit

// MARK: - Main Menu View

struct MainMenuView: View {
    @State private var isShowingGame = false
    @State private var isShowingSetup = false
    @State private var isShowingLobby = false
    @State private var isShowingOnlineLobby = false
    @State private var isShowingCustomization = false
    @State private var isShowingTutorial = false
    @State private var gameViewModel = GameViewModel()
    @State private var customizationViewModel = CustomizationViewModel()
    @State private var inviteError: String? = nil
    @AppStorage("onlinePlayerName") private var onlinePlayerName: String = ""

    // Brand palette
    private let orange     = Color(red: 0.96, green: 0.65, blue: 0.22)
    private let orangeDark = Color(red: 0.82, green: 0.48, blue: 0.08)
    private let blue       = Color(red: 0.22, green: 0.62, blue: 0.92)
    private let felt       = Color(red: 0.07, green: 0.20, blue: 0.12)

    var body: some View {
        if isShowingGame {
            GameBoardView(onExit: {
                gameViewModel.networkSession?.disconnect()
                isShowingGame = false
            })
                .environment(gameViewModel)
        } else {
            mainMenuStack
        }
    }

    private var mainMenuStack: some View {
        NavigationStack {
            ZStack {
                feltBackground

                VStack(spacing: 0) {
                    Spacer()

                    logoSection
                        .padding(.bottom, 48)

                    buttonSection
                        .padding(.horizontal, 32)

                    Spacer()

                    Text("Go! Deal! — A financial card game")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $isShowingSetup) {
            GameSetupView(onStart: { setup in
                gameViewModel = GameViewModel(setup: setup)
                isShowingSetup = false
                isShowingGame = true
            })
        }
        .sheet(isPresented: $isShowingCustomization) {
            CustomizationMenuView()
                .environment(customizationViewModel)
        }
        .sheet(isPresented: $isShowingLobby) {
            LobbyView { session, localIdx, cpuCount, difficulty in
                var setup = GameSetup()
                setup.cpuDifficulty = difficulty
                if session.role == .host {
                    gameViewModel = GameViewModel(setup: setup, session: session, localPlayerIndex: localIdx, cpuCount: cpuCount)
                } else {
                    gameViewModel = GameViewModel(session: session, localPlayerIndex: localIdx)
                }
                isShowingGame = true
                isShowingLobby = false
            }
        }
        .sheet(isPresented: $isShowingTutorial) {
            TutorialView()
        }
        .sheet(isPresented: $isShowingOnlineLobby) {
            GameKitLobbyView { session, localIdx, cpuCount, difficulty in
                var setup = GameSetup()
                setup.cpuDifficulty = difficulty
                setup.humanPlayerName = onlinePlayerName
                if session.role == .host {
                    gameViewModel = GameViewModel(setup: setup, session: session, localPlayerIndex: localIdx, cpuCount: cpuCount)
                } else {
                    gameViewModel = GameViewModel(session: session, localPlayerIndex: localIdx)
                }
                isShowingGame = true
                isShowingOnlineLobby = false
            }
        }
        .onChange(of: InviteManager.shared.pendingInvite != nil) { _, hasPending in
            guard hasPending, !isShowingGame else { return }
            acceptPendingInvite()
        }
        .alert("Invite Error", isPresented: Binding(
            get: { inviteError != nil },
            set: { if !$0 { inviteError = nil } }
        )) {
            Button("OK") { inviteError = nil }
        } message: {
            Text(inviteError ?? "")
        }
    }

    private func acceptPendingInvite() {
        Task { @MainActor in
            do {
                let (match, role) = try await InviteManager.shared.acceptInvite()
                let session = GameKitSession(match: match, role: role)
                let allIDs = ([GKLocalPlayer.local.gamePlayerID]
                    + match.players.map { $0.gamePlayerID }).sorted()
                let localIdx = allIDs.firstIndex(of: GKLocalPlayer.local.gamePlayerID) ?? 0

                if role == .host {
                    gameViewModel = GameViewModel(setup: GameSetup(), session: session, localPlayerIndex: localIdx)
                } else {
                    gameViewModel = GameViewModel(session: session, localPlayerIndex: localIdx)
                }
                isShowingGame = true
            } catch {
                inviteError = error.localizedDescription
                InviteManager.shared.clearInvite()
            }
        }
    }

    // MARK: - Background

    private var feltBackground: some View {
        ZStack {
            felt.ignoresSafeArea()

            // Tiled suit watermark
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
                            Text(suit)
                                .font(.system(size: 20))
                                .foregroundStyle(Color.white.opacity(0.055)),
                            at: CGPoint(x: x, y: y),
                            anchor: .center
                        )
                    }
                }
            }
            .ignoresSafeArea()

            // Vignette
            RadialGradient(
                colors: [.clear, .black.opacity(0.5)],
                center: .center,
                startRadius: 140,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: 16) {
            Image("GoDealLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .shadow(color: orange.opacity(0.3), radius: 16)

            HStack(spacing: 8) {
                Text("♠").foregroundStyle(.white.opacity(0.4))
                Text("Collect 3 complete sets to win")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                Text("♠").foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Buttons

    private var buttonSection: some View {
        VStack(spacing: 14) {
            // Primary CTA
            Button { isShowingSetup = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.bold))
                    Text("Play Now")
                        .font(.title3.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    LinearGradient(colors: [orange, orangeDark], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .foregroundStyle(.white)
                .shadow(color: orange.opacity(0.38), radius: 12, y: 5)
            }
            .buttonStyle(.plain)

            // Multiplayer row
            HStack(spacing: 12) {
                multiCard("Play with\nFriends", icon: "person.2.fill", color: blue) {
                    isShowingLobby = true
                }
                multiCard("Play\nOnline", icon: "globe", color: orange) {
                    isShowingOnlineLobby = true
                }
            }

            // Secondary links
            HStack(spacing: 16) {
                Button { isShowingCustomization = true } label: {
                    Label("Customize", systemImage: "paintbrush.fill")
                }
                Text("·").opacity(0.35)
                Button { isShowingTutorial = true } label: {
                    Label("How to Play", systemImage: "questionmark.circle")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.top, 2)
        }
    }

    private func multiCard(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(color.opacity(0.4), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Customization Menu View

struct CustomizationMenuView: View {
    @Environment(CustomizationViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    private let sampleDeck = DeckBuilder.buildDeck()

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Edit Street Names") {
                    PropertyNameEditorView()
                        .environment(viewModel)
                }
            }
            .navigationTitle("Customization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    MainMenuView()
}
