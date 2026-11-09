import AppKit

enum Theme: String, CaseIterable {
    case dark
    case light
}

/// User-facing appearance preference, stored in UserDefaults under
/// "Theme". `.system` resolves at runtime against the app's appearance.
enum ThemePreference: String, CaseIterable {
    case light
    case dark
    case system

    var displayName: String {
        switch self {
        case .light: return L("Light")
        case .dark: return L("Dark")
        case .system: return L("System")
        }
    }

    @MainActor func resolve() -> Theme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? .dark : .light
        }
    }
}

extension NSAttributedString.Key {
    /// Marks a run as belonging to a fenced code block, so the layout
    /// manager can paint one full-width panel behind it instead of a
    /// ragged background that stops at the end of each line.
    static let qmCodeBlock = NSAttributedString.Key("qmCodeBlock")
    /// Lines inside a `$$` display-math block; painted like code.
    static let qmMathBlock = NSAttributedString.Key("qmMathBlock")
    /// Rows of a pipe table; the layout manager draws a framed panel.
    static let qmTable = NSAttributedString.Key("qmTable")
    /// A plain block-quote line; the layout manager draws its bar.
    /// The `|---|` row; reading mode collapses it.
    static let qmTableDelimiter = NSAttributedString.Key("qmTableDelimiter")
    static let qmQuote = NSAttributedString.Key("qmQuote")
    /// The header row of a pipe table.
    static let qmTableHeader = NSAttributedString.Key("qmTableHeader")
    /// Lines of a GitHub callout (`> [!TIP]`); the value is its colour.
    static let qmCallout = NSAttributedString.Key("qmCallout")
    /// A task's `[ ]` / `[x]`; the value is whether it's ticked. The
    /// characters go clear and a real checkbox is drawn over them.
    static let qmCheckbox = NSAttributedString.Key("qmCheckbox")
}

/// Colours for fenced code, shared by the editor and the preview.
struct CodeColors {
    let keyword: NSColor
    let string: NSColor
    let comment: NSColor
    let number: NSColor
    let type: NSColor

    static func `for`(_ theme: Theme) -> CodeColors {
        func hex(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        switch theme {
        case .dark:
            // VS Code's Dark+, as MarkView shows code.
            return CodeColors(keyword: hex(0xC586C0), string: hex(0xCE9178), comment: hex(0x6A9955), number: hex(0xB5CEA8), type: hex(0x4EC9B0))
        case .light:
            return CodeColors(keyword: hex(0xAD3DA4), string: hex(0xA6461D), comment: hex(0x707F8C), number: hex(0x272AD8), type: hex(0x0B6B8F))
        }
    }

    func color(_ kind: SyntaxHighlighter.Kind) -> NSColor {
        switch kind {
        case .keyword: return keyword
        case .string: return string
        case .comment: return comment
        case .number: return number
        case .type: return type
        }
    }
}

/// GitHub's five alert types.
enum CalloutKind: String, CaseIterable {
    case note, tip, important, warning, caution

    /// GitHub's five markers, and Obsidian's other kinds mapped onto
    /// the nearest colour (`[!info]` reads as a note, `[!bug]` as caution).
    init?(marker: String) {
        let name = marker.lowercased()
        if let kind = CalloutKind(rawValue: name) { self = kind; return }
        switch name {
        case "info", "todo", "abstract", "summary", "tldr", "quote", "cite": self = .note
        case "hint", "success", "check", "done": self = .tip
        case "example": self = .important
        case "question", "help", "faq", "attention": self = .warning
        case "failure", "fail", "missing", "danger", "error", "bug": self = .caution
        default: return nil
        }
    }

    var title: String { L(rawValue.prefix(1).uppercased() + rawValue.dropFirst()) }

    func color(for theme: Theme) -> NSColor {
        let dark = theme == .dark
        switch self {
        case .note: return dark ? NSColor(srgbRed: 0.35, green: 0.60, blue: 1.0, alpha: 1) : NSColor(srgbRed: 0.04, green: 0.41, blue: 0.85, alpha: 1)
        case .tip: return dark ? NSColor(srgbRed: 0.25, green: 0.73, blue: 0.31, alpha: 1) : NSColor(srgbRed: 0.10, green: 0.50, blue: 0.22, alpha: 1)
        case .important: return dark ? NSColor(srgbRed: 0.67, green: 0.50, blue: 1.0, alpha: 1) : NSColor(srgbRed: 0.51, green: 0.31, blue: 0.87, alpha: 1)
        case .warning: return dark ? NSColor(srgbRed: 0.82, green: 0.60, blue: 0.13, alpha: 1) : NSColor(srgbRed: 0.60, green: 0.40, blue: 0.0, alpha: 1)
        case .caution: return dark ? NSColor(srgbRed: 0.97, green: 0.32, blue: 0.29, alpha: 1) : NSColor(srgbRed: 0.81, green: 0.13, blue: 0.18, alpha: 1)
        }
    }

    /// CSS hex for the preview, matching `color(for:)`.
    func css(for theme: Theme) -> String {
        cssHex(color(for: theme))
    }
}

extension Theme {
    /// AppKit's appearance for this theme. A fixed appearance overrides the
    /// system's, so Increase Contrast has to be asked for by name.
    var appearanceName: NSAppearance.Name {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        switch self {
        case .dark: return contrast ? .accessibilityHighContrastDarkAqua : .darkAqua
        case .light: return contrast ? .accessibilityHighContrastAqua : .aqua
        }
    }
}
