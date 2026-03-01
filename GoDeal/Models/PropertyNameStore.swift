import Foundation

// MARK: - Property Name Store
// Manages user-customizable street names, persisted in UserDefaults.

struct PropertyNameStore {

    private static let keyPrefix = "streetNames."

    // Returns current names for a color (custom if set, otherwise defaults)
    static func names(for color: PropertyColor) -> [String] {
        let key = keyPrefix + color.rawValue
        if let stored = UserDefaults.standard.array(forKey: key) as? [String],
           stored.count == color.defaultStreetNames.count {
            return stored
        }
        return color.defaultStreetNames
    }

    // Returns the name for a specific property at index within a district
    static func name(for color: PropertyColor, at index: Int) -> String {
        let list = names(for: color)
        guard index >= 0 && index < list.count else {
            return color.defaultStreetNames[safe: index] ?? "\(color.displayName) \(index + 1)"
        }
        return list[index]
    }

    // Persist custom names for a color
    static func setNames(_ names: [String], for color: PropertyColor) {
        let key = keyPrefix + color.rawValue
        UserDefaults.standard.set(names, forKey: key)
    }

    // Reset a single color to defaults
    static func resetToDefaults(for color: PropertyColor) {
        let key = keyPrefix + color.rawValue
        UserDefaults.standard.removeObject(forKey: key)
    }

    // Reset all colors to defaults
    static func resetAllToDefaults() {
        for color in PropertyColor.allCases {
            resetToDefaults(for: color)
        }
    }
}

