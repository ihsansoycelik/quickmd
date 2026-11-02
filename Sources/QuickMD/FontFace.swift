import AppKit

/// A font family for body text or headings. The curated list comes
/// first in menus; any installed family works too. Two ids are
/// special: "system" (San Francisco) and "mono" (SF Mono), which have
/// no public family name.
struct FontFace: Hashable {
    let rawValue: String

    /// "Nanum Myeongjo" is what older versions stored for the bundled serif.
    init(rawValue: String) { self.rawValue = rawValue == "Nanum Myeongjo" ? "QuickMD Myeongjo" : rawValue }

    static let charter = FontFace(rawValue: "charter")
    static let iowanOldStyle = FontFace(rawValue: "iowanOldStyle")
    static let sanFrancisco = FontFace(rawValue: "system")
    static let sfMono = FontFace(rawValue: "mono")
    static let inter = FontFace(rawValue: "Inter")
    static let nanumMyeongjo = FontFace(rawValue: "QuickMD Myeongjo")
    static let newYork = FontFace(rawValue: "New York")
    static let georgia = FontFace(rawValue: "Georgia")
    static let avenir = FontFace(rawValue: "Avenir Next")
    static let helvetica = FontFace(rawValue: "Helvetica Neue")
    static let menlo = FontFace(rawValue: "Menlo")

    /// Shown at the top of font menus. The rest of the installed
    /// families follow in a submenu.
    static let curated: [FontFace] = [
        .inter, .sanFrancisco, .avenir, .helvetica,
        .charter, .iowanOldStyle, .newYork, .georgia, .nanumMyeongjo,
        .sfMono, .menlo,
    ]

    var displayName: String {
        switch rawValue {
        case "charter": return "Charter"
        case "iowanOldStyle": return "Iowan Old Style"
        case "system": return "San Francisco"
        case "mono": return "SF Mono"
        case "QuickMD Myeongjo": return "Myeongjo"
        default: return rawValue
        }
    }

    /// Family name passed to NSFont lookups.
    var familyName: String { rawValue == "QuickMD Myeongjo" ? rawValue : displayName }

    /// CSS font-family for the preview and exported HTML.
    var cssFamily: String {
        switch rawValue {
        case "system": return "-apple-system, system-ui, sans-serif"
        case "mono": return "ui-monospace, Menlo, monospace"
        case "New York": return "ui-serif, \"New York\", Georgia, serif"
        // The bundled subset in the preview; upstream Nanum from Google Fonts in exports.
        case "QuickMD Myeongjo": return "\"QuickMD Myeongjo\", \"Nanum Myeongjo\", Georgia, serif"
        default: return "\"\(familyName)\""
        }
    }

    var isMonospaced: Bool { rawValue == "mono" || rawValue == "Menlo" }

    /// The face at `size`, or nil when it isn't installed.
    func font(size: CGFloat) -> NSFont? {
        switch rawValue {
        case "system": return NSFont.systemFont(ofSize: size)
        case "mono": return NSFont.monospacedSystemFont(ofSize: size * 0.92, weight: .regular)
        case "QuickMD Myeongjo":
            return InvisibleType.nanum(bold: false, size)
        case "New York":
            let base = NSFont.systemFont(ofSize: size).fontDescriptor
            if let serif = base.withDesign(.serif) { return NSFont(descriptor: serif, size: size) }
            return nil
        default:
            if let font = NSFont(name: familyName, size: size) { return font }
            // Families whose regular face isn't named after the family.
            return NSFontManager.shared.font(withFamily: familyName, traits: [], weight: 5, size: size)
        }
    }

    /// The face at `size`, falling back to a serif that is always there.
    func resolvedFont(size: CGFloat) -> NSFont {
        if let font = font(size: size) { return font }
        for fallback in ["Charter", "Iowan Old Style"] {
            if let font = NSFont(name: fallback, size: size) { return font }
        }
        let base = NSFont.systemFont(ofSize: size).fontDescriptor
        return NSFont(descriptor: base.withDesign(.serif) ?? base, size: size) ?? .systemFont(ofSize: size)
    }

    /// The face in bold, or the closest the family has.
    func boldFont(size: CGFloat) -> NSFont {
        let regular = resolvedFont(size: size)
        if rawValue == "QuickMD Myeongjo" {
            return InvisibleType.nanum(bold: true, size)
        }
        let descriptor = regular.fontDescriptor.withSymbolicTraits(regular.fontDescriptor.symbolicTraits.union(.bold))
        return NSFont(descriptor: descriptor, size: size) ?? regular
    }

    /// Installed families not in the curated list, for the "More Fonts" submenu.
    static var otherInstalled: [FontFace] {
        let curatedNames = Set(curated.map(\.familyName))
        return NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") && !curatedNames.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { FontFace(rawValue: $0) }
    }
}
