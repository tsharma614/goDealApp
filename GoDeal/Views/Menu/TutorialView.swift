import SwiftUI

// MARK: - Tutorial View

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    tutorialSection(
                        icon: "trophy.fill",
                        iconColor: .yellow,
                        title: "Goal",
                        content: "Be the first player to collect **3 complete property sets**. A set is complete when you have all cards of that color."
                    )

                    tutorialSection(
                        icon: "arrow.clockwise",
                        iconColor: .blue,
                        title: "Your Turn",
                        content: """
                        1. **Draw 2 cards** from the deck (draw 5 if your hand is empty).
                        2. **Play up to 3 cards** — to your bank, property area, or as actions.
                        3. **End your turn.** Discard down to 7 cards if you have more.
                        """
                    )

                    Divider().padding(.horizontal)

                    sectionHeader("Card Types")

                    cardTypeRow(
                        color: .green,
                        icon: "banknote.fill",
                        name: "Money",
                        description: "Play to your bank. Used to pay rent and action debts. Higher value = fewer cards needed to pay."
                    )
                    cardTypeRow(
                        color: .orange,
                        icon: "house.fill",
                        name: "Property",
                        description: "Play to your property area in the matching color group. Complete a full set to count toward your win."
                    )
                    cardTypeRow(
                        color: .purple,
                        icon: "star.fill",
                        name: "Wild Property",
                        description: "Can be placed in either of its two colors. Long-press a wild card in your property area to move it to a different group."
                    )
                    cardTypeRow(
                        color: .red,
                        icon: "dollarsign.circle.fill",
                        name: "Collect Dues",
                        description: "Charge all players who own properties in either of the two listed colors. They must pay from their bank or properties."
                    )
                    cardTypeRow(
                        color: .indigo,
                        icon: "bolt.circle.fill",
                        name: "Rent Blitz",
                        description: "Charge any one player rent on any color you own — great for targeting the richest player."
                    )

                    Divider().padding(.horizontal)

                    sectionHeader("Action Cards")

                    actionRow(name: "Deal Forward!", icon: "arrow.forward.circle.fill", color: .blue,
                              description: "Draw 2 extra cards immediately.")
                    actionRow(name: "Double Up!", icon: "multiply.circle.fill", color: .purple,
                              description: "Play before a rent card on the same turn to double the amount charged.")
                    actionRow(name: "Collect Now!", icon: "dollarsign.square.fill", color: .orange,
                              description: "One player of your choice pays you $5M.")
                    actionRow(name: "Big Spender!", icon: "party.popper.fill", color: .green,
                              description: "Every other player pays you $2M each.")
                    actionRow(name: "Quick Grab!", icon: "hand.point.right.fill", color: .teal,
                              description: "Steal one property from another player's incomplete set.")
                    actionRow(name: "Deal Snatcher!", icon: "hand.raised.fill", color: .red,
                              description: "Steal an entire complete property set from any player.")
                    actionRow(name: "Swap It!", icon: "arrow.left.arrow.right", color: .pink,
                              description: "Trade one of your properties for any one of another player's.")
                    actionRow(name: "Corner Store", icon: "building.2.fill", color: Color(UIColor.brown),
                              description: "Add to a complete set to boost rent by $3M.")
                    actionRow(name: "Apartment Building", icon: "building.columns.fill", color: .indigo,
                              description: "Add after a Corner Store to boost rent by an additional $4M.")

                    Divider().padding(.horizontal)

                    tutorialSection(
                        icon: "xmark.circle.fill",
                        iconColor: Color(UIColor.darkGray),
                        title: "No Deal!",
                        content: "Play **No Deal!** from your hand in response to any action or rent played against you to cancel it completely. You can only block actions targeting you."
                    )

                    tutorialSection(
                        icon: "banknote",
                        iconColor: .green,
                        title: "Paying Debts",
                        content: "When you owe rent or an action fee, pay from your **bank first**, then from your properties if needed. You give the exact cards — no change is made. If you can't fully pay, give everything you have."
                    )

                    tutorialSection(
                        icon: "lightbulb.fill",
                        iconColor: .yellow,
                        title: "Tips",
                        content: """
                        • Keep No Deal! cards in hand — they're your best defense.
                        • Bank money cards you don't need to pay future debts.
                        • Double Up! must be played **before** the rent card on the same turn.
                        • Complete sets are protected from Quick Grab but not Deal Snatcher.
                        • Wild cards on complete sets **can** be moved to other groups.
                        """
                    )
                }
                .padding()
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .padding(.horizontal)
    }

    private func tutorialSection(icon: String, iconColor: Color, title: String, content: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(LocalizedStringKey(content))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func cardTypeRow(color: Color, icon: String, name: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.body)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func actionRow(name: String, icon: String, color: Color, description: String) -> some View {
        cardTypeRow(color: color, icon: icon, name: name, description: description)
    }
}

#Preview {
    TutorialView()
}
