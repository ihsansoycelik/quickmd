import AppKit

extension Notification.Name {
    /// Posted when size or appearance changes, so every open window restyles.
    static let editorSettingsChanged = Notification.Name("QuickMDEditorSettingsChanged")
}

/// App-wide preferences, kept in UserDefaults. The look itself is fixed
/// (see `Design`); only size and light/dark are the user's.
@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard
    static let sizeRange: ClosedRange<CGFloat> = 11...32

    static var fontSize: CGFloat {
        get {
            let stored = defaults.double(forKey: "TextSize")
            return stored == 0 ? Design.defaultSize : min(max(CGFloat(stored), sizeRange.lowerBound), sizeRange.upperBound)
        }
        set {
            defaults.set(Double(min(max(newValue, sizeRange.lowerBound), sizeRange.upperBound)), forKey: "TextSize")
            changed()
        }
    }

    /// Set by the app delegate so the window appearance is updated
    /// before observers resolve the new theme (notification order is not
    /// guaranteed, and `.system` must no longer see the old fixed look).
    static var applicationAppearanceUpdater: (() -> Void)?

    static var themePreference: ThemePreference {
        get { ThemePreference(rawValue: defaults.string(forKey: "Theme") ?? "") ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: "Theme")
            applicationAppearanceUpdater?()
            changed()
        }
    }

    static var theme: Theme { themePreference.resolve() }

    /// Opening another file adds a tab to the front window instead of a new window.
    static var opensInTabs: Bool {
        get { defaults.object(forKey: "OpensInTabs") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "OpensInTabs"); changed() }
    }

    /// When another app (an agent, a script) writes an open note, the
    /// change types itself in and the window comes forward. Off: it just reloads.
    static var liveWriting: Bool {
        get { defaults.object(forKey: "LiveWriting") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "LiveWriting"); changed() }
    }

    /// View › Show Markdown Syntax: every mark shown, dimmed, everywhere.
    /// Off (the default), marks are hidden and the text reads styled.
    static var showsSyntax: Bool {
        get { defaults.bool(forKey: "ShowMarkdownSyntax") }
        set { defaults.set(newValue, forKey: "ShowMarkdownSyntax"); changed() }
    }

    /// View › Show Word Count: words and reading time in the window's subtitle.
    static var showsWordCount: Bool {
        get { defaults.object(forKey: "ShowWordCount") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ShowWordCount"); changed() }
    }

    /// View › Focus: every paragraph but the caret's is dimmed.
    static var focusMode: Bool {
        get { defaults.bool(forKey: "FocusMode") }
        set { defaults.set(newValue, forKey: "FocusMode"); changed() }
    }

    /// View › Typewriter: the caret's line stays in the middle of the window.
    static var typewriterMode: Bool {
        get { defaults.bool(forKey: "TypewriterMode") }
        set { defaults.set(newValue, forKey: "TypewriterMode"); changed() }
    }

    /// What File › New starts with.
    static var newDocumentStarter: Starter {
        get { Starter(rawValue: defaults.string(forKey: "NewDocumentStarter") ?? "") ?? .blank }
        set { defaults.set(newValue.rawValue, forKey: "NewDocumentStarter") }
    }

    // MARK: Writing and appearance (fonts, page, writing aids, counts)

    /// Settings › Writing font.
    static var writingFont: WritingFont {
        get { .stored }
        set { defaults.set(newValue.rawValue, forKey: "WritingFont"); changed() }
    }

    /// Settings › Line width.
    static var lineWidth: LineWidth {
        get { .stored }
        set { defaults.set(newValue.rawValue, forKey: "LineWidth"); changed() }
    }

    /// Settings › Page: the ground in light appearance.
    static var lightPage: LightPage {
        get { .stored }
        set { defaults.set(newValue.rawValue, forKey: "LightPage"); changed() }
    }

    /// Settings › Page: the ground in dark appearance.
    static var darkPage: DarkPage {
        get { .stored }
        set { defaults.set(newValue.rawValue, forKey: "DarkPage"); changed() }
    }

    /// What Focus keeps bright: the caret's paragraph or its sentence.
    static var focusScope: FocusScope {
        get { FocusScope(rawValue: defaults.string(forKey: "FocusScope") ?? "") ?? .paragraph }
        set { defaults.set(newValue.rawValue, forKey: "FocusScope"); changed() }
    }

    /// The title bar and tab bar fade while typing, back on mouse move.
    static var fadesChrome: Bool {
        get { defaults.bool(forKey: "FadeChrome") }
        set { defaults.set(newValue, forKey: "FadeChrome"); changed() }
    }

    /// Smart quotes and dashes while typing, never inside code.
    static var smartPunctuation: Bool {
        get { defaults.bool(forKey: "SmartPunctuation") }
        set { defaults.set(newValue, forKey: "SmartPunctuation"); changed() }
    }

    /// Display only: indented first lines, no blank-line gap between prose paragraphs.
    static var bookParagraphs: Bool {
        get { TypographyLook.current.bookParagraphs }
        set { defaults.set(newValue, forKey: "BookParagraphs"); changed() }
    }

    /// View › Show Count As.
    static var countStyle: CountStyle {
        get { CountStyle(rawValue: defaults.string(forKey: "CountStyle") ?? "") ?? .words }
        set { defaults.set(newValue.rawValue, forKey: "CountStyle"); changed() }
    }

    static let readingSpeedRange = 100...600

    /// Words a minute, for reading time.
    static var readingSpeed: Int {
        get {
            let stored = defaults.integer(forKey: "ReadingSpeed")
            return stored == 0 ? 230 : min(max(stored, readingSpeedRange.lowerBound), readingSpeedRange.upperBound)
        }
        set {
            defaults.set(min(max(newValue, readingSpeedRange.lowerBound), readingSpeedRange.upperBound), forKey: "ReadingSpeed")
            changed()
        }
    }

    /// View › Show Writing Aids.
    static var showsWritingAids: Bool {
        get { defaults.bool(forKey: "ShowWritingAids") }
        set { defaults.set(newValue, forKey: "ShowWritingAids"); changed() }
    }

    /// The aids that are on (all by default).
    static var writingAids: Set<WritingAids.Kind> {
        get {
            guard let stored = defaults.stringArray(forKey: "WritingAids") else { return Set(WritingAids.Kind.allCases) }
            return Set(stored.compactMap(WritingAids.Kind.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: "WritingAids"); changed() }
    }

    private static func changed() {
        NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
    }
}
