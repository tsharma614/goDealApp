import SwiftUI
import PhotosUI

// MARK: - Card Customization View
// Shows card categories (not individual cards). One custom image applies to all cards of that type.

struct CardCustomizationView: View {
    let deck: [Card]
    @Environment(CustomizationViewModel.self) private var viewModel
    @State private var selectedKey: String? = nil
    @State private var photosPickerItem: PhotosPickerItem? = nil
    @State private var isShowingPicker = false
    @State private var errorMessage: String? = nil
    @State private var refreshToggle = false   // forces row refresh after save/remove

    // Derive unique categories from the deck, in a sensible display order
    private var categories: [CardCategory] {
        var seen = Set<String>()
        var result: [CardCategory] = []
        for card in deck {
            let key = CardImageStore.categoryKey(for: card)
            if !seen.contains(key) {
                seen.insert(key)
                result.append(CardCategory(key: key, card: card))
            }
        }
        return result
    }

    // Group categories by section
    private var moneyCats:    [CardCategory] { categories.filter { if case .money = $0.card.type { return true }; return false } }
    private var propertyCats: [CardCategory] { categories.filter { if case .property = $0.card.type { return true }; return false } }
    private var wildPropCats: [CardCategory] { categories.filter { if case .wildProperty = $0.card.type { return true }; return false } }
    private var actionCats:   [CardCategory] { categories.filter { if case .action = $0.card.type { return true }; return false } }
    private var rentCats:     [CardCategory] { categories.filter { if case .rent = $0.card.type { return true }; return false } }
    private var wildRentCats: [CardCategory] { categories.filter { if case .wildRent = $0.card.type { return true }; return false } }

    var body: some View {
        NavigationStack {
            List {
                section("Money Cards", categories: moneyCats)
                section("Property Districts", categories: propertyCats)
                section("Wild Properties", categories: wildPropCats)
                section("Action Cards", categories: actionCats)
                section("Rent Cards", categories: rentCats)
                section("Wild Rent", categories: wildRentCats)
            }
            .navigationTitle("Card Images")
            .navigationBarTitleDisplayMode(.inline)
            .photosPicker(isPresented: $isShowingPicker, selection: $photosPickerItem, matching: .images)
            .onChange(of: photosPickerItem) { _, newValue in
                Task { await loadAndSaveImage(item: newValue) }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, categories: [CardCategory]) -> some View {
        if !categories.isEmpty {
            Section(title) {
                ForEach(categories, id: \.key) { cat in
                    let hasImage = CardImageStore.hasCustomImage(for: cat.key)
                    CardCategoryRow(
                        category: cat,
                        hasCustomImage: hasImage,
                        onTapImage: {
                            selectedKey = cat.key
                            isShowingPicker = true
                        },
                        onRemove: {
                            CardImageStore.removeCustomImage(for: cat.key)
                            refreshToggle.toggle()
                            GameLogger.shared.bumpImageRevision()
                        }
                    )
                    // Force full row rebuild after save/remove so thumbnail + badge update immediately
                    .id("\(cat.key)-\(refreshToggle)")
                }
            }
        }
    }

    private func loadAndSaveImage(item: PhotosPickerItem?) async {
        guard let item, let key = selectedKey else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let cropped = cropToCardRatio(uiImage)
                try CardImageStore.saveCustomImage(cropped, for: key)
                refreshToggle.toggle()
                GameLogger.shared.bumpImageRevision()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        photosPickerItem = nil
        selectedKey = nil
    }

    // Crop image to 5:7 card ratio before saving (G3)
    private func cropToCardRatio(_ image: UIImage) -> UIImage {
        let targetRatio: CGFloat = 5.0 / 7.0
        let w = image.size.width, h = image.size.height
        let scale = image.scale

        let cropRect: CGRect
        if w / h > targetRatio {
            let newW = h * targetRatio
            cropRect = CGRect(x: ((w - newW) / 2) * scale, y: 0, width: newW * scale, height: h * scale)
        } else {
            let newH = w / targetRatio
            cropRect = CGRect(x: 0, y: ((h - newH) / 2) * scale, width: w * scale, height: newH * scale)
        }

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
    }
}

// MARK: - Card Category Model

struct CardCategory {
    let key: String
    let card: Card   // representative card for thumbnail and name

    var displayName: String {
        switch card.type {
        case .money(let value):     return "$\(value)M bills"
        case .property(let color):  return color.displayName
        case .wildProperty:         return "Wild Property"
        case .action:               return card.name
        case .rent(let colors):
            return colors.map { $0.displayName }.joined(separator: " / ")
        case .wildRent:             return "Wild Rent (Rent Blitz!)"
        }
    }
}

// MARK: - Card Category Row

struct CardCategoryRow: View {
    let category: CardCategory
    let hasCustomImage: Bool
    let onTapImage: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail: category image or default card rendering
            Group {
                if let uiImage = CardImageStore.loadCustomImage(for: category.key) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                } else {
                    CardView(card: category.card, size: .small)
                        .scaleEffect(50.0 / 60.0)
                        .frame(width: 50, height: 70)
                        .clipped()
                }
            }
            .onTapGesture(perform: onTapImage)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.displayName)
                    .font(.body.weight(.medium))
                Text("All cards of this type")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if hasCustomImage {
                    Label("Custom image", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: onTapImage) {
                    Label("Change", systemImage: "photo")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                if hasCustomImage {
                    Button("Reset", role: .destructive, action: onRemove)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CardCustomizationView(deck: DeckBuilder.buildDeck())
        .environment(CustomizationViewModel())
}
