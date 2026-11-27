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

    private static func changed() {
        NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
    }
}
