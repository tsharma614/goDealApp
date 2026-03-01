import SwiftUI

// MARK: - Action Target Sheet
// Shown when an action card requires the player to select a target player.

struct ActionTargetSheet: View {
    let actionCard: Card
    let players: [Player]
    let currentPlayerIndex: Int
    let onSelectTarget: (Int) -> Void
    let onCancel: () -> Void
    var onBank: (() -> Void)? = nil

    var targetPlayers: [(Int, Player)] {
        players.enumerated()
            .filter { $0.offset != currentPlayerIndex }
            .map { ($0.offset, $0.element) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Card being played
                    CardView(card: actionCard, size: .normal)
                        .padding(.top)

                    Text("Select a target player:")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // Target options
                    VStack(spacing: 10) {
                        ForEach(targetPlayers, id: \.0) { (idx, player) in
                            Button {
                                onSelectTarget(idx)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(player.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 10) {
                                            Label("\(player.hand.count) cards", systemImage: "rectangle.stack")
                                            Label("$\(player.bankTotal)M", systemImage: "banknote")
                                            Label("\(player.completedSets)/3", systemImage: "house.fill")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 20)
                }
            }
            .navigationTitle(actionCard.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                if let onBank = onBank {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Bank $\(actionCard.monetaryValue)M", action: onBank)
                    }
                }
            }
        }
    }
}

#Preview {
    let players = [
        Player(name: "You", isHuman: true),
        Player(name: "CPU", isHuman: false),
    ]
    let card = DeckBuilder.buildDeck().first { if case .action(.collectNow) = $0.type { return true }; return false }!

    ActionTargetSheet(
        actionCard: card,
        players: players,
        currentPlayerIndex: 0,
        onSelectTarget: { _ in },
        onCancel: {}
    )
}
