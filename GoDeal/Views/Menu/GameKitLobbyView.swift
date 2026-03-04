import SwiftUI
import GameKit

// MARK: - GameKit Lobby View

/// Internet multiplayer lobby.
/// Flow: Create/Join code entry → waiting lobby → host taps Start → game begins.
struct GameKitLobbyView: View {
    var onStartGame: (GameKitSession, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Screen { case entry, lobby }

    @State private var screen: Screen = .entry
    @State private var entryMode: EntryMode = .create
    @State private var generatedCode: String = String.randomRoomCode()
    @State private var joinCode: String = ""
    @State private var codeCopied: Bool = false
    @State private var matchmaker = GameKitMatchmaker()
    @State private var errorMessage: String? = nil
    @State private var isAuthenticated: Bool = GKLocalPlayer.local.isAuthenticated
    @State private var activeSession: GameKitSession? = nil
    @State private var activeRole: MCRole = .guest
    @State private var activeCode: String = ""
    @State private var localPlayerIndex: Int = 0

    private enum EntryMode { case create, join }

    var body: some View {
        NavigationStack {
            Group {
                if !isAuthenticated {
                    notAuthenticatedView
                } else if screen == .lobby, let session = activeSession {
                    lobbyScreen(session: session)
                } else {
                    entryScreen
                }
            }
            .navigationTitle("Play Online")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        matchmaker.cancel()
                        activeSession?.disconnect()
                        activeSession = nil
                        dismiss()
                    }
                }
            }
        }
        .onAppear { isAuthenticated = GKLocalPlayer.local.isAuthenticated }
    }

    // MARK: - Entry Screen

    private var entryScreen: some View {
        VStack(spacing: 24) {
            Picker("Mode", selection: $entryMode) {
                Text("Create Room").tag(EntryMode.create)
                Text("Join Room").tag(EntryMode.join)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if entryMode == .create { createView } else { joinView }

            if matchmaker.isSearching {
                ProgressView("Connecting…")
                    .padding()
            }

            if let err = errorMessage {
                VStack(spacing: 10) {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Try Again") {
                        errorMessage = nil
                        matchmaker.cancel()
                        if entryMode == .create { generatedCode = String.randomRoomCode() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    private var createView: some View {
        VStack(spacing: 20) {
            Button {
                UIPasteboard.general.string = generatedCode
                codeCopied = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    codeCopied = false
                }
            } label: {
                VStack(spacing: 8) {
                    Text("Share this code with your friends")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(generatedCode)
                        .font(.system(size: 44, weight: .black, design: .monospaced))
                        .foregroundStyle(.primary)
                        .tracking(8)
                    Label(codeCopied ? "Copied!" : "Tap to copy",
                          systemImage: codeCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(codeCopied ? .green : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: codeCopied)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            Button { startSearch(code: generatedCode, maxPlayers: 5) } label: {
                Label("Wait for Players", systemImage: "person.wave.2.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(matchmaker.isSearching)
            .padding(.horizontal)

            Button("New Code") { generatedCode = String.randomRoomCode() }
                .font(.callout)
                .foregroundStyle(.secondary)
                .disabled(matchmaker.isSearching)
        }
    }

    private var joinView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Room Code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. XKCD42", text: $joinCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Button {
                startSearch(code: joinCode.uppercased().trimmingCharacters(in: .whitespaces), maxPlayers: 5)
            } label: {
                Label("Join Room", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(matchmaker.isSearching || joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal)
        }
    }

    // MARK: - Lobby Screen

    @ViewBuilder
    private func lobbyScreen(session: GameKitSession) -> some View {
        VStack(spacing: 24) {
            // Room code reminder
            if activeRole == .host {
                HStack(spacing: 6) {
                    Text("Room:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(activeCode)
                        .font(.system(.title3, design: .monospaced).weight(.black))
                        .tracking(4)
                    Button {
                        UIPasteboard.general.string = activeCode
                        codeCopied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            codeCopied = false
                        }
                    } label: {
                        Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(codeCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Player list
            playerListCard(session: session)
                .padding(.horizontal)

            if activeRole == .host {
                hostLobbyButtons(session: session)
            } else {
                guestWaitingView
            }

            Spacer()
        }
        .padding(.top, 16)
        .onChange(of: session.gameStartReceived) { _, started in
            guard started else { return }
            onStartGame(session, session.assignedPlayerIndex)
            dismiss()
        }
    }

    private func playerListCard(session: GameKitSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let totalCount = session.connectedPeerNames.count + 1
            HStack {
                Text("Players (\(totalCount)/5)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if totalCount >= 5 {
                    Text("Full")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            // Local player row
            playerRow(
                name: "\(GKLocalPlayer.local.displayName) (you)",
                badge: activeRole == .host ? "host" : "guest",
                color: activeRole == .host ? .blue : .green
            )

            // Remote players
            ForEach(Array(session.connectedPeerNames.enumerated()), id: \.offset) { _, name in
                playerRow(name: name, badge: nil, color: .green)
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func playerRow(name: String, badge: String?, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
                .font(.subheadline)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func hostLobbyButtons(session: GameKitSession) -> some View {
        let count = session.connectedPeerNames.count + 1
        Button { startHostGame(session: session) } label: {
            Label(
                count >= 2 ? "Start Game (\(count) players)" : "Waiting for players…",
                systemImage: "play.fill"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(count < 2)
        .padding(.horizontal)

        Text("More players can still join with code \(activeCode)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private var guestWaitingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Waiting for the host to start…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Game Center Required")
                .font(.title3.weight(.semibold))
            Text("Sign in to Game Center in the Settings app to play online with friends.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }

    // MARK: - Actions

    private func startSearch(code: String, maxPlayers: Int = 5) {
        guard !code.isEmpty else { return }
        errorMessage = nil
        Task {
            do {
                let (match, role) = try await matchmaker.createOrJoinMatch(roomCode: code, maxPlayers: maxPlayers)
                let session = GameKitSession(match: match, role: role)
                // Compute local player index from sorted IDs (consistent with host assignment)
                let allIDs = ([GKLocalPlayer.local.gamePlayerID]
                    + match.players.map { $0.gamePlayerID }).sorted()
                localPlayerIndex = allIDs.firstIndex(of: GKLocalPlayer.local.gamePlayerID) ?? 0

                activeSession = session
                activeRole = role
                activeCode = code.uppercased()
                screen = .lobby

                // Guests listen for playerAssignment + gameStart from host
                if role == .guest {
                    setupGuestReceiver(session: session)
                }
            } catch {
                errorMessage = error.localizedDescription
                matchmaker.isSearching = false
            }
        }
    }

    private func startHostGame(session: GameKitSession) {
        // Assign indices: sort all IDs so every device gets the same deterministic mapping
        let allIDs = ([GKLocalPlayer.local.gamePlayerID]
            + session.connectedPeerIDs).sorted()
        for (idx, id) in allIDs.enumerated() where id != GKLocalPlayer.local.gamePlayerID {
            session.send(.playerAssignment(localPlayerIndex: idx), toPeerIDs: [id])
        }
        session.send(.gameStart)
        let localIdx = allIDs.firstIndex(of: GKLocalPlayer.local.gamePlayerID) ?? 0
        onStartGame(session, localIdx)
        dismiss()
    }

    private func setupGuestReceiver(session: GameKitSession) {
        session.onReceive = { [session] message, _ in
            switch message {
            case .playerAssignment(let idx):
                session.assignedPlayerIndex = idx
            case .gameStart:
                session.gameStartReceived = true   // triggers .onChange in lobbyScreen
            default:
                break
            }
        }
    }
}

#Preview {
    GameKitLobbyView { _, _ in }
}
