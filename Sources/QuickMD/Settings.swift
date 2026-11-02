import AppKit

extension Notification.Name {
    /// Posted when font, size, theme or layout preferences change, so
    /// every open window restyles.
    static let editorSettingsChanged = Notification.Name("QuickMDEditorSettingsChanged")
}

/// App-wide editor preferences, kept in UserDefaults.
@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard
    static let sizeRange: ClosedRange<CGFloat> = 11...32

    /// Body font, remembered per template. Invisible Details starts
    /// on Inter, Classic on Charter.
    static var fontFace: FontFace {
        get {
            let stored = defaults.string(forKey: fontKey) ?? ""
            return stored.isEmpty ? template.defaultFace : FontFace(rawValue: stored)
        }
        set { defaults.set(newValue.rawValue, forKey: fontKey); changed() }
    }

    /// Heading font, per template; nil keeps the template's own
    /// (Myeongjo for Invisible Details, bold body for Classic).
    static var headingFace: FontFace? {
        get {
            let stored = defaults.string(forKey: "HeadingFace.\(template.rawValue)") ?? ""
            return stored.isEmpty ? nil : FontFace(rawValue: stored)
        }
        set { defaults.set(newValue?.rawValue ?? "", forKey: "HeadingFace.\(template.rawValue)"); changed() }
    }

    private static var fontKey: String { template == .classic ? "FontFace" : "FontFace.\(template.rawValue)" }

    /// Opening another file adds a tab to the front window instead of
    /// a new window.
    static var opensInTabs: Bool {
        get { defaults.object(forKey: "OpensInTabs") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "OpensInTabs"); changed() }
    }

    /// When another app (an agent, a script) writes an open note, the
    /// change types itself in, the view follows it, and the window
    /// comes forward. Off: the note just reloads.
    static var liveWriting: Bool {
        get { defaults.object(forKey: "LiveWriting") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "LiveWriting"); changed() }
    }

    /// What File › New starts with.
    static var newDocumentStarter: Starter {
        get { Starter(rawValue: defaults.string(forKey: "NewDocumentStarter") ?? "") ?? .blank }
        set { defaults.set(newValue.rawValue, forKey: "NewDocumentStarter") }
    }

    /// The page's look. Invisible Details sets its own fonts, so the
    /// Font menu only applies to Classic.
    static var template: Template {
        get { Template(rawValue: defaults.string(forKey: "Template") ?? "") ?? .looq }
        set { defaults.set(newValue.rawValue, forKey: "Template"); changed() }
    }

    /// Text size, remembered per template: the two are designed at
    /// different sizes.
    static var fontSize: CGFloat {
        get {
            let key = template == .classic ? "FontSize" : "FontSize.\(template.rawValue)"
            let stored = defaults.double(forKey: key)
            return stored == 0 ? template.defaultSize : min(max(CGFloat(stored), sizeRange.lowerBound), sizeRange.upperBound)
        }
        set {
            let key = template == .classic ? "FontSize" : "FontSize.\(template.rawValue)"
            defaults.set(Double(min(max(newValue, sizeRange.lowerBound), sizeRange.upperBound)), forKey: key)
            changed()
        }
    }

    static var themePreference: ThemePreference {
        get { ThemePreference(rawValue: defaults.string(forKey: "Theme") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "Theme"); changed() }
    }

    /// Lines stop at a comfortable measure; extra width becomes margin.
    static var readableWidth: Bool {
        get { defaults.object(forKey: "ReadableWidth") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ReadableWidth"); changed() }
    }

    static var showsOutline: Bool {
        get { defaults.bool(forKey: "ShowsOutline") }
        set { defaults.set(newValue, forKey: "ShowsOutline"); changed() }
    }

    /// What the footer counts.
    static var footerStat: FooterStat {
        get { FooterStat(rawValue: defaults.string(forKey: "FooterStat") ?? "") ?? .words }
        set { defaults.set(newValue.rawValue, forKey: "FooterStat") }
    }

    static var showsStatusBar: Bool {
        get { defaults.object(forKey: "ShowsStatusBar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ShowsStatusBar"); changed() }
    }

    /// How much of the desktop shows through the window.
    static var transparency: Transparency {
        get { Transparency(rawValue: defaults.string(forKey: "Transparency") ?? "") ?? .subtle }
        set { defaults.set(newValue.rawValue, forKey: "Transparency"); changed() }
    }

    static var theme: Theme { themePreference.resolve() }

    private static func changed() {
        NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
    }
}
