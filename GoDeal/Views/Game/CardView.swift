import SwiftUI

// MARK: - Card View
// Renders a single card with appropriate styling based on its type.

struct CardView: View {
    var card: Card? = nil
    var isSelected: Bool = false
    var isPlayable: Bool = true
    var showBack: Bool = false
    var size: CardSize = .normal

    enum CardSize {
        case small, normal, large
        var width: CGFloat {
            switch self { case .small: 60; case .normal: 80; case .large: 110 }
        }
        var height: CGFloat {
            switch self { case .small: 84; case .normal: 112; case .large: 154 }
        }
        var fontSize: CGFloat {
            switch self { case .small: 8; case .normal: 11; case .large: 14 }
        }
    }

    var body: some View {
        ZStack {
            if showBack || card == nil {
                cardBack
            } else {
                cardFront
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: isSelected ? Color.accentColor.opacity(0.6) : .black.opacity(0.2),
                radius: isSelected ? 8 : 3, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .opacity(isPlayable ? 1.0 : 0.55)
        .animation(.spring(response: 0.25), value: isSelected)
    }

    // MARK: - Card Front

    private var cardFront: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .fill(cardBackground)

            if let c = card {
                defaultCardContent(for: c)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
    }

    @ViewBuilder
    private func defaultCardContent(for c: Card) -> some View {
        if case .wildProperty(let colors) = c.type {
            wildPropertyContent(c: c, colors: colors)
        } else if case .rent(let colors) = c.type, colors.count >= 2 {
            rentDualContent(c: c, colors: colors)
        } else {
            VStack(spacing: 2) {
                HStack {
                    Text("$\(c.monetaryValue)M")
                        .font(.system(size: size.fontSize - 1, weight: .bold))
                        .foregroundStyle(cardTextColor.opacity(0.8))
                    Spacer()
                }
                .padding(.horizontal, 5)
                .padding(.top, 4)

                Spacer()

                cardIcon
                    .font(.system(size: size.height * 0.22))

                Spacer()

                Text(c.name)
                    .font(.system(size: size.fontSize, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(cardTextColor)
                    .lineLimit(2)
                    .padding(.horizontal, 4)

                if size == .large {
                    Text(c.description)
                        .font(.system(size: size.fontSize - 2))
                        .foregroundStyle(cardTextColor.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 4)
                }
                Spacer(minLength: 4)
            }
        }
    }

    @ViewBuilder
    private func wildPropertyContent(c: Card, colors: [PropertyColor]) -> some View {
        VStack(spacing: 0) {
            // "WILD" badge pinned to top
            Text("WILD")
                .font(.system(size: size.fontSize, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(.black.opacity(0.35))

            Spacer()

            // Two color circles side by side (2-color wilds), or rainbow star (rainbow wilds)
            if colors.count == 2 {
                HStack(spacing: 6) {
                    ForEach(Array(colors.prefix(2).enumerated()), id: \.offset) { _, color in
                        VStack(spacing: 2) {
                            Circle()
                                .fill(color.uiColor)
                                .frame(width: size.width * 0.22, height: size.width * 0.22)
                                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                        }
                    }
                }
            } else {
                // Rainbow wild: show a colorful star
                Image(systemName: "star.fill")
                    .font(.system(size: size.height * 0.22))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }

            Spacer()

            // Card name and value pinned to bottom
            VStack(spacing: 1) {
                Text(c.name)
                    .font(.system(size: size.fontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                Text("$\(c.monetaryValue)M")
                    .font(.system(size: size.fontSize - 1, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
            .padding(.bottom, 3)
        }
    }

    // MARK: - Dual Rent Card (top/bottom color split)

    @ViewBuilder
    private func rentDualContent(c: Card, colors: [PropertyColor]) -> some View {
        VStack(spacing: 0) {
            // "DUES" banner at top — mirrors "WILD" on wild property cards
            Text("DUES")
                .font(.system(size: size.fontSize, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(.black.opacity(0.35))

            Spacer()

            // Dollar icon + two property color circles
            VStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: size.height * 0.2))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                HStack(spacing: 6) {
                    ForEach(Array(colors.prefix(2).enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color.uiColor)
                            .frame(width: size.width * 0.22, height: size.width * 0.22)
                            .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                    }
                }
            }

            Spacer()

            // Card name + monetary value at bottom — mirrors wild property card layout
            VStack(spacing: 1) {
                Text(c.name)
                    .font(.system(size: size.fontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                Text("$\(c.monetaryValue)M")
                    .font(.system(size: size.fontSize - 1, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
            .padding(.bottom, 3)
        }
    }

    // MARK: - Card Back

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius)
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text("GO!\nDEAL!")
                    .font(.system(size: size.fontSize + 2, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
    }

    // MARK: - Helpers

    private var cardCornerRadius: CGFloat { size.width * 0.1 }

    private var cardBackground: LinearGradient {
        guard let c = card else {
            return LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)], startPoint: .top, endPoint: .bottom)
        }
        switch c.type {
        case .money:
            return LinearGradient(colors: [.green.opacity(0.15), .green.opacity(0.05)], startPoint: .top, endPoint: .bottom)
        case .property(let color):
            return LinearGradient(colors: [color.uiColor.opacity(0.9), color.uiColor.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        case .wildProperty(let colors):
            if colors.count == 2 {
                // Hard split: left half = color[0], right half = color[1]
                return LinearGradient(stops: [
                    .init(color: colors[0].uiColor, location: 0.0),
                    .init(color: colors[0].uiColor, location: 0.5),
                    .init(color: colors[1].uiColor, location: 0.5),
                    .init(color: colors[1].uiColor, location: 1.0)
                ], startPoint: .leading, endPoint: .trailing)
            }
            // Rainbow wild (0 or 3+ colors) — full rainbow sweep
            return LinearGradient(
                colors: [Color.red, .orange, .yellow, .green, .blue, .purple].map { $0.opacity(0.8) },
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .action(let type):
            switch type {
            case .dealSnatcher:  return LinearGradient(colors: [Color(red: 0.8, green: 0, blue: 0), Color(red: 0.6, green: 0, blue: 0)], startPoint: .top, endPoint: .bottom)
            case .noDeal:        return LinearGradient(colors: [Color(UIColor.darkGray), Color(UIColor.darkGray).opacity(0.7)], startPoint: .top, endPoint: .bottom)
            case .quickGrab:     return LinearGradient(colors: [.teal, .teal.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            case .swapIt:        return LinearGradient(colors: [Color(UIColor.systemPink), Color(UIColor.systemPink).opacity(0.65)], startPoint: .top, endPoint: .bottom)
            case .collectNow:    return LinearGradient(colors: [Color(UIColor.systemOrange), .yellow.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            case .bigSpender:    return LinearGradient(colors: [Color(UIColor.systemGreen).opacity(0.85), .green.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            case .dealForward:   return LinearGradient(colors: [Color(UIColor.systemBlue).opacity(0.75), .cyan.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            case .doubleUp:      return LinearGradient(colors: [.purple.opacity(0.85), .purple.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            case .cornerStore:   return LinearGradient(colors: [Color(UIColor.brown).opacity(0.85), Color(UIColor.brown).opacity(0.55)], startPoint: .top, endPoint: .bottom)
            case .apartmentBuilding:    return LinearGradient(colors: [.indigo.opacity(0.9), .indigo.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            }
        case .rent(let colors):
            if colors.count >= 2 {
                // Hard top/bottom split — mirrors the left/right split on wild property cards
                return LinearGradient(stops: [
                    .init(color: colors[0].uiColor, location: 0.0),
                    .init(color: colors[0].uiColor, location: 0.5),
                    .init(color: colors[1].uiColor, location: 0.5),
                    .init(color: colors[1].uiColor, location: 1.0)
                ], startPoint: .top, endPoint: .bottom)
            } else if colors.count == 1 {
                return LinearGradient(colors: [colors[0].uiColor.opacity(0.9), colors[0].uiColor.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            }
            return LinearGradient(colors: [.orange.opacity(0.7), .red.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        case .wildRent:
            // Full rainbow to show it works for any color
            return LinearGradient(
                colors: [Color.red, .orange, .yellow, .green, .blue, .purple].map { $0.opacity(0.75) },
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var cardTextColor: Color {
        guard let c = card else { return .primary }
        switch c.type {
        case .property(let color):
            switch color {
            case .rustDistrict, .blueChip, .hotZone, .transitLine: return .white
            default: return .black.opacity(0.85)
            }
        case .action(let type):
            switch type {
            case .noDeal, .dealSnatcher, .quickGrab, .swapIt, .doubleUp, .cornerStore, .apartmentBuilding:
                return .white
            default: return .primary
            }
        case .rent(let colors):
            // Use white text on darker property colors
            if let first = colors.first {
                switch first {
                case .rustDistrict, .blueChip, .hotZone, .transitLine: return .white
                default: return .black.opacity(0.85)
                }
            }
            return .primary
        default: return .primary
        }
    }

    private var cardIcon: some View {
        Group {
            if let c = card {
                switch c.type {
                case .money(let value):
                    Text("$\(value)M")
                        .font(.system(size: size.height * 0.18, weight: .black, design: .rounded))
                        .foregroundStyle(.green)
                case .property:
                    Image(systemName: "house.fill")
                        .foregroundStyle(.white.opacity(0.8))
                case .wildProperty:
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                case .action(let type):
                    Image(systemName: actionIcon(type))
                        .foregroundStyle(.primary)
                case .rent:
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(.orange)
                case .wildRent:
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(.red)
                }
            } else {
                Image(systemName: "rectangle.fill").foregroundStyle(.clear)
            }
        }
    }

    private func actionIcon(_ type: ActionType) -> String {
        switch type {
        case .dealSnatcher:  return "hand.raised.fill"
        case .noDeal:        return "xmark.circle.fill"
        case .quickGrab:     return "hand.point.right.fill"
        case .swapIt:        return "arrow.left.arrow.right"
        case .collectNow:    return "dollarsign.square.fill"
        case .bigSpender:    return "party.popper.fill"
        case .dealForward:   return "arrow.forward.circle.fill"
        case .doubleUp:      return "multiply.circle.fill"
        case .cornerStore:   return "building.2.fill"
        case .apartmentBuilding:    return "building.columns.fill"
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        let deck = DeckBuilder.buildDeck()
        if deck.count > 5 {
            CardView(card: deck[0], size: .normal)
            CardView(card: deck[10], isSelected: true, size: .normal)
            CardView(card: deck[20], showBack: true, size: .normal)
            CardView(card: deck[30], size: .large)
        }
    }
    .padding()
}
