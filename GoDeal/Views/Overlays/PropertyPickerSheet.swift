import SwiftUI

// MARK: - Property Picker Sheet
// Shown when the human player must choose a property for quickGrab, dealSnatcher, or swapIt.

struct PropertyPickerSheet: View {
    let purpose: PropertyChoicePurpose
    let humanPlayer: Player
    let targetPlayer: Player
    let onResolve: (UUID?, PropertyColor?, UUID?) -> Void  // (selectedCardId, selectedColor, secondaryCardId)
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            switch purpose {
            case .quickGrab:
                quickGrabPicker
            case .quickGrabVictim:
                quickGrabVictimPicker
            case .dealSnatcher:
                dealSnatcherPicker
            case .dealSnatcherVictim:
                dealSnatcherVictimPicker
            case .swapIt:
                swapItPicker
            case .swapItVictim:
                swapItVictimPicker
            default:
                Text("Invalid choice context")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    // MARK: - Quick Grab: steal one property from target's incomplete sets

    private var quickGrabPicker: some View {
        VStack(spacing: 12) {
            headerView(
                icon: "hand.point.right.fill",
                title: "Quick Grab!",
                subtitle: "Pick a property to steal from \(targetPlayer.name)"
            )

            let stealable = targetPlayer.properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
                .sorted { $0.monetaryValue > $1.monetaryValue }

            if stealable.isEmpty {
                Spacer()
                Text("No incomplete sets to steal from!")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], spacing: 12) {
                        ForEach(stealable) { card in
                            Button {
                                onResolve(card.id, nil, nil)
                            } label: {
                                CardView(card: card, size: .normal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Quick Grab!")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    // MARK: - Deal Snatcher: steal a complete set

    private var dealSnatcherPicker: some View {
        VStack(spacing: 12) {
            headerView(
                icon: "hand.raised.fill",
                title: "Deal Snatcher!",
                subtitle: "Pick a complete set to steal from \(targetPlayer.name)"
            )

            let completeSets = targetPlayer.properties.values
                .filter { $0.isComplete }
                .sorted { $0.currentRent > $1.currentRent }

            if completeSets.isEmpty {
                Spacer()
                Text("No complete sets to steal!")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(completeSets, id: \.color) { set in
                            Button {
                                onResolve(nil, set.color, nil)
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(set.color.uiColor)
                                        .frame(width: 20, height: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(set.color.displayName)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("\(set.properties.count) cards · Rent: $\(set.currentRent)M")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .padding()
                                .background(
                                    set.color.uiColor.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(set.color.uiColor.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Deal Snatcher!")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    // MARK: - Swap It: pick one of yours and one of theirs

    @State private var selectedMyCardId: UUID? = nil

    private var swapItPicker: some View {
        VStack(spacing: 12) {
            headerView(
                icon: "arrow.left.arrow.right",
                title: "Swap It!",
                subtitle: selectedMyCardId == nil
                    ? "Pick YOUR property to give away"
                    : "Now pick \(targetPlayer.name)'s property to take"
            )

            let myCards = humanPlayer.properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
                .sorted { $0.monetaryValue < $1.monetaryValue }
            let theirCards = targetPlayer.properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
                .sorted { $0.monetaryValue > $1.monetaryValue }

            if myCards.isEmpty || theirCards.isEmpty {
                Spacer()
                Text("Cannot swap — both players need at least one property in an incomplete set.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // My cards
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your property (to give):", systemImage: "person.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(myCards) { card in
                                        CardView(
                                            card: card,
                                            isSelected: selectedMyCardId == card.id,
                                            size: .normal
                                        )
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.2)) {
                                                selectedMyCardId = card.id
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Their cards
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(targetPlayer.name)'s property (to take):", systemImage: "person.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(theirCards) { card in
                                        CardView(
                                            card: card,
                                            isPlayable: selectedMyCardId != nil,
                                            size: .normal
                                        )
                                        .opacity(selectedMyCardId == nil ? 0.4 : 1.0)
                                        .onTapGesture {
                                            if let myId = selectedMyCardId {
                                                onResolve(myId, nil, card.id)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom)
                }
            }
        }
        .navigationTitle("Swap It!")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    // MARK: - Quick Grab Victim: human victim picks which property to sacrifice

    private var quickGrabVictimPicker: some View {
        VStack(spacing: 12) {
            headerView(
                icon: "hand.point.right.fill",
                title: "Quick Grab!",
                subtitle: "\(targetPlayer.name) is stealing one property from you — pick which to give up"
            )

            let sacrificeable = humanPlayer.properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
                .sorted { $0.monetaryValue < $1.monetaryValue }

            if sacrificeable.isEmpty {
                Spacer()
                Text("No incomplete sets — nothing to take!")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], spacing: 12) {
                        ForEach(sacrificeable) { card in
                            Button { onResolve(card.id, nil, nil) } label: {
                                CardView(card: card, size: .normal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Give Up a Property")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
    }

    // MARK: - Deal Snatcher Victim: human victim picks which complete set to give up

    private var dealSnatcherVictimPicker: some View {
        VStack(spacing: 12) {
            headerView(
                icon: "hand.raised.fill",
                title: "Deal Snatcher!",
                subtitle: "\(targetPlayer.name) is stealing a complete set — choose which one to give up"
            )

            let completeSets = humanPlayer.properties.values
                .filter { $0.isComplete }
                .sorted { $0.currentRent < $1.currentRent }

            if completeSets.isEmpty {
                Spacer()
                Text("No complete sets!")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(completeSets, id: \.color) { set in
                            Button { onResolve(nil, set.color, nil) } label: {
                                HStack(spacing: 12) {
                                    Circle().fill(set.color.uiColor).frame(width: 20, height: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(set.color.displayName).font(.body.weight(.semibold))
                                        Text("\(set.properties.count) cards · Rent: $\(set.currentRent)M")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                                }
                                .padding()
                                .background(set.color.uiColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(set.color.uiColor.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Give Up a Set")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
    }

    // MARK: - Swap It Victim: human victim picks their property + which of attacker's to take

    @State private var selectedVictimCardId: UUID? = nil

    private var swapItVictimPicker: some View {
        VStack(spacing: 12) {
            headerView(
                icon: "arrow.left.arrow.right",
                title: "Swap It!",
                subtitle: selectedVictimCardId == nil
                    ? "Pick YOUR property to give away"
                    : "Now pick \(targetPlayer.name)'s property to take in return"
            )

            let myCards = humanPlayer.properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
                .sorted { $0.monetaryValue < $1.monetaryValue }
            let theirCards = targetPlayer.properties.values
                .filter { !$0.isComplete }
                .flatMap { $0.properties }
                .sorted { $0.monetaryValue > $1.monetaryValue }

            if myCards.isEmpty || theirCards.isEmpty {
                Spacer()
                Text("Cannot swap — both players need at least one property in an incomplete set.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your property (to give):", systemImage: "person.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(myCards) { card in
                                        CardView(card: card, isSelected: selectedVictimCardId == card.id, size: .normal)
                                            .onTapGesture {
                                                withAnimation(.spring(response: 0.2)) { selectedVictimCardId = card.id }
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(targetPlayer.name)'s property (to take):", systemImage: "person.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(theirCards) { card in
                                        CardView(card: card, isPlayable: selectedVictimCardId != nil, size: .normal)
                                            .opacity(selectedVictimCardId == nil ? 0.4 : 1.0)
                                            .onTapGesture {
                                                if let myId = selectedVictimCardId {
                                                    // selectedCardId = my card (victim), secondaryCardId = their card (attacker)
                                                    onResolve(myId, nil, card.id)
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom)
                }
            }
        }
        .navigationTitle("Swap It!")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
    }

    // MARK: - Shared header

    private func headerView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .padding(.top)
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}
