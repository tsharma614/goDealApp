import SwiftUI

// MARK: - Discard Sheet
// Shown when the player has more than 7 cards at end of turn.

struct DiscardSheet: View {
    let hand: [Card]
    let mustDiscard: Int
    let onDiscard: (UUID) -> Void
    /// Non-nil when the player still has actions left — lets them cancel and play more cards first
    var onPlayMore: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 4) {
                    Image(systemName: "hand.raised.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)

                    Text("Too Many Cards!")
                        .font(.title2.weight(.bold))

                    Text("You have \(hand.count) cards. Discard \(mustDiscard) to reach 7.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if onPlayMore != nil {
                        Text("Or play more cards first to reduce your hand.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.top)

                // Hand grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], spacing: 12) {
                        ForEach(hand) { card in
                            VStack(spacing: 4) {
                                CardView(card: card, size: .normal)
                                Text("Discard")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                            .onTapGesture {
                                onDiscard(card.id)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Discard Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onPlayMore {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Play More First") { onPlayMore() }
                    }
                }
            }
            // Auto-close as soon as mustDiscard hits 0 — works for both solo and
            // multiplayer guests (mustDiscard is a live computed value from the parent).
            .onChange(of: mustDiscard) { _, new in
                if new <= 0 { dismiss() }
            }
        }
    }
}

#Preview {
    let deck = DeckBuilder.buildDeck()
    DiscardSheet(
        hand: Array(deck.prefix(10)),
        mustDiscard: 3,
        onDiscard: { _ in }
    )
}
