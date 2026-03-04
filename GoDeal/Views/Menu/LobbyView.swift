import SwiftUI
import MultipeerConnectivity

// MARK: - Lobby View

/// Entry point for local (same-network) multiplayer.
/// Visual style matches GameKitLobbyView for consistency.
struct LobbyView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("playerName") private var storedName: String = ""

    var onStartGame: (MultipeerSession, Int) -> Void

    @State private var role: MCRole? = nil
    @State private var displayName: String = ""
    @State private var session: MultipeerSession? = nil
    @State private var localPlayerIndex: Int = 0

    var body: some View {
        NavigationStack {
            Group {
                if let role, let session {
                    lobbyScreen(role: role, session: session)
                } else {
                    rolePickerScreen
                }
            }
            .navigationTitle("Play with Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        session?.disconnect()
                        self.session = nil
                        self.role = nil
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if displayName.isEmpty {
                displayName = storedName.isEmpty ? UIDevice.current.name : storedName
            }
        }
    }

    // MARK: - Role Picker

    private var rolePickerScreen: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Your name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Tanmay", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            VStack(spacing: 14) {
                roleButton(title: "Host a Game", icon: "person.badge.plus",
                           description: "Others on your network join you") {
                    let name = displayName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { storedName = name }
                    let s = MultipeerSession(role: .host,
                                            displayName: name.isEmpty ? UIDevice.current.name : name)
                    s.startAdvertising()
                    session = s
                    role = .host
                    localPlayerIndex = 0
                }
                roleButton(title: "Join a Game", icon: "magnifyingglass",
                           description: "Find a host on your network") {
                    let name = displayName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { storedName = name }
                    let s = MultipeerSession(role: .guest,
                                            displayName: name.isEmpty ? UIDevice.current.name : name)
                    s.startBrowsing()
                    session = s
                    role = .guest
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Lobby Screen

    @ViewBuilder
    private func lobbyScreen(role: MCRole, session: MultipeerSession) -> some View {
        VStack(spacing: 24) {
            if role == .host {
                hostBody(session: session)
            } else {
                guestBody(session: session)
            }
            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: - Host UI

    @ViewBuilder
    private func hostBody(session: MultipeerSession) -> some View {
        // Player list card
        playerListCard(session: session)
            .padding(.horizontal)

        let count = session.connectedPeers.count + 1
        Button {
            startHostGame(session: session)
        } label: {
            Label(
                count >= 2 ? "Start Game (\(count) players)" : "Waiting for players…",
                systemImage: "play.fill"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(session.connectedPeers.isEmpty)
        .padding(.horizontal)

        Text("Make sure everyone is on the same Wi-Fi network")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private func playerListCard(session: MultipeerSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let totalCount = session.connectedPeers.count + 1
            HStack {
                Text("Players (\(totalCount)/4)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if totalCount >= 4 {
                    Text("Full")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            // Host row
            HStack(spacing: 8) {
                Circle().fill(Color.blue).frame(width: 8, height: 8)
                Text("\(displayName) (you)")
                    .font(.subheadline)
                Spacer()
                Text("host")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if session.connectedPeers.isEmpty {
                Text("No players connected yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                ForEach(session.connectedPeers, id: \.self) { peer in
                    HStack(spacing: 8) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(peer.displayName)
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Guest UI

    @ViewBuilder
    private func guestBody(session: MultipeerSession) -> some View {
        let _ = setupGuestReceiver(session: session)

        if session.connectedPeers.isEmpty {
            // Browsing for hosts
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for hosts…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                if !session.nearbyHosts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nearby hosts:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(session.nearbyHosts.enumerated()), id: \.offset) { _, host in
                            Button { session.invite(host) } label: {
                                HStack {
                                    Text(host.displayName)
                                    Spacer()
                                    Text("Tap to join")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        } else {
            // Connected — waiting for host
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("Connected!")
                    .font(.title3.weight(.bold))
                Text("Waiting for the host to start…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Private helpers

    private func roleButton(title: String, icon: String, description: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 30)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func startHostGame(session: MultipeerSession) {
        let guests = session.connectedPeers
        for (offset, peer) in guests.enumerated() {
            session.send(.playerAssignment(localPlayerIndex: offset + 1),
                         toPeerIDs: [peer.displayName])
        }
        session.send(.gameStart)
        session.stopAdvertising()
        onStartGame(session, 0)
    }

    @discardableResult
    private func setupGuestReceiver(session: MultipeerSession) -> Bool {
        guard session.onReceive == nil else { return true }
        session.onReceive = { [session] message, _ in
            switch message {
            case .playerAssignment(let idx):
                session.assignedPlayerIndex = idx
            case .gameStart:
                session.stopBrowsing()
                session.gameStartReceived = true
            default:
                break
            }
        }
        return true
    }
}

#Preview {
    LobbyView { _, _ in }
}
