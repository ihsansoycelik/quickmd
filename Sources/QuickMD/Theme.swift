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
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
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
            return CodeColors(keyword: hex(0xFF7AB2), string: hex(0xF2D489), comment: hex(0x7F8C98), number: hex(0xD9C97C), type: hex(0x6BDFFF))
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

    init?(marker: String) {
        self.init(rawValue: marker.lowercased())
    }

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

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
        let c = color(for: theme).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Looq's Markdown preview colours: its default "vscode-dark" and
/// "vscode-light" themes, read from LooqPreviewKit.
struct LooqColors {
    let bg: NSColor
    let text: NSColor
    let heading: NSColor
    let secondary: NSColor
    let link: NSColor
    let codeBg: NSColor
    /// The same six as CSS hex, for the preview.
    let css: [String: String]

    static func `for`(_ theme: Theme) -> LooqColors {
        let hexes: [String: String] = theme == .dark
            ? ["bg": "#1e1e1e", "text": "#d4d4d4", "heading": "#e0e0e0", "secondary": "#808080", "link": "#4fc1ff", "codeBg": "#2d2d2d"]
            : ["bg": "#ffffff", "text": "#1f1f1f", "heading": "#1f1f1f", "secondary": "#6a737d", "link": "#006ab1", "codeBg": "#f3f3f3"]
        func color(_ key: String) -> NSColor {
            let v = UInt32(hexes[key]!.dropFirst(), radix: 16)!
            return NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return LooqColors(
            bg: color("bg"), text: color("text"), heading: color("heading"),
            secondary: color("secondary"), link: color("link"), codeBg: color("codeBg"), css: hexes
        )
    }

    /// Quote text: CSS color-mix(text 65%, secondary).
    var quote: NSColor { text.blended(withFraction: 0.35, of: secondary) ?? text }
}

struct Palette {
    /// Body text.
    let text: NSColor
    /// Bold text and headings: a step darker (or lighter) than the body.
    let strong: NSColor
    let cursor: NSColor
    let selection: NSColor
    /// Used for the horizontal-rule glyph run so it reads as a quieter
    /// hint than body text instead of competing with words.
    let divider: NSColor
    /// Markdown's own marks — `#`, `**`, backticks, fence lines — and
    /// link underlines. Kept on screen, since the file is plain text,
    /// but quiet enough that the words read first.
    let syntax: NSColor
    /// Background drawn behind the current Find match (temporary layout
    /// attribute). Warm amber so it reads in both themes.
    let findHighlight: NSColor

    /// Ground behind `inline code` and fenced blocks: a low-alpha
    /// overlay, so it reads on either window background.
    static func codeBackground(for theme: Theme, template: Template = .classic) -> NSColor {
        if template == .looq { return LooqColors.for(theme).codeBg }
        return theme == .dark ? NSColor(white: 1.0, alpha: 0.07) : NSColor(white: 0.0, alpha: 0.045)
    }

