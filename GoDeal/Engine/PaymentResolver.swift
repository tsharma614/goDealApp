import Foundation

// MARK: - Payment Resolver
// Handles all debt-collection mechanics:
//   - No-change rule: overpayment kept by creditor
//   - Partial payment accepted if debtor has insufficient assets
//   - Pay from bank first, then properties if needed

enum PaymentResolver {

    struct PaymentResult {
        let amountPaid: Int
        let cardsPaid: [Card]
        let wasFullyPaid: Bool
    }

    // Resolve payment: debtor pays creditor up to `amount`.
    // Mutates state.players directly.
    @discardableResult
    static func resolvePayment(
        state: inout GameState,
        debtorIndex: Int,
        creditorIndex: Int,
        amount: Int
    ) -> PaymentResult {
        var debtor = state.players[debtorIndex]
        var creditor = state.players[creditorIndex]

        let bankPaid = payFromBank(player: &debtor, amount: amount)
        let bankTotal = bankPaid.reduce(0) { $0 + $1.monetaryValue }

        var propPaid: [(PropertyColor, Card)] = []
        var propTotal = 0

        if bankTotal < amount {
            // Need more from properties
            let stillOwed = amount - bankTotal
            propPaid = payFromProperties(player: &debtor, amount: stillOwed)
            propTotal = propPaid.reduce(0) { $0 + $1.1.monetaryValue }
        }

        let totalPaid = bankTotal + propTotal

        // Bank cards go to creditor's bank (no change back)
        for card in bankPaid {
            creditor.bank.append(card)
        }
        // Property cards go to creditor's property area (correct per game rules)
        for (color, card) in propPaid {
            creditor.placeProperty(card, in: color)
        }

        state.players[debtorIndex] = debtor
        state.players[creditorIndex] = creditor

        // Track rent collected/paid and peak bank
        if state.playerStats.count > creditorIndex {
            state.playerStats[creditorIndex].rentCollected += totalPaid
            let newBankTotal = state.players[creditorIndex].bankTotal
            if newBankTotal > state.playerStats[creditorIndex].peakBankValue {
                state.playerStats[creditorIndex].peakBankValue = newBankTotal
            }
        }
        if state.playerStats.count > debtorIndex {
            state.playerStats[debtorIndex].rentPaid += totalPaid
        }

        let allPaidCards = bankPaid + propPaid.map { $0.1 }
        return PaymentResult(
            amountPaid: totalPaid,
            cardsPaid: allPaidCards,
            wasFullyPaid: totalPaid >= amount
        )
    }

    // Pay rent to all other players (for two-color rent cards or bigSpender)
    static func resolveRentToAll(
        state: inout GameState,
        payerIndices: [Int],
        creditorIndex: Int,
        amountEach: Int
    ) {
        for debtorIndex in payerIndices where debtorIndex != creditorIndex {
            resolvePayment(
                state: &state,
                debtorIndex: debtorIndex,
                creditorIndex: creditorIndex,
                amount: amountEach
            )
        }
    }

    // MARK: - Private helpers

    // Pay as much as possible from bank cards, smallest first
    private static func payFromBank(player: inout Player, amount: Int) -> [Card] {
        var paid: [Card] = []
        var remaining = amount

        // Sort by value ascending — pay small denominations first
        let sorted = player.bank.enumerated()
            .sorted { player.bank[$0.offset].monetaryValue < player.bank[$1.offset].monetaryValue }

        var indices: [Int] = []
        var soFar = 0

        for (offset, _) in sorted {
            if soFar >= remaining { break }
            indices.append(offset)
            soFar += player.bank[offset].monetaryValue
        }

        // Remove in reverse index order
        for idx in indices.sorted().reversed() {
            paid.append(player.bank.remove(at: idx))
        }

        return paid
    }

    // Pay from properties when bank is insufficient — properties are sorted by monetaryValue ascending.
    // Returns (color, card) pairs so the creditor can place them in the correct property area.
    private static func payFromProperties(player: inout Player, amount: Int) -> [(PropertyColor, Card)] {
        var paid: [(PropertyColor, Card)] = []
        var remaining = amount

        // Collect (color, card) pairs sorted by card monetaryValue ascending
        // Do NOT take from complete sets first — take cheapest properties first
        var candidates: [(PropertyColor, Card)] = []
        for (color, set) in player.properties {
            for card in set.properties {
                candidates.append((color, card))
            }
        }
        candidates.sort { $0.1.monetaryValue < $1.1.monetaryValue }

        for (color, card) in candidates {
            if remaining <= 0 { break }
            if let removed = player.properties[color]?.removeProperty(withId: card.id) {
                if player.properties[color]?.properties.isEmpty == true {
                    player.properties.removeValue(forKey: color)
                } else if player.properties[color]?.isComplete == false {
                    // Set is now incomplete — strip improvements that require a full set
                    player.properties[color]?.hasCornerStore = false
                    player.properties[color]?.hasApartmentBuilding = false
                }
                paid.append((color, removed))
                remaining -= removed.monetaryValue
            }
        }

        return paid
    }
}
