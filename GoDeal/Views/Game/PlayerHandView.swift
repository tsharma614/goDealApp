import SwiftUI

// MARK: - Player Hand View
// Displays the human player's hand as a scrollable row of cards.

struct PlayerHandView: View {
    let cards: [Card]
    let canPlay: Bool
    var selectedCardId: UUID?
    let onCardTap: (Card) -> Void
    let onCardPlay: (Card) -> Void

    @State private var detailCard: Card? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Your Hand")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(cards.count) cards")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

            // Hint sits above the cards so lifted card is never covered
            if let selectedId = selectedCardId,
               let selected = cards.first(where: { $0.id == selectedId }) {
                cardActionHint(for: selected)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -16) {
                    ForEach(cards) { card in
                        CardView(
                            card: card,
                            isSelected: selectedCardId == card.id,
                            isPlayable: canPlay,
                            size: .normal
                        )
                        .offset(y: selectedCardId == card.id ? -12 : 0)
                        .zIndex(selectedCardId == card.id ? 10 : 0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                        .onTapGesture {
                            if selectedCardId == card.id {
                                onCardPlay(card)
                            } else {
                                onCardTap(card)
                            }
                        }
                        .onLongPressGesture {
                            detailCard = card
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .sheet(item: $detailCard) { card in
            CardDetailSheet(card: card)
                .presentationDetents([.medium, .large])
        }
        .animation(.spring(response: 0.2), value: selectedCardId)
    }

    @ViewBuilder
    private func cardActionHint(for card: Card) -> some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(card.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("Tap again to play")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    let deck = DeckBuilder.buildDeck()
    PlayerHandView(
        cards: Array(deck.prefix(7)),
        canPlay: true,
        selectedCardId: deck.first?.id,
        onCardTap: { _ in },
        onCardPlay: { _ in }
    )
    .background(Color(UIColor.systemBackground))
}
