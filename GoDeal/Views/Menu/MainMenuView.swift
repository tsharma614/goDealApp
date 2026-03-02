import SwiftUI

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

    var body: some View {
        // Using if/else instead of fullScreenCover avoids iOS modal presentation
        // ordering conflicts (can't present a cover while a sheet is dismissing).
        if isShowingGame {
            GameBoardView(onExit: { isShowingGame = false })
                .environment(gameViewModel)
        } else {
            mainMenuStack
        }
    }

    private var mainMenuStack: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.15, blue: 0.35),
                        Color(red: 0.12, green: 0.25, blue: 0.15),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Logo
                    logoSection
                        .padding(.bottom, 48)

                    // Buttons
                    VStack(spacing: 16) {
                        menuButton(title: "Play Now", icon: "play.fill", color: .green) {
                            isShowingSetup = true
                        }

                        menuButton(title: "Play with Friends", icon: "person.2.fill", color: .blue) {
                            isShowingLobby = true
                        }

                        menuButton(title: "Play Online", icon: "globe", color: .cyan) {
                            isShowingOnlineLobby = true
                        }

                        menuButton(title: "Customize Cards", icon: "paintbrush.fill", color: .purple) {
                            isShowingCustomization = true
                        }

                        menuButton(title: "How to Play", icon: "questionmark.circle.fill", color: .orange) {
                            isShowingTutorial = true
                        }
                    }
                    .padding(.horizontal, 40)

                    Spacer()

                    // Footer
                    Text("Go! Deal! — A financial card game")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
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
            LobbyView { session, localIdx in
                // Build the right VM then show the game board.
                // Since isShowingGame flips the entire root view (not a modal),
                // there is no presentation conflict with the lobby sheet.
                let setup = GameSetup()
                if session.role == .host {
                    gameViewModel = GameViewModel(setup: setup, session: session, localPlayerIndex: localIdx)
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
            GameKitLobbyView { session, localIdx in
                if session.role == .host {
                    gameViewModel = GameViewModel(setup: GameSetup(), session: session, localPlayerIndex: localIdx)
                } else {
                    gameViewModel = GameViewModel(session: session, localPlayerIndex: localIdx)
                }
                isShowingGame = true
                isShowingOnlineLobby = false
            }
        }
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: 100, height: 100)
                    .shadow(color: .yellow.opacity(0.4), radius: 20)

                VStack(spacing: -4) {
                    Text("GO!")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                    Text("DEAL!")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                }
            }

            Text("Go! Deal!")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Collect 3 complete sets to win!")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Menu Button

    private func menuButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 30)
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .opacity(0.6)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.5), lineWidth: 1)
            )
            .foregroundStyle(.white)
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
