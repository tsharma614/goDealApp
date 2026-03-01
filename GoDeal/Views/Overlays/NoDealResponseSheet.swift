import SwiftUI

// MARK: - No Deal Response Sheet
// Appears when the human player is targeted by an action.
// They can play a "No Deal!" card or accept.

struct NoDealResponseSheet: View {
    let actionCard: Card
    let attackerName: String
    let actionDetail: String
    let noDealCards: [Card]
    let onPlayNoDeal: (UUID) -> Void
    let onAccept: () -> Void

    @State private var timeRemaining: Int = 15

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)

                Text("\(attackerName) played:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(actionCard.name)
                    .font(.title2.weight(.bold))

                Text(actionCard.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if !actionDetail.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.orange)
                        Text(actionDetail)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                }
            }
            .padding(.top)

            // Action card preview
            CardView(card: actionCard, size: .large)
                .padding(.vertical, 4)

            // Timer
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)
                Circle()
                    .trim(from: 0, to: CGFloat(timeRemaining) / 15.0)
                    .stroke(timeRemaining > 5 ? Color.green : Color.red, lineWidth: 4)
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timeRemaining)
                Text("\(timeRemaining)")
                    .font(.caption.weight(.bold))
            }

            // Accept button (primary action — shown first)
            Button(action: {
                onAccept()
                timer.upstream.connect().cancel()
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Accept")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            // No Deal! block option — always show just ONE button even if player holds multiple
            if let noDealCard = noDealCards.first {
                VStack(spacing: 10) {
                    Text("— or block with No Deal! —")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button {
                        onPlayNoDeal(noDealCard.id)
                        timer.upstream.connect().cancel()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(noDealCard.name)
                                .fontWeight(.semibold)
                            Text("— Cancel this action")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }

            Spacer(minLength: 8)
        }
        .onReceive(timer) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                onAccept()
                timer.upstream.connect().cancel()
            }
        }
    }
}

#Preview {
    let deck = DeckBuilder.buildDeck()
    let noDealCards = deck.filter { $0.isNoDeal }
    let actionCards = deck.filter { if case .action(.dealSnatcher) = $0.type { return true }; return false }

    if let action = actionCards.first {
        NoDealResponseSheet(
            actionCard: action,
            attackerName: "CPU",
            actionDetail: "Will steal your complete Blue Chip set (2 cards)",
            noDealCards: Array(noDealCards.prefix(1)),
            onPlayNoDeal: { _ in },
            onAccept: {}
        )
    }
}
