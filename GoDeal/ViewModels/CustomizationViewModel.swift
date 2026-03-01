import Foundation
import SwiftUI

// MARK: - Customization View Model

@Observable
final class CustomizationViewModel {

    // Street name editing — keyed by color, then index
    var editingNames: [PropertyColor: [String]] = [:]
    var hasUnsavedChanges = false

    init() {
        loadAllNames()
    }

    // MARK: - Street Names

    private func loadAllNames() {
        for color in PropertyColor.allCases {
            editingNames[color] = PropertyNameStore.names(for: color)
        }
    }

    func updateName(_ name: String, for color: PropertyColor, at index: Int) {
        editingNames[color]?[index] = name
        hasUnsavedChanges = true
    }

    func saveNames(for color: PropertyColor) {
        guard let names = editingNames[color] else { return }
        PropertyNameStore.setNames(names, for: color)
        hasUnsavedChanges = false
    }

    func saveAllNames() {
        for color in PropertyColor.allCases {
            if let names = editingNames[color] {
                PropertyNameStore.setNames(names, for: color)
            }
        }
        hasUnsavedChanges = false
    }

    func resetNames(for color: PropertyColor) {
        PropertyNameStore.resetToDefaults(for: color)
        editingNames[color] = color.defaultStreetNames
        hasUnsavedChanges = false
    }

    func resetAllNames() {
        PropertyNameStore.resetAllToDefaults()
        loadAllNames()
        hasUnsavedChanges = false
    }

    // MARK: - Card Images

    func hasCustomImage(for assetKey: String) -> Bool {
        CardImageStore.hasCustomImage(for: assetKey)
    }

    func removeCustomImage(for assetKey: String) {
        CardImageStore.removeCustomImage(for: assetKey)
    }
}
