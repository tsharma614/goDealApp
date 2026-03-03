import SwiftUI

// MARK: - Deck Area View
// Shows the draw deck, discard pile, and a recent activity feed.

struct DeckAreaView: View {
    let deckCount: Int
    let topDiscard: Card?
    var recentActivity: [String] = []

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Activity feed (left, takes remaining width)
            activityFeed

            // Discard pile
            VStack(spacing: 2) {
                if let top = topDiscard {
                    CardView(card: top, isPlayable: false, size: .small)
                } else {
                    emptyPile(label: "Discard")
                }
                Text("Discard")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            // Draw deck
            VStack(spacing: 2) {
                ZStack {
                    ForEach(0..<min(3, deckCount), id: \.self) { i in
                        CardView(showBack: true, size: .small)
                            .offset(x: CGFloat(i) * 1.5, y: CGFloat(-i) * 1.5)
                    }
                    if deckCount == 0 {
                        emptyPile(label: "")
                    }
                }
                .frame(width: 60, height: 84)

                Text("\(deckCount) left")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Activity Feed

    private var activityFeed: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                Text("ACTIVITY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            if recentActivity.isEmpty {
                Text("Waiting for first action…")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(recentActivity.prefix(5).enumerated()), id: \.offset) { i, msg in
                        Text(msg)
                            .font(.system(size: i == 0 ? 11 : 10))
                            .fontWeight(i == 0 ? .medium : .regular)
                            .foregroundStyle(i == 0 ? Color.primary : Color.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func emptyPile(label: String) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            .frame(width: 60, height: 84)
            .overlay {
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
    }
}

#Preview {
    let deck = DeckBuilder.buildDeck()
    DeckAreaView(
        deckCount: deck.count,
        topDiscard: deck.first,
        recentActivity: [
            "CPU played Quick Grab!",
            "You paid $3M to CPU",
            "CPU 2 drew 2 cards",
        ]
    )
    .frame(height: 120)
    .padding()
    .background(Color(UIColor.systemBackground))
}
