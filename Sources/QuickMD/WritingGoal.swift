import AppKit

/// View › Show Count As: what the window's subtitle counts.
enum CountStyle: String, CaseIterable {
    case words, characters, lines

    var displayName: String {
        switch self {
        case .words: return L("Words")
        case .characters: return L("Characters")
        case .lines: return L("Lines")
        }
    }
}

/// The subtitle's count line: words, characters or lines, reading time,
/// and the writing goal when one is set.
enum WritingStats {
    static func words(_ text: String) -> Int {
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        return words
    }

    static func characters(_ text: String) -> Int { text.filter { !$0.isNewline }.count }

    /// Lines as the editor shows them; a final line break adds none.
    static func lines(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 1
        for c in text.utf16 where c == 0x0A { count += 1 }
        return text.hasSuffix("\n") ? count - 1 : count
    }

    static func minutes(words: Int, wordsPerMinute: Int) -> Int {
        words == 0 ? 0 : max(1, Int((Double(words) / Double(max(1, wordsPerMinute))).rounded(.up)))
    }

    static func number(_ n: Int) -> String { NumberFormatter.localizedString(from: n as NSNumber, number: .decimal) }

    /// "320 / 1,000 words · 2 min read", "1,204 characters · 2 min read"…
    /// `selection`, when it has words, is counted instead of `text`, and
    /// the goal (always in words, for the whole note) is left out.
    static func subtitle(text: String, selection: String? = nil, style: CountStyle = .words,
                         goal: Int? = nil, wordsPerMinute: Int = 230) -> String {
        var counted = text
        var isSelection = false
        if let selection, words(selection) > 0 {
            counted = selection
            isSelection = true
        }
        let wordCount = words(counted)
        let minutes = minutes(words: wordCount, wordsPerMinute: wordsPerMinute)
        let read = String(format: L("%@ min read"), number(minutes))
        let goalPart: String? = {
            guard let goal, goal > 0, !isSelection else { return nil }
            let line = String(format: L("%@ / %@ words"), number(wordCount), number(goal))
            return wordCount >= goal ? "✓ " + line : line
        }()
        switch style {
        case .words:
            if let goalPart { return goalPart + " · " + read }
            return String(format: L("%@ words · %@ min read"), number(wordCount), number(minutes))
        case .characters:
            return ([String(format: L("%@ characters"), number(characters(counted))), goalPart ?? read]).joined(separator: " · ")
        case .lines:
            return ([String(format: L("%@ lines"), number(lines(counted))), goalPart ?? read]).joined(separator: " · ")
        }
    }
}

/// A word target per note, kept in the app's defaults by file path (never
/// in the file). An untitled note keeps its goal while it's open.
@MainActor
enum WritingGoals {
    private static let key = "WritingGoals"
    private static var unsaved: [ObjectIdentifier: Int] = [:]

    static func goal(for document: NSDocument?) -> Int? {
        guard let document else { return nil }
        if let path = document.fileURL?.path {
            return (UserDefaults.standard.dictionary(forKey: key) as? [String: Int])?[path]
        }
        return unsaved[ObjectIdentifier(document)]
    }

    static func setGoal(_ goal: Int?, for document: NSDocument) {
        let value = goal.flatMap { $0 > 0 ? $0 : nil }
        guard let path = document.fileURL?.path else {
            unsaved[ObjectIdentifier(document)] = value
            return
        }
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        all[path] = value
        UserDefaults.standard.set(all, forKey: key)
    }
}

extension DocumentWindowController {
    var writingGoal: Int? { WritingGoals.goal(for: document as? NSDocument) }

    /// View › Writing Goal…: a word target for this note.
    @objc func setWritingGoal(_ sender: Any?) {
        guard let window, let document = document as? NSDocument else { return }
        let alert = NSAlert()
        alert.messageText = L("Writing Goal")
        alert.informativeText = L("Words to write in this note. The goal is kept on this Mac, not in the file.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 1
        formatter.maximum = 1_000_000
        field.formatter = formatter
        field.placeholderString = WritingStats.number(1000)
        if let goal = writingGoal { field.integerValue = goal }
        field.setAccessibilityLabel(L("Words"))
        alert.accessoryView = field
        alert.addButton(withTitle: L("Set Goal"))
        alert.addButton(withTitle: L("Cancel"))
        if writingGoal != nil { alert.addButton(withTitle: L("Remove Goal")) }
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                let value = (formatter.number(from: field.stringValue) as? Int) ?? field.integerValue
                guard value > 0 else { return }
                WritingGoals.setGoal(value, for: document)
                if !Settings.showsWordCount { Settings.showsWordCount = true }
            case .alertThirdButtonReturn:
                WritingGoals.setGoal(nil, for: document)
            default:
                return
            }
            NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
        }
    }
}

/// The View menu's writing items: Show Count As, Writing Goal…, Show Writing Aids.
@MainActor
final class WritingMenu: NSObject, NSMenuItemValidation {
    static let shared = WritingMenu()

    static func addItems(to menu: NSMenu) {
        let counts = NSMenu(title: L("Show Count As"))
        for style in CountStyle.allCases {
            let entry = NSMenuItem(title: style.displayName, action: #selector(chooseCountStyle(_:)), keyEquivalent: "")
            entry.target = shared
            entry.representedObject = style.rawValue
            counts.addItem(entry)
        }
        let countsItem = NSMenuItem(title: counts.title, action: nil, keyEquivalent: "")
        countsItem.submenu = counts
        menu.addItem(countsItem)
        menu.addItem(NSMenuItem(title: L("Writing Goal…"), action: #selector(DocumentWindowController.setWritingGoal(_:)), keyEquivalent: ""))
        let aids = NSMenuItem(title: L("Show Writing Aids"), action: #selector(toggleWritingAids(_:)), keyEquivalent: "")
        aids.target = shared
        menu.addItem(aids)
    }

    @objc func chooseCountStyle(_ sender: NSMenuItem) {
        if let style = CountStyle(rawValue: sender.representedObject as? String ?? "") {
            Settings.countStyle = style
            if !Settings.showsWordCount { Settings.showsWordCount = true }
        }
    }

    @objc func toggleWritingAids(_ sender: Any?) { Settings.showsWritingAids.toggle() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(chooseCountStyle(_:)):
            menuItem.state = Settings.countStyle.rawValue == menuItem.representedObject as? String ? .on : .off
        case #selector(toggleWritingAids(_:)):
            menuItem.state = Settings.showsWritingAids ? .on : .off
        default:
            break
        }
        return true
    }
}
