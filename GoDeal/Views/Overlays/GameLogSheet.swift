import SwiftUI

// MARK: - Game Log Sheet
// Debug log viewer. Accessible via the bug button in the game top bar.

struct GameLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filterLevel: LogLevel? = nil

    private let logger = GameLogger.shared

    private var filteredEntries: [LogEntry] {
        let all = logger.entries.reversed()
        guard let level = filterLevel else { return Array(all) }
        return all.filter { $0.level == level }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No log entries",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Game events will appear here as you play.")
                    )
                } else {
                    List(filteredEntries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(entry.level.rawValue)
                                Text(entry.formattedTime)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(rowColor(entry.level))
                                .textSelection(.enabled)
                        }
                        .listRowBackground(rowBackground(entry.level))
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Game Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("All entries") { filterLevel = nil }
                        Button("Events only") { filterLevel = .event }
                        Button("Warnings only") { filterLevel = .warn }
                        Button("Errors only") { filterLevel = .error }
                        Divider()
                        Button("Clear log", role: .destructive) { logger.clear() }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    ShareLink(
                        item: logText,
                        subject: Text("Go! Deal! Game Log"),
                        message: Text("Game log from Go! Deal!")
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                if logger.issueCount > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(logger.issueCount) warning/error\(logger.issueCount == 1 ? "" : "s") logged")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
            }
        }
    }

    private var logText: String {
        logger.entries.map { "\($0.formattedTime) \($0.level.rawValue) \($0.message)" }
            .joined(separator: "\n")
    }

    private func rowColor(_ level: LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warn:  return .orange
        case .event: return .primary
        case .info:  return .secondary
        }
    }

    private func rowBackground(_ level: LogLevel) -> Color {
        switch level {
        case .error: return .red.opacity(0.07)
        case .warn:  return .orange.opacity(0.07)
        default:     return .clear
        }
    }
}

#Preview {
    let logger = GameLogger.shared
    logger.event("Turn 1 · CPU · drawing")
    logger.event("Turn 1 · CPU · playing (1/3 played)")
    logger.warn("Stuck state detected (CPU playing) — auto-triggering CPU")
    logger.error("Example error entry")
    return GameLogSheet()
}
