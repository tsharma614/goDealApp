import SwiftUI

// MARK: - Opponent Area View
// Compact display of an opponent's state.

struct OpponentAreaView: View {
    let player: Player
    let isCurrentTurn: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Header bar
            HStack(spacing: 8) {
                // Turn indicator
                Circle()
                    .fill(isCurrentTurn ? Color.yellow : Color.clear)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .frame(width: 10, height: 10)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isCurrentTurn)

                Text(player.name)
                    .font(.caption.weight(.semibold))

                Spacer()

                // Hand size
                Label("\(player.hand.count)", systemImage: "rectangle.stack")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Bank
                BankView(player: player, compact: true)

                // Completed sets badge
                if player.completedSets > 0 {
                    Label("\(player.completedSets)/3", systemImage: "house.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(player.completedSets >= 2 ? .orange : .secondary)
                }
            }
            .padding(.horizontal, 10)

            // Properties — always shown so empty state is visible and layout height stays stable
            PlayerPropertyView(player: player, isInteractive: false)
                .padding(.horizontal, 6)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrentTurn ? Color.yellow.opacity(0.08) : Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isCurrentTurn ? Color.yellow.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
        )
    }
}

#Preview {
    let player: Player = {
        var p = Player(name: "CPU", isHuman: false)
        let deck = DeckBuilder.buildDeck()
        p.addToHand(Array(deck.prefix(5)))
        for card in deck where card.isMoneyCard {
            p.addToBank(card)
            if p.bank.count >= 3 { break }
        }
        return p
    }()

    VStack {
        OpponentAreaView(player: player, isCurrentTurn: true)
        OpponentAreaView(player: player, isCurrentTurn: false)
    }
    .padding()
}