    static func `for`(_ theme: Theme, template: Template = .classic) -> Palette {
        switch (template, theme) {
        case (.looq, _):
            let c = LooqColors.for(theme)
            return Palette(
                text: c.text, strong: c.heading, cursor: c.heading,
                selection: NSColor.controlAccentColor.withAlphaComponent(theme == .dark ? 0.32 : 0.22),
                divider: c.secondary.withAlphaComponent(0.35),
                syntax: c.secondary,
                findHighlight: theme == .dark
                    ? NSColor(red: 0.98, green: 0.78, blue: 0.28, alpha: 0.42)
                    : NSColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 0.55)
            )
        case (.invisible, .dark):
            // The site's dark card: #d6d6d6 prose, white headings.
            let text = NSColor(srgbRed: 0.84, green: 0.84, blue: 0.84, alpha: 1)
            return Palette(
                text: text, strong: .white, cursor: .white,
                selection: NSColor.controlAccentColor.withAlphaComponent(0.32),
                divider: NSColor(white: 1, alpha: 0.14),
                syntax: NSColor(white: 1, alpha: 0.32),
                findHighlight: NSColor(red: 0.98, green: 0.78, blue: 0.28, alpha: 0.42)
            )
        case (.invisible, .light):
            // #525252 prose, black headings.
            let text = NSColor(srgbRed: 0.32, green: 0.32, blue: 0.32, alpha: 1)
            return Palette(
                text: text, strong: .black, cursor: .black,
                selection: NSColor.controlAccentColor.withAlphaComponent(0.22),
                divider: NSColor(white: 0, alpha: 0.12),
                syntax: NSColor(white: 0, alpha: 0.30),
                findHighlight: NSColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 0.55)
            )
        case (.classic, .dark):
            // Warm off-white on dark glass — easy on eyes for long sessions.
            let text = NSColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1.0)
            return Palette(
                text: text, strong: text,
                cursor: NSColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1.0),
                selection: NSColor.controlAccentColor.withAlphaComponent(0.32),
                divider: text.withAlphaComponent(0.35),
                syntax: text.withAlphaComponent(0.38),
                findHighlight: NSColor(red: 0.98, green: 0.78, blue: 0.28, alpha: 0.42)
            )
        case (.classic, .light):
            // Clean white slate with near-black ink. Selection follows the
            // system accent colour in both themes.
            let text = NSColor(white: 0.10, alpha: 1.0)
            return Palette(
                text: text, strong: text,
                cursor: NSColor(white: 0.0, alpha: 1.0),
                selection: NSColor.controlAccentColor.withAlphaComponent(0.22),
                divider: text.withAlphaComponent(0.30),
                syntax: text.withAlphaComponent(0.36),
                findHighlight: NSColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 0.55)
            )
        }
    }
}
/// How much of the desktop shows through the panel. This is the useful
/// half of "add a settings screen": three steps on a menu rather than a
/// preferences window and a colour picker.
enum Transparency: String, CaseIterable {
    case off
    case subtle
    case strong

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .subtle: return "Subtle"
        case .strong: return "Strong"
        }
    }

    /// Opacity of the tint painted over the blur — 1.0 is a solid
    /// panel, lower lets the desktop through.
    ///
    /// The steps have to be far enough apart to actually see.
    func tintAlpha(for theme: Theme) -> CGFloat {
        switch (theme, self) {
        case (_, .off):           return 1.0
        case (.dark, .subtle):    return 0.50
        case (.dark, .strong):    return 0.22
        case (.light, .subtle):   return 0.72
        case (.light, .strong):   return 0.40
        }
    }

    /// Light text needs a darker ground and vice versa, so the tint is
    /// black in the dark theme and white in the light one. At `.off`
    /// the dark tint lifts off pure black — a solid panel, not a void.
    func tintColor(for theme: Theme, template: Template = .classic) -> NSColor {
        switch theme {
        case _ where template == .looq:
            return LooqColors.for(theme).bg.withAlphaComponent(tintAlpha(for: theme))
        case .dark:
            // Invisible Details sits on the site's #26292b card.
            if template == .invisible {
                return NSColor(srgbRed: 0.149, green: 0.161, blue: 0.169, alpha: tintAlpha(for: theme))
            }
            return self == .off
                ? NSColor(white: 0.10, alpha: 1.0)
                : NSColor(white: 0.0, alpha: tintAlpha(for: theme))
        case .light:
            return NSColor(white: 1.0, alpha: tintAlpha(for: theme))
        }
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

struct Chrome {
    let material: NSVisualEffectView.Material
    let tintColor: NSColor
    let appearance: NSAppearance.Name
    /// False for `.off`: no blur behind an opaque panel is wasted work.
    let usesVisualEffect: Bool

    static func `for`(_ theme: Theme, transparency: Transparency, template: Template = .classic) -> Chrome {
        // One genuinely translucent material for both themes.
        // `.windowBackground` was the wrong choice for the light theme:
        // it's near-opaque by design, so no tint above it read as glass.
        Chrome(
            material: .fullScreenUI,
            tintColor: transparency.tintColor(for: theme, template: template),
            appearance: theme.appearanceName,
            usesVisualEffect: transparency != .off
        )
    }
}
