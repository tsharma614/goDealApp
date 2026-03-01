import SwiftUI

// MARK: - Payment Sheet
// Shown when the human player must pay rent or debt.
// They choose which bank cards and/or property cards to hand over.

struct PaymentSheet: View {
    let debtor: Player
    let creditor: Player
    let amountOwed: Int
    let reason: PaymentReason
    let onPay: ([UUID], [UUID]) -> Void  // (bankCardIds, propertyCardIds)

    @State private var selectedBankIds: Set<UUID> = []
    @State private var selectedPropertyIds: Set<UUID> = []

    // MARK: - Computed

    private var selectedBankTotal: Int {
        debtor.bank
            .filter { selectedBankIds.contains($0.id) }
            .reduce(0) { $0 + $1.monetaryValue }
    }

    private var selectedPropertyTotal: Int {
        debtor.allPropertyCards
            .filter { selectedPropertyIds.contains($0.id) }
            .reduce(0) { $0 + $1.monetaryValue }
    }

    private var selectedTotal: Int { selectedBankTotal + selectedPropertyTotal }

    private var mustPayAll: Bool { debtor.totalAssets <= amountOwed }

    private var canConfirm: Bool {
        if mustPayAll { return true }
        return selectedTotal >= amountOwed
    }

    private var sortedPropertySets: [(PropertyColor, PropertySet)] {
        debtor.properties
            .sorted { a, b in
                let order = PropertyColor.allCases
                let ai = order.firstIndex(of: a.key) ?? 0
                let bi = order.firstIndex(of: b.key) ?? 0
                return ai < bi
            }
            .map { ($0.key, $0.value) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reasonText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Owe: $\(amountOwed)M")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("$\(selectedTotal)M")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(selectedTotal >= amountOwed ? .green : .primary)
                        }
                    }
                    .padding(.vertical, 4)

                    if mustPayAll {
                        Label("You must pay all your assets ($\(debtor.totalAssets)M)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Select cards totalling at least $\(amountOwed)M")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Bank cards
                if !debtor.bank.isEmpty {
                    Section("Bank") {
                        ForEach(debtor.bank.sorted { $0.monetaryValue > $1.monetaryValue }) { card in
                            bankCardRow(card)
                        }
                    }
                }

                // Property cards
                ForEach(sortedPropertySets, id: \.0) { (color, set) in
                    Section(color.displayName) {
                        ForEach(set.properties) { card in
                            propertyCardRow(card, color: color, set: set)
                        }
                    }
                }
            }
            .navigationTitle("Pay \(creditor.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(mustPayAll ? "Pay All" : "Pay") {
                        if mustPayAll {
                            let allBankIds = debtor.bank.map { $0.id }
                            let allPropIds = debtor.allPropertyCards.map { $0.id }
                            onPay(allBankIds, allPropIds)
                        } else {
                            onPay(Array(selectedBankIds), Array(selectedPropertyIds))
                        }
                    }
                    .disabled(!canConfirm)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Bank Card Row

    private func bankCardRow(_ card: Card) -> some View {
        let isSelected = selectedBankIds.contains(card.id)
        let value: Int = {
            if case .money(let v) = card.type { return v }
            return card.monetaryValue
        }()

        return HStack {
            Text("$\(value)M")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(bankChipColor(value: value), in: Capsule())

            Text(card.name)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedBankIds.remove(card.id)
            } else {
                selectedBankIds.insert(card.id)
            }
        }
        .opacity(mustPayAll ? 0.5 : 1.0)
        .disabled(mustPayAll)
    }

    // MARK: - Property Card Row

    private func propertyCardRow(_ card: Card, color: PropertyColor, set: PropertySet) -> some View {
        let isSelected = selectedPropertyIds.contains(card.id)

        return HStack {
            Circle()
                .fill(color.uiColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.subheadline)
                if set.isComplete {
                    Text("Complete set")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Text("$\(card.monetaryValue)M")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedPropertyIds.remove(card.id)
            } else {
                selectedPropertyIds.insert(card.id)
            }
        }
        .opacity(mustPayAll ? 0.5 : 1.0)
        .disabled(mustPayAll)
    }

    // MARK: - Helpers

    private var reasonText: String {
        switch reason {
        case .rent(let color): return "\(creditor.name) charged rent (\(color.displayName))"
        case .collectNow:      return "\(creditor.name) played Collect Now!"
        case .bigSpender:      return "\(creditor.name) played Big Spender!"
        case .dealSnatcher:    return "\(creditor.name) played Deal Snatcher!"
        }
    }

    private func bankChipColor(value: Int) -> Color {
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
    let debtor: Player = {
        var p = Player(name: "You", isHuman: true)
        let deck = DeckBuilder.buildDeck()
        for card in deck where card.isMoneyCard {
            p.addToBank(card)
            if p.bank.count >= 4 { break }
        }
        for card in deck {
            if case .property(let color) = card.type {
                p.placeProperty(card, in: color)
                if p.allPropertyCards.count >= 3 { break }
            }
        }
        return p
    }()
    let creditor = Player(name: "CPU", isHuman: false)

    PaymentSheet(
        debtor: debtor,
        creditor: creditor,
        amountOwed: 5,
        reason: .collectNow,
        onPay: { _, _ in }
    )
}
