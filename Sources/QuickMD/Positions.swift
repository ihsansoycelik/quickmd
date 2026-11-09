import Foundation

/// Where the caret and the view were in each note, so reopening a note
/// puts you back where you left it. Kept in UserDefaults on this Mac
/// only, newest 300 notes.
enum Positions {
    struct Position: Equatable {
        var caret: Int
        /// The first character visible at the top of the view.
        var top: Int
    }

    private static let key = "NotePositions"
    private static let limit = 300
    nonisolated(unsafe) static var defaults = UserDefaults.standard

    static func position(for url: URL) -> Position? {
        guard let entry = all()[url.resolvingSymlinksInPath().path], entry.count >= 2 else { return nil }
        return Position(caret: Int(entry[0]), top: Int(entry[1]))
    }

    static func save(_ position: Position, for url: URL) {
        var entries = all()
        entries[url.resolvingSymlinksInPath().path] = [Double(position.caret), Double(position.top), Date().timeIntervalSince1970]
        if entries.count > limit {
            let oldest = entries.sorted { ($0.value.last ?? 0) < ($1.value.last ?? 0) }.prefix(entries.count - limit)
            oldest.forEach { entries[$0.key] = nil }
        }
        defaults.set(entries, forKey: key)
    }

    private static func all() -> [String: [Double]] {
        defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }
}
