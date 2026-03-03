import Foundation

// MARK: - Property Color

enum PropertyColor: String, CaseIterable, Hashable, Codable {
    case rustDistrict   // brown (2)
    case skylineAve     // light blue (3)
    case neonRow        // pink (3)
    case sunsetStrip    // orange (3)
    case hotZone        // red (3)
    case goldRush       // yellow (3)
    case emeraldQuarter // green (3)
    case blueChip       // dark blue (2)
    case transitLine    // railroad (4)
    case powerAndWater  // utility (2)

    // Number of properties needed for a complete set
    var setSize: Int {
        switch self {
        case .rustDistrict:   return 2
        case .skylineAve:     return 3
        case .neonRow:        return 3
        case .sunsetStrip:    return 3
        case .hotZone:        return 3
        case .goldRush:       return 3
        case .emeraldQuarter: return 3
        case .blueChip:       return 2
        case .transitLine:    return 4
        case .powerAndWater:  return 2
        }
    }

    // Rent table indexed by: [1 prop, 2 props, full set, full+cornerStore(+$3M), full+apartmentBuilding(+$4M)]
    // Corner Store always adds exactly $3M; Apartment Building always adds exactly $4M (cumulative: +$7M over full).
    // Transit and Power & Water don't support improvements (indices 3 & 4 unused).
    var rentTable: [Int] {
        switch self {
        case .rustDistrict:   return [1, 2, 3, 6, 10]      // Brown       full=3  +CS=6  +AB=10
        case .skylineAve:     return [1, 2, 3, 6, 10]      // Light Blue  full=3  +CS=6  +AB=10
        case .neonRow:        return [1, 2, 4, 7, 11]      // Pink        full=4  +CS=7  +AB=11
        case .sunsetStrip:    return [1, 3, 5, 8, 12]      // Orange      full=5  +CS=8  +AB=12
        case .hotZone:        return [2, 3, 6, 9, 13]      // Red         full=6  +CS=9  +AB=13
        case .goldRush:       return [2, 4, 6, 9, 13]      // Yellow      full=6  +CS=9  +AB=13
        case .emeraldQuarter: return [2, 4, 7, 10, 14]     // Green       full=7  +CS=10 +AB=14
        case .blueChip:       return [3, 8, 8, 11, 15]     // Dark Blue   full=8  +CS=11 +AB=15
        case .transitLine:    return [1, 2, 3, 4, 4]       // Railroad (4 props max, no improvements)
        case .powerAndWater:  return [1, 2, 2, 2, 2]       // Utility (flat, no improvements)
        }
    }

    // Rent for a given number of properties owned (0-based: 1 prop = index 0)
    func rent(for propertyCount: Int) -> Int {
        guard propertyCount > 0 else { return 0 }
        let index = min(propertyCount - 1, rentTable.count - 1)
        return rentTable[index]
    }

    var displayName: String {
        switch self {
        case .rustDistrict:   return "Rust District"
        case .skylineAve:     return "Skyline Ave"
        case .neonRow:        return "Neon Row"
        case .sunsetStrip:    return "Sunset Strip"
        case .hotZone:        return "Hot Zone"
        case .goldRush:       return "Gold Rush"
        case .emeraldQuarter: return "Emerald Quarter"
        case .blueChip:       return "Blue Chip"
        case .transitLine:    return "Transit Line"
        case .powerAndWater:  return "Power & Water"
        }
    }

    // Default street names for each district
    var defaultStreetNames: [String] {
        switch self {
        case .rustDistrict:   return ["Tin Can Alley", "Rusty Nail Road"]
        case .skylineAve:     return ["Cloud Nine Court", "Breeze Blvd", "Azure Lane"]
        case .neonRow:        return ["Glitter Gulch", "Flashy Street", "Neon Heights"]
        case .sunsetStrip:    return ["Tangerine Terrace", "Amber Ave", "Blaze Blvd"]
        case .hotZone:        return ["Inferno Lane", "Ember Street", "Scorched Row"]
        case .goldRush:       return ["Nugget Drive", "Prospector's Path", "Fortune Falls"]
        case .emeraldQuarter: return ["Clover Court", "Jade Junction", "Evergreen Estate"]
        case .blueChip:       return ["Pinnacle Plaza", "Summit Square"]
        case .transitLine:    return ["North Station", "East Terminal", "West Junction", "Central Hub"]
        case .powerAndWater:  return ["Current Creek", "Pipeline Pass"]
        }
    }
}
