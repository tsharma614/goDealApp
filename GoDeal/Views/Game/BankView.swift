import SwiftUI

// MARK: - Bank View
// Shows a player's banked money cards and total.

struct BankView: View {
    let player: Player
    var compact: Bool = false

    var body: some View {
        if compact {
            compactView
        } else {
            fullView
        }
    }

    private var compactView: some View {
        HStack(spacing: 4) {
            Image(systemName: "banknote.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Text("$\(player.bankTotal)M")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Bank", systemImage: "banknote.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                Text("Total: $\(player.bankTotal)M")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            }

            if player.bank.isEmpty {
                Text("No cards banked")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(player.bank.sorted { $0.monetaryValue > $1.monetaryValue }) { card in
                            moneyChip(card: card)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }

    private func moneyChip(card: Card) -> some View {
        let value: Int = {
            if case .money(let v) = card.type { return v }
            return card.monetaryValue
        }()

        return Text("$\(value)M")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(moneyColor(value: value), in: Capsule())
    }

    private func moneyColor(value: Int) -> Color {
        switch value {
        case 1:  return .green.opacity(0.6)
        case 2:  return .green.opacity(0.7)
        case 3:  return .green.opacity(0.8)
        case 4:  return .green.opacity(0.85)
        case 5:  return .green
        case 10: return Color(red: 0, green: 0.5, blue: 0.1)
        default: return .green
        }
    }
}

#Preview {
    let player: Player = {
        var p = Player(name: "Test", isHuman: true)
        let deck = DeckBuilder.buildDeck()
        for card in deck where card.isMoneyCard {
            p.addToBank(card)
            if p.bank.count >= 5 { break }
        }
        return p
    }()

    VStack {
        BankView(player: player, compact: true)
        BankView(player: player, compact: false)
    }
    .padding()
}
