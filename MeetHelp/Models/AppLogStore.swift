import Foundation
import Combine

struct AppLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

@MainActor
final class AppLogStore: ObservableObject {
    static let shared = AppLogStore()

    @Published private(set) var entries: [AppLogEntry] = []

    private let maxEntries = 600
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var combinedText: String {
        entries
            .map { "[\(timestampFormatter.string(from: $0.timestamp))] \($0.message)" }
            .joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
    }

    fileprivate func append(_ message: String) {
        guard shouldDisplay(message) else { return }

        entries.append(AppLogEntry(timestamp: Date(), message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    private func shouldDisplay(_ message: String) -> Bool {
        !message.hasPrefix("[AudioCapture] Received audio frame #")
    }
}

func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let message = items
        .map { String(describing: $0) }
        .joined(separator: separator)

    Swift.print(message, terminator: terminator)

    Task { @MainActor in
        AppLogStore.shared.append(message)
    }
}
