import AppKit

/// Files shipped next to the binary: KaTeX and Mermaid for export and
/// print. In the app they sit in Contents/Resources; under `swift run`
/// they're read from the repo's Resources folder.
enum AppResources {
    static func url(_ path: String) -> URL? {
        if let base = Bundle.main.resourceURL {
            let url = base.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        #if DEBUG
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources").appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
        #else
        return nil
        #endif
    }
}

/// The one look of the app, after iA Writer: a monospaced face by
/// default, a ~64 character column centred in the window, generous
/// leading, a blue caret, markdown's marks in quiet grey. The writing
/// font, line width and page colour are the user's (`Typography`);
/// nothing goes in the margins.
enum Design {
    static let defaultSize: CGFloat = 16
    /// Characters per line before extra width becomes margin.
    static let measure: CGFloat = 64
    /// Line height as a multiple of the font size.
    static let leading: CGFloat = 1.6
    /// Code blocks and tables sit a touch smaller than prose.
    static let codeScale: CGFloat = 0.92
    /// Heading sizes relative to body, H1…H3; H4+ are body size.
    static let headingScale: [CGFloat] = [1.5, 1.25, 1.08]
    /// Air above a heading, in body sizes, H1…H3 (H4+ use the last).
    static let headingSpaceAbove: [CGFloat] = [1.4, 1.1, 0.75]

    static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Width of the text column in points at `size`, for the chosen
    /// writing font and line width (Settings › Appearance).
    static func columnWidth(size: CGFloat, font family: WritingFont = .stored, width: LineWidth = .stored) -> CGFloat {
        let body = family.body(size: size)
        let advance = Typography.averageAdvance(body)
        return (advance * width.measure(proportional: !family.isMonospacedBody)).rounded()
    }

    static let cssFamily = "ui-monospace, \"SF Mono\", Menlo, monospace"
}

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// CSS hex for an sRGB colour.
func cssHex(_ color: NSColor) -> String {
    let c = color.usingColorSpace(.sRGB) ?? .gray
    return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                  Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
}

/// Every colour the editor and the exported page use.
struct Palette {
    let background: NSColor
    let text: NSColor
    /// Headings and bold: a step stronger than the body.
    let strong: NSColor
    /// Markdown's own marks — `#`, `**`, backticks, fences, link URLs.
    let syntax: NSColor
    /// Rules, panel frames, table lines.
    let divider: NSColor
    /// Ground behind inline code, code blocks and tables.
    let codeBackground: NSColor
    let link: NSColor
    let cursor: NSColor
    let selection: NSColor
    /// Behind `==marked==` text.
    let highlight: NSColor
    /// Behind the current Find match.
    let findHighlight: NSColor

    static func `for`(_ theme: Theme, light page: LightPage = .stored, dark darkPage: DarkPage = .stored) -> Palette {
        let blue = srgb(0x1AA9FF)
        switch theme {
        case .light:
            return Palette(
                background: page.background, text: srgb(0x2A2926), strong: srgb(0x12110F),
                syntax: srgb(0xA9A7A1), divider: srgb(0xDEDCD6), codeBackground: srgb(0x3A3426, 0.055),
                link: page == .grey ? srgb(0x0864B0) : srgb(0x0A6FC2), cursor: blue, selection: srgb(0xB3DDFB),
                highlight: srgb(0xFFF1A8), findHighlight: srgb(0xFFD22E, 0.55)
            )
        case .dark:
            return Palette(
                background: darkPage.background, text: srgb(0xD3D0CA), strong: srgb(0xF4F2EE),
                syntax: srgb(0x65625D), divider: srgb(0x36342F), codeBackground: srgb(0xFFF6E6, 0.06),
                link: srgb(0x5CB8F5), cursor: blue, selection: srgb(0x1F4A6B),
                highlight: srgb(0x5A4B12), findHighlight: srgb(0xFAC747, 0.42)
            )
        }
    }
}
