import SwiftUI
import GameKit

// MARK: - GameKit Lobby View

/// Internet multiplayer lobby. Two modes:
/// - Create Room: generates a shareable 6-char code, waits for players to join.
/// - Join Room:   enter a code a friend shared, connect to their room.
struct GameKitLobbyView: View {
    /// Called when a match forms. Receives the session and this player's index.
    var onStartGame: (GameKitSession, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mode: LobbyMode = .create
    @State private var generatedCode: String = String.randomRoomCode()
    @State private var joinCode: String = ""
    @State private var matchmaker = GameKitMatchmaker()
    @State private var errorMessage: String? = nil
    @State private var isAuthenticated: Bool = GKLocalPlayer.local.isAuthenticated

    private enum LobbyMode { case create, join }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if !isAuthenticated {
                    notAuthenticatedView
                } else {
                    Picker("Mode", selection: $mode) {
                        Text("Create Room").tag(LobbyMode.create)
                        Text("Join Room").tag(LobbyMode.join)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if mode == .create {
                        createRoomView
                    } else {
                        joinRoomView
                    }

                    if matchmaker.isSearching {
                        ProgressView("Looking for players…")
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
                                if mode == .create { generatedCode = String.randomRoomCode() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Play Online")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        matchmaker.cancel()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    // MARK: - Subviews

    private var notAuthenticatedView: some View {
        VStack(spacing: 16) {
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
        }
        .padding(.top, 40)
    }

    private var createRoomView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Share this code with your friends")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(generatedCode)
                    .font(.system(size: 44, weight: .black, design: .monospaced))
                    .foregroundStyle(.primary)
                    .tracking(8)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            Button {
                startSearch(code: generatedCode)
            } label: {
                Label("Wait for Players", systemImage: "person.wave.2.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(matchmaker.isSearching)
            .padding(.horizontal)

            Button("New Code") {
                generatedCode = String.randomRoomCode()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .disabled(matchmaker.isSearching)
        }
    }

    private var joinRoomView: some View {
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
                startSearch(code: joinCode.uppercased().trimmingCharacters(in: .whitespaces))
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

    // MARK: - Actions

    private func startSearch(code: String) {
        guard !code.isEmpty else { return }
        errorMessage = nil
        Task {
            do {
                let (match, role) = try await matchmaker.createOrJoinMatch(roomCode: code, maxPlayers: 4)
                let session = GameKitSession(match: match, role: role)
                // localPlayerIndex: position in sorted list of all gamePlayerIDs
                let allIDs = ([GKLocalPlayer.local.gamePlayerID]
                    + match.players.map { $0.gamePlayerID }).sorted()
                let localIdx = allIDs.firstIndex(of: GKLocalPlayer.local.gamePlayerID) ?? 0
                onStartGame(session, localIdx)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                matchmaker.isSearching = false
            }
        }
    }
}

#Preview {
    GameKitLobbyView { _, _ in }
}
