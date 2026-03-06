import Foundation

// MARK: - Recent Opponent

struct RecentOpponent: Codable, Identifiable, Equatable {
    var id: String { gamePlayerID }
    let gamePlayerID: String
    let displayName: String
    let lastPlayed: Date
    let roomCode: String?
}

// MARK: - Recent Opponents Store

/// Persists recent GameKit opponents in UserDefaults for quick rematch.
enum RecentOpponentsStore {
    private static let key = "recentOpponents"
    private static let maxCount = 20

    static func load() -> [RecentOpponent] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RecentOpponent].self, from: data)) ?? []
    }

    static func save(_ opponents: [RecentOpponent]) {
        let trimmed = Array(opponents.prefix(maxCount))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Add or update opponents from a finished game. Most recent first.
    static func record(opponents: [(gamePlayerID: String, displayName: String)], roomCode: String?) {
        var list = load()
        let now = Date()
        for opp in opponents {
            list.removeAll { $0.gamePlayerID == opp.gamePlayerID }
            list.insert(RecentOpponent(
                gamePlayerID: opp.gamePlayerID,
                displayName: opp.displayName,
                lastPlayed: now,
                roomCode: roomCode
            ), at: 0)
        }
        save(list)
    }

    static func remove(gamePlayerID: String) {
        var list = load()
        list.removeAll { $0.gamePlayerID == gamePlayerID }
        save(list)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
