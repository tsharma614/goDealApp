import SwiftUI

// MARK: - Player Property View
// Shows a player's property sets in a compact grid.

struct PlayerPropertyView: View {
    let player: Player
    var isInteractive: Bool = false
    var onPropertyTap: ((Card, PropertyColor) -> Void)? = nil
    var onLongPress: ((PropertySet) -> Void)? = nil

    var body: some View {
        if player.properties.isEmpty {
            emptyState
        } else {
            propertySets
        }
    }

    private var emptyState: some View {
        HStack {
            Image(systemName: "house.slash")
                .foregroundStyle(.tertiary)
            Text("No properties yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }

    private var propertySets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(sortedSets, id: \.color) { set in
                    PropertySetView(
                        set: set,
                        isInteractive: isInteractive,
                        onPropertyTap: onPropertyTap,
                        onLongPress: onLongPress
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.7).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: sortedSets.map { $0.color })
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    private var sortedSets: [PropertySet] {
        player.properties.values.sorted { a, b in
            // Complete sets first, then by color order
            if a.isComplete != b.isComplete { return a.isComplete }
            let order = PropertyColor.allCases
            let ai = order.firstIndex(of: a.color) ?? 0
            let bi = order.firstIndex(of: b.color) ?? 0
            return ai < bi
        }
    }
}

// MARK: - Property Set View

struct PropertySetView: View {
    let set: PropertySet
    var isInteractive: Bool = false
    var onPropertyTap: ((Card, PropertyColor) -> Void)? = nil
    var onLongPress: ((PropertySet) -> Void)? = nil

    var body: some View {
        VStack(spacing: 2) {
            // Set header
            setHeader

            // Show only top card with a count badge.
            // Wild cards are preferred so the player can always see them on top.
            ZStack(alignment: .topTrailing) {
                let topCard = set.properties.first(where: {
                    if case .wildProperty = $0.type { return true }; return false
                }) ?? set.properties.last
                if let topCard {
                    CardView(card: topCard, isPlayable: true, size: .small)
                        .onTapGesture {
                            if isInteractive {
                                onPropertyTap?(topCard, set.color)
                            }
                        }
                }
                if set.properties.count > 1 {
                    Text("×\(set.properties.count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.white)
                        .offset(x: 6, y: -4)
                }
            }
            .frame(height: 84)

            // Improvements
            if set.hasCornerStore || set.hasTowerBlock {
                improvementBadges
            }

            // Rent label
            rentLabel
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(set.isComplete ? set.color.uiColor.opacity(0.18) : Color.clear)
        )
        .onLongPressGesture {
            if isInteractive { onLongPress?(set) }
        }
    }

    private var setHeader: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(set.color.uiColor)
                .frame(width: 8, height: 8)
            Text(set.color.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if set.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 10))
            } else {
                Text("\(set.properties.count)/\(set.color.setSize)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 70)
    }

    private var improvementBadges: some View {
        HStack(spacing: 2) {
            if set.hasCornerStore {
                Text("CS")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.3), in: Capsule())
            }
            if set.hasTowerBlock {
                Text("TB")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.3), in: Capsule())
            }
        }
    }

    private var rentLabel: some View {
        Text("Rent: $\(set.currentRent)M")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
    }
}

#Preview {
    let player: Player = {
        var p = Player(name: "Test", isHuman: true)
        let deck = DeckBuilder.buildDeck()
        for card in deck.prefix(5) {
            if case .property(let color) = card.type {
                p.placeProperty(card, in: color)
            }
        }
        return p
    }()
    PlayerPropertyView(player: player, isInteractive: true)
        .padding()
}
