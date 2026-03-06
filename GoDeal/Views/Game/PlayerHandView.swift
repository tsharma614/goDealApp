import SwiftUI

// MARK: - Player Hand View
// Displays the human player's hand as a scrollable row of cards.

struct PlayerHandView: View {
    let cards: [Card]
    let canPlay: Bool
    var selectedCardId: UUID?
    var isCardPlayable: ((Card) -> Bool)? = nil
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

            if let selectedId = selectedCardId,
               let selected = cards.first(where: { $0.id == selectedId }) {
                cardActionHint(for: selected)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -16) {
                    ForEach(cards) { card in
                        let isSelected = selectedCardId == card.id
                        let cardPlayable = canPlay && (isCardPlayable?(card) ?? true)
                        CardView(
                            card: card,
                            isSelected: isSelected,
                            isPlayable: cardPlayable,
                            size: .normal
                        )
                        .offset(y: isSelected ? -12 : 0)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .offset(y: -40).combined(with: .opacity)
                        ))
                        .onTapGesture {
                            if isSelected {
                                SoundManager.cardSelect()
                                onCardPlay(card)
                            } else {
                                SoundManager.cardSelect()
                                onCardTap(card)
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: cards.map { $0.id })
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            // Lock to intrinsic card height so extra space goes to spacers around activity section
            .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $detailCard) { card in
            CardDetailSheet(card: card)
                .presentationDetents([.medium, .large])
        }
        .animation(.spring(response: 0.2), value: selectedCardId)
    }

    // MARK: - Card Hint

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
