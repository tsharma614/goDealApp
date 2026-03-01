import SwiftUI

// MARK: - Game Setup View

struct GameSetupView: View {
    @AppStorage("playerName") private var storedName: String = ""
    @State private var setup = GameSetup()
    let onStart: (GameSetup) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Name") {
                    TextField("e.g. Tanmay", text: $setup.humanPlayerName)
                        .onAppear { if setup.humanPlayerName.isEmpty { setup.humanPlayerName = storedName } }
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section("Opponents") {
                    Stepper(
                        "\(setup.cpuCount) CPU Opponent\(setup.cpuCount > 1 ? "s" : "")",
                        value: $setup.cpuCount, in: 1...3
                    )
                    Text("Total players: \(setup.cpuCount + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("CPU Difficulty") {
                    Picker("Difficulty", selection: $setup.cpuDifficulty) {
                        ForEach(AIDifficulty.allCases, id: \.self) { diff in
                            Text(diff.rawValue.capitalized).tag(diff)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Difficulty description
                    VStack(alignment: .leading, spacing: 4) {
                        switch setup.cpuDifficulty {
                        case .easy:
                            Label("CPU plays randomly. Great for learning!", systemImage: "tortoise.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .medium:
                            Label("CPU uses smart strategies. A fair challenge.", systemImage: "brain.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Game Info") {
                    LabeledContent("Win Condition", value: "3 complete property sets")
                    LabeledContent("Cards per Turn", value: "Play up to 3")
                    LabeledContent("Hand Limit", value: "7 cards")
                }
            }
            .navigationTitle("Game Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Game") {
                        let trimmed = setup.humanPlayerName.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { storedName = trimmed }
                        onStart(setup)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    GameSetupView(onStart: { _ in })
}
