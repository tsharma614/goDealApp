import Foundation
import SwiftUI

// MARK: - Card Image Store
// Checks Documents/ for user-provided images first, falls back to Assets.xcassets.

enum CardImageStore {

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Category Key

    /// Stable key for the card's *type category* — used for custom image lookup.
    /// One image per category applies to all cards of that type.
    static func categoryKey(for card: Card) -> String {
        switch card.type {
        case .money(let value):     return "cat_money_\(value)"
        case .property(let color):  return "cat_prop_\(color.rawValue)"
        case .wildProperty:         return "cat_wildprop"
        case .action(let type):     return "cat_action_\(type.rawValue)"
        case .rent(let colors):
            let sorted = colors.map { $0.rawValue }.sorted().joined(separator: "_")
            return "cat_rent_\(sorted)"
        case .wildRent:             return "cat_wildrent"
        }
    }

    // MARK: - Load Image

    /// Returns a custom UIImage for a card: checks category key first, then per-card key.
    /// Returns nil if no custom image is set (caller should use default card rendering).
    static func image(for card: Card) -> UIImage? {
        loadCustomImage(for: categoryKey(for: card)) ?? loadCustomImage(for: card.assetKey)
    }

    /// Returns a UIImage for the given asset key (custom only).
    static func loadCustomImage(for assetKey: String) -> UIImage? {
        for ext in ["jpg", "png", "jpeg"] {
            let url = documentsURL.appendingPathComponent("\(assetKey).\(ext)")
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    // MARK: - Save Image

    static func saveCustomImage(_ image: UIImage, for assetKey: String) throws {
        let url = documentsURL.appendingPathComponent("\(assetKey).jpg")
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw ImageStoreError.compressionFailed
        }
        try data.write(to: url)
    }

    // MARK: - Check & Delete

    static func hasCustomImage(for assetKey: String) -> Bool {
        for ext in ["jpg", "png", "jpeg"] {
            let url = documentsURL.appendingPathComponent("\(assetKey).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return true }
        }
        return false
    }

    static func removeCustomImage(for assetKey: String) {
        for ext in ["jpg", "png", "jpeg"] {
            let url = documentsURL.appendingPathComponent("\(assetKey).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Errors

enum ImageStoreError: Error, LocalizedError {
    case compressionFailed

    var errorDescription: String? {
        "Failed to compress image for saving."
    }
}
