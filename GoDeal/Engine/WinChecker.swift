import Foundation

// MARK: - Win Checker
// Returns the winning player's index if any player has 3+ complete property sets, else nil.

enum WinChecker {
    static func check(_ state: GameState) -> Int? {
        // Check the current player first — if they triggered the win condition, they win
        // (handles the edge case where multiple players reach 3 sets simultaneously)
        let currentIdx = state.currentPlayerIndex
        if state.players[currentIdx].completedSets >= 3 {
            return currentIdx
        }
        for (index, player) in state.players.enumerated() where index != currentIdx {
            if player.completedSets >= 3 {
                return index
            }
        }
        return nil
    }

    // Check a specific player only
    static func playerWins(_ player: Player) -> Bool {
        player.completedSets >= 3
    }
}
