import Foundation

// MARK: - Shared Array Extension

extension Array {
    /// Safe subscript that returns nil instead of crashing on out-of-bounds.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
