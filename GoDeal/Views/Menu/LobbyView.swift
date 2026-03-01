import SwiftUI
import MultipeerConnectivity

// MARK: - Lobby View

/// Entry point for multiplayer: user picks Host or Guest, then waits/browses.
struct LobbyView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("playerName") private var storedName: String = ""

    /// Called when the session is ready and the game should start.
    /// Provides the configured session + the local player's index.
    var onStartGame: (MultipeerSession, Int) -> Void

    @State private var role: MCRole? = nil
    @State private var displayName: String = ""
    @State private var session: MultipeerSession? = nil
    @State private var localPlayerIndex: Int = 0

    var body: some View {
        NavigationStack {
            if let role, let session {
                // Already chosen a role — show lobby screen
                lobbyScreen(role: role, session: session)
            } else {
                rolePickerScreen
            }
        }
    }

    // MARK: - Role Picker

    private var rolePickerScreen: some View {
        ZStack {
            Color(red: 0.08, green: 0.15, blue: 0.35).ignoresSafeArea()
            VStack(spacing: 28) {
                Text("Play with Friends")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                VStack(spacing: 8) {
                    Text("Your name")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    TextField("e.g. Tanmay", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .autocorrectionDisabled()
                }

                VStack(spacing: 14) {
                    roleButton(title: "Host a Game", icon: "person.badge.plus", color: .green) {
                        let name = displayName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { storedName = name }
                        let s = MultipeerSession(role: .host, displayName: name.isEmpty ? UIDevice.current.name : name)
                        s.startAdvertising()
                        session = s
                        role = .host
                        localPlayerIndex = 0
                    }
                    roleButton(title: "Join a Game", icon: "magnifyingglass", color: .blue) {
                        let name = displayName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { storedName = name }
                        let s = MultipeerSession(role: .guest, displayName: name.isEmpty ? UIDevice.current.name : name)
                        s.startBrowsing()
                        session = s
                        role = .guest
                    }
                }
                .padding(.horizontal, 40)

                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            if displayName.isEmpty {
                displayName = storedName.isEmpty ? UIDevice.current.name : storedName
            }
        }
    }

    // MARK: - Lobby Screen (post-role selection)

    @ViewBuilder
    private func lobbyScreen(role: MCRole, session: MultipeerSession) -> some View {
        ZStack {
            Color(red: 0.08, green: 0.15, blue: 0.35).ignoresSafeArea()

            VStack(spacing: 24) {
                Text(role == .host ? "Hosting Game" : "Finding Game")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if role == .host {
                    hostBody(session: session)
                } else {
                    guestBody(session: session)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    session.disconnect()
                    self.session = nil
                    self.role = nil
                }
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Host UI

    @ViewBuilder
    private func hostBody(session: MultipeerSession) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Waiting for players…")
                    .foregroundStyle(.white.opacity(0.8))
                Text("Your device: \(displayName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            if session.connectedPeers.isEmpty {
                Text("No players connected yet")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.subheadline)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connected (\(session.connectedPeers.count)):")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    ForEach(session.connectedPeers, id: \.self) { peer in
                        HStack(spacing: 8) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text(peer.displayName)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            Button {
                startHostGame(session: session)
            } label: {
                Text("Start Game")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(session.connectedPeers.isEmpty ? Color.gray : Color.green,
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .disabled(session.connectedPeers.isEmpty)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Guest UI

    @ViewBuilder
    private func guestBody(session: MultipeerSession) -> some View {
        // Wire up host-start receiver once (idempotent due to @Observable)
        let _ = setupGuestReceiver(session: session)

        VStack(spacing: 20) {
            if session.connectedPeers.isEmpty {
                // Browsing
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Looking for hosts…")
                        .foregroundStyle(.white.opacity(0.7))
                }

                if !session.nearbyHosts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nearby hosts:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        ForEach(session.nearbyHosts, id: \.self) { host in
                            Button {
                                session.invite(host)
                            } label: {
                                HStack {
                                    Text(host.displayName)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("Tap to join")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                // Connected — waiting for host to start
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Connected!")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Waiting for the host to start…")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Private helpers

    private func roleButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).frame(width: 30)
                Text(title).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).opacity(0.6)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.5), lineWidth: 1))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    /// Host: assigns indices to guests, broadcasts gameStart, then launches game.
    private func startHostGame(session: MultipeerSession) {
        let guests = session.connectedPeers
        // Assign player indices: host = 0, guests = 1, 2, 3…
        for (offset, peer) in guests.enumerated() {
            let idx = offset + 1
            session.send(.playerAssignment(localPlayerIndex: idx), to: [peer])
        }
        session.send(.gameStart)
        session.stopAdvertising()
        onStartGame(session, 0)
    }

    /// Guest: set up onReceive to listen for playerAssignment + gameStart.
    /// Uses [session] capture (reference type) so mutations to assignedPlayerIndex
    /// are real, not on a discarded SwiftUI view-struct copy.
    /// Returns a dummy value so it can be used in the `let _ =` pattern in SwiftUI body.
    @discardableResult
    private func setupGuestReceiver(session: MultipeerSession) -> Bool {
        guard session.onReceive == nil else { return true }
        // Store the callback on the session (reference type) once, not on self (value type).
        session.onGameStart = self.onStartGame
        session.onReceive = { [session] message, _ in
            switch message {
            case .playerAssignment(let idx):
                session.assignedPlayerIndex = idx
            case .gameStart:
                let localIdx = session.assignedPlayerIndex
                session.stopBrowsing()
                session.onGameStart?(session, localIdx)
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
