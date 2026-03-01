import SwiftUI

// MARK: - Card Detail Sheet
// Full-size card view with name and description. Triggered by long-press on a hand card.

struct CardDetailSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    CardView(card: card, size: .large)
                        .padding(.top, 8)

                    VStack(spacing: 8) {
                        Text(card.name)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text(card.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                    }

                    HStack(spacing: 24) {
                        VStack(spacing: 2) {
                            Text("Value")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("$\(card.monetaryValue)M")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.green)
                        }

                        if case .property(let color) = card.type {
                            VStack(spacing: 2) {
                                Text("District")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(color.displayName)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(color.uiColor.opacity(0.2), in: Capsule())
                            }
                        }

                        if case .rent = card.type {
                            VStack(spacing: 2) {
                                Text("Charges")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("All players")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                            }
                        }

                        if case .wildRent = card.type {
                            VStack(spacing: 2) {
                                Text("Charges")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("One player")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    Spacer(minLength: 20)
                }
                .padding(.bottom)
            }
            .navigationTitle("Card Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CardDetailSheet(card: DeckBuilder.buildDeck().first { if case .action(.quickGrab) = $0.type { return true }; return false }!)
}
