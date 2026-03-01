import Foundation
import os.log

// MARK: - Game Logger
// In-memory circular buffer of game events. Accessible from the game UI.
// Also writes to os.log so events appear in Console.app / Xcode console.

enum LogLevel: String {
    case info  = "ℹ️"
    case warn  = "⚠️"
    case error = "🔴"
    case event = "🎮"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
}

@Observable
final class GameLogger {

    static let shared = GameLogger()
    private init() {}

    private(set) var entries: [LogEntry] = []
    private let maxEntries = 500

    // Incremented whenever a custom card image is saved or removed.
    // CardView reads this to force re-renders when images change in-game.
    private(set) var imageRevision: Int = 0
    func bumpImageRevision() { imageRevision += 1 }

    // Short human-readable activity feed for the game UI (newest first, max 8)
    private(set) var activityFeed: [String] = []
    func addActivity(_ msg: String) {
        activityFeed.insert(msg, at: 0)
        if activityFeed.count > 8 { activityFeed.removeLast() }
    }
    func clearActivity() { activityFeed.removeAll() }
    private let osLog = OSLog(subsystem: "com.tanmaysharma.godeal", category: "Game")

    // MARK: - File logging

    private var logFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("godeal_game.log")
    }

    private func appendToLogFile(_ line: String) {
        guard let url = logFileURL, let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            guard let fh = try? FileHandle(forWritingTo: url) else { return }
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Logging

    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        // Mirror to os.log for Console.app / Xcode console
        switch level {
        case .error, .warn:
            os_log(.error, log: osLog, "%{public}@", "\(level.rawValue) \(message)")
        default:
            os_log(.info, log: osLog, "%{public}@", "\(level.rawValue) \(message)")
        }
        // Persist to file (all levels)
        appendToLogFile("\(entry.formattedTime) \(level.rawValue) \(message)\n")
    }

    func clear() {
        entries.removeAll()
        if let url = logFileURL {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // Convenience wrappers
    func event(_ msg: String)  { log(msg, level: .event) }
    func warn(_ msg: String)   { log(msg, level: .warn) }
    func error(_ msg: String)  { log(msg, level: .error) }

    // Count of warnings + errors (for badge)
    var issueCount: Int {
        entries.filter { $0.level == .warn || $0.level == .error }.count
    }

    // Path of log file (for sharing / debugging)
    var logFilePath: String { logFileURL?.path ?? "unavailable" }
}
