import AppKit
import CoreText

/// Files shipped next to the binary: fonts, KaTeX, Mermaid. In the
/// app they sit in Contents/Resources; under `swift run` they're read
/// from the repo's Resources folder.
enum AppResources {
    static func url(_ path: String) -> URL? {
        if let base = Bundle.main.resourceURL {
            let url = base.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        #if DEBUG
        // `swift run` from the repo: no bundle, read the source tree.
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources").appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
        #else
        return nil
        #endif
    }

    static let fontFiles = ["Inter.ttf", "Inter-Italic.ttf", "QuickMDMyeongjo-Regular.ttf", "QuickMDMyeongjo-Bold.ttf"]

    /// Makes the bundled faces available to this process only.
    static func registerFonts() {
        for name in fontFiles {
            guard let url = url("Fonts/\(name)") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// The page's look: type, colours and spacing together. "Invisible
/// Details" follows the lesson pages of invisibledetails.com — Inter
/// body in grey at 160% leading, Myeongjo serif headings in black,
/// 16px between paragraphs, a ~32em measure.
/// "Looq" copies Looq's Markdown preview defaults: San Francisco at
/// 14px, 1.4 leading, 8px between paragraphs, VS Code colours.
enum Template: String, CaseIterable {
    case looq
    case invisible
    case classic

    var displayName: String {
        switch self {
        case .looq: return "Looq"
        case .invisible: return "Invisible Details"
        case .classic: return "Classic"
        }
    }

    var defaultFace: FontFace {
        switch self {
        case .looq: return .sanFrancisco
        case .invisible: return .inter
        case .classic: return .charter
        }
    }

    /// The site sets 15px and scales its prose to 17px on a desktop.
    var defaultSize: CGFloat {
        switch self {
        case .looq: return 16
        case .invisible: return 17
        case .classic: return 20
        }
    }

    /// Line length in ems of body text before extra width turns into
    /// margin. 0: no cap, lines fill the window (Looq).
    var measure: CGFloat {
        switch self {
        case .looq: return 0
        case .invisible: return 30
        case .classic: return 34
        }
    }
}

/// Fonts of the Invisible Details template, built at a body size.
/// Everything is scaled from the site's 15px design.
struct InvisibleType {
    let size: CGFloat
    var scale: CGFloat { size / 15 }

    static func inter(_ face: String, _ size: CGFloat) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [.family: "Inter", .face: face])
        if let font = NSFont(descriptor: descriptor, size: size), font.familyName == "Inter" { return font }
        return .systemFont(ofSize: size, weight: face.contains("Medium") ? .medium : .regular)
    }

    /// QuickMD Myeongjo (a renamed Latin subset of Nanum Myeongjo) has
    /// Latin only: Turkish and other accented letters fall back to
    /// Georgia, as they do on the site.
    static func nanum(bold: Bool, _ size: CGFloat) -> NSFont {
        let name = bold ? "QuickMDMyeongjo-Bold" : "QuickMDMyeongjo-Regular"
        let fallback = NSFontDescriptor(name: bold ? "Georgia-Bold" : "Georgia", size: size)
        guard let font = NSFont(name: name, size: size) else {
            return NSFont(descriptor: fallback, size: size) ?? .systemFont(ofSize: size)
        }
        let cascaded = font.fontDescriptor.addingAttributes([.cascadeList: [fallback]])
        return NSFont(descriptor: cascaded, size: size) ?? font
    }

    var body: NSFont { Self.inter("Regular", size) }
    var strong: NSFont { Self.inter("Medium", size) }
    var italic: NSFont { Self.inter("Italic", size) }
    var strongItalic: NSFont { Self.inter("Medium Italic", size) }

    func heading(_ level: Int) -> NSFont {
        switch level {
        case 1: return Self.nanum(bold: true, (24 * scale).rounded())
        case 2: return Self.nanum(bold: true, (20 * scale).rounded())
        case 3: return Self.nanum(bold: true, (17 * scale).rounded())
        default: return Self.nanum(bold: false, size)
        }
    }

    var quote: NSFont { Self.nanum(bold: false, (17 * scale).rounded()) }
}
