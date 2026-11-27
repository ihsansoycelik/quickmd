import AppKit
import NaturalLanguage

// Writing font, line width, page colour and book paragraphs: the parts
// of the one look a writer may choose. Read straight from UserDefaults
// (not through the main-actor `Settings`) so the styler, `Palette` and
// the export page can ask from anywhere. None of it touches the text.

private let lookDefaults = UserDefaults.standard

/// Settings › Writing font. Code spans and blocks stay monospaced in every family.
enum WritingFont: String, CaseIterable {
    /// SF Mono throughout (the original look).
    case mono
    /// SF Mono body with SF Pro headings.
    case duo
    /// SF Pro throughout.
    case sans
    /// New York throughout.
    case serif

    static var stored: WritingFont { WritingFont(rawValue: lookDefaults.string(forKey: "WritingFont") ?? "") ?? .mono }

    var displayName: String {
        switch self {
        case .mono: return L("Mono")
        case .duo: return L("Duo")
        case .sans: return L("Sans")
        case .serif: return L("Serif")
        }
    }

    /// The body text is fixed pitch (the column is measured in "0" widths).
    var isMonospacedBody: Bool { self == .mono || self == .duo }

    func body(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch self {
        case .mono, .duo: return .monospacedSystemFont(ofSize: size, weight: weight)
        case .sans: return .systemFont(ofSize: size, weight: weight)
        case .serif: return Self.serif(size: size, weight: weight)
        }
    }

    func heading(size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
        switch self {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: weight)
        case .duo, .sans: return .systemFont(ofSize: size, weight: weight)
        case .serif: return Self.serif(size: size, weight: weight)
        }
    }

    private static func serif(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }

    static let cssMono = "ui-monospace, \"SF Mono\", Menlo, monospace"
    static let cssSans = "-apple-system, system-ui, \"Helvetica Neue\", sans-serif"
    static let cssSerif = "ui-serif, \"New York\", Georgia, serif"

    var cssBody: String {
        switch self {
        case .mono, .duo: return Self.cssMono
        case .sans: return Self.cssSans
        case .serif: return Self.cssSerif
        }
    }

    var cssHeading: String {
        switch self {
        case .mono: return Self.cssMono
        case .duo, .sans: return Self.cssSans
        case .serif: return Self.cssSerif
        }
    }
}

/// Settings › Line width, in characters.
enum LineWidth: String, CaseIterable {
    case narrow, normal, wide

    static var stored: LineWidth { LineWidth(rawValue: lookDefaults.string(forKey: "LineWidth") ?? "") ?? .normal }

    var displayName: String {
        switch self {
        case .narrow: return L("Narrow")
        case .normal: return L("Normal")
        case .wide: return L("Wide")
        }
    }

    /// Characters per line. Proportional text reads a little denser,
    /// so it gets two more average characters (66 at Normal).
    func measure(proportional: Bool) -> CGFloat {
        let base: CGFloat
        switch self {
        case .narrow: base = 56
        case .normal: base = 64
        case .wide: base = 80
        }
        return proportional ? base + 2 : base
    }
}

/// Settings › Page, in light appearance.
enum LightPage: String, CaseIterable {
    case paper, white, grey

    static var stored: LightPage { LightPage(rawValue: lookDefaults.string(forKey: "LightPage") ?? "") ?? .paper }

    var displayName: String {
        switch self {
        case .paper: return L("Paper")
        case .white: return L("White")
        case .grey: return L("Grey")
        }
    }

    var background: NSColor {
        switch self {
        case .paper: return srgb(0xF8F7F4)
        case .white: return srgb(0xFFFFFF)
        case .grey: return srgb(0xEEEDEA)
        }
    }
}

/// Settings › Page, in dark appearance.
enum DarkPage: String, CaseIterable {
    case standard, black

    static var stored: DarkPage { DarkPage(rawValue: lookDefaults.string(forKey: "DarkPage") ?? "") ?? .standard }

    var displayName: String {
        switch self {
        case .standard: return L("Default")
        case .black: return L("Black")
        }
    }

    var background: NSColor {
        switch self {
        case .standard: return srgb(0x1A1918)
        case .black: return srgb(0x0B0B0A)
        }
    }
}

/// Settings › Focus: what Focus keeps bright.
enum FocusScope: String, CaseIterable {
    case paragraph, sentence

    var displayName: String {
        switch self {
        case .paragraph: return L("Paragraph")
        case .sentence: return L("Sentence")
        }
    }
}

/// The chosen look that changes text attributes: the styler's cache key.
struct TypographyLook: Equatable {
    var font: WritingFont
    var bookParagraphs: Bool

    static var current: TypographyLook {
        TypographyLook(font: .stored, bookParagraphs: lookDefaults.bool(forKey: "BookParagraphs"))
    }
}

enum Typography {
    /// WCAG contrast ratio between two colours.
    static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            let c = color.usingColorSpace(.sRGB) ?? .gray
            func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Average advance of running text in `font`, for measuring a column.
    static func averageAdvance(_ font: NSFont) -> CGFloat {
        if font.isFixedPitch {
            return ("0" as NSString).size(withAttributes: [.font: font]).width
        }
        let sample = "The quick brown fox jumps over the lazy dog, then reads a long sentence." as NSString
        return sample.size(withAttributes: [.font: font]).width / CGFloat(sample.length)
    }

    // MARK: Book paragraphs

    /// A line of plain prose: not blank, not a heading, list item, quote,
    /// table row, fence, rule, math, image, footnote or front matter, and
    /// not inside a code block. Text-only, so it can judge neighbours
    /// that this restyle pass doesn't cover.
    @MainActor static func isProseLine(_ ns: NSString, _ lineRange: NSRange, fences: [Int], frontMatterEnd: Int?) -> Bool {
        guard lineRange.length > 0, lineRange.location < ns.length else { return false }
        if let close = frontMatterEnd, lineRange.location <= close { return false }
        if MarkdownStyler.isInsideBlock(lineRange.location, fences: fences) { return false }
        let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = line.first else { return false }
        if "#>|`~$=-*+_<".contains(first) { return false }
        if line.hasPrefix("![") || line.hasPrefix("[^") { return false }
        if first.isNumber, line.firstMatch(of: /^\d{1,9}[.)](\s|$)/) != nil { return false }
        return true
    }

    /// Book paragraphs: a prose line right after a blank line that follows
    /// prose gets a first-line indent, and that blank line folds away.
    /// True when the line at `lineRange` is such a line.
    @MainActor static func bookRole(_ ns: NSString, lineRange: NSRange, fences: [Int], frontMatterEnd: Int?) -> Bool {
        guard isProseLine(ns, lineRange, fences: fences, frontMatterEnd: frontMatterEnd), lineRange.location > 0 else { return false }
        let blank = ns.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
        guard isBlankLine(ns, blank), blank.location > 0 else { return false }
        let before = ns.lineRange(for: NSRange(location: blank.location - 1, length: 0))
        return isProseLine(ns, before, fences: fences, frontMatterEnd: frontMatterEnd)
    }

    /// A blank line between two prose lines (folded in book paragraphs).
    @MainActor static func isFoldedBlank(_ ns: NSString, lineRange: NSRange, fences: [Int], frontMatterEnd: Int?) -> Bool {
        guard isBlankLine(ns, lineRange), lineRange.location > 0, NSMaxRange(lineRange) < ns.length else { return false }
        let next = ns.lineRange(for: NSRange(location: NSMaxRange(lineRange), length: 0))
        return bookRole(ns, lineRange: next, fences: fences, frontMatterEnd: frontMatterEnd)
    }

    static func isBlankLine(_ ns: NSString, _ lineRange: NSRange) -> Bool {
        ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One more line each way: a book indent depends on the line two above.
    static func widen(_ range: NSRange, in ns: NSString) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        if start > 0 { start = ns.lineRange(for: NSRange(location: start - 1, length: 0)).location }
        if end < ns.length { end = NSMaxRange(ns.lineRange(for: NSRange(location: end, length: 0))) }
        return NSRange(location: start, length: end - start)
    }

    // MARK: Sentence focus

    /// The sentence around `location` inside `block` (a paragraph).
    static func sentence(in ns: NSString, block: NSRange, at location: Int) -> NSRange {
        guard block.length > 0 else { return block }
        let text = ns.substring(with: block)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let offset = min(max(0, location - block.location), (text as NSString).length)
        var found: NSRange?
        var last: NSRange?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let r = NSRange(range, in: text)
            last = r
            // The caret right after a sentence's last character still belongs to it.
            if offset >= r.location, offset < NSMaxRange(r) || (offset == NSMaxRange(r) && offset == (text as NSString).length) {
                found = r
                return false
            }
            return true
        }
        guard let r = found ?? last else { return block }
        return NSRange(location: block.location + r.location, length: r.length)
    }

    // MARK: Smart quotes and dashes

    /// Smart quotes and dashes follow the setting, but never inside code:
    /// a fenced block, display math, or an open backtick span on the caret's line.
    @MainActor static func updateSubstitutions(_ textView: NSTextView) {
        let on = Settings.smartPunctuation && !caretIsInCode(textView)
        if textView.isAutomaticQuoteSubstitutionEnabled != on { textView.isAutomaticQuoteSubstitutionEnabled = on }
        if textView.isAutomaticDashSubstitutionEnabled != on { textView.isAutomaticDashSubstitutionEnabled = on }
    }

    @MainActor static func caretIsInCode(_ textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let ns = storage.string as NSString
        let caret = min(textView.selectedRange().location, ns.length)
        return isInCode(ns, storage: storage, at: caret)
    }

    static func isInCode(_ ns: NSString, storage: NSAttributedString?, at caret: Int) -> Bool {
        guard ns.length > 0 else { return false }
        let line = ns.lineRange(for: NSRange(location: min(caret, ns.length), length: 0))
        if let storage, line.location < ns.length {
            for key in [NSAttributedString.Key.qmCodeBlock, .qmMathBlock] where storage.attribute(key, at: line.location, effectiveRange: nil) != nil {
                return true
            }
        }
        let before = ns.substring(with: NSRange(location: line.location, length: max(0, caret - line.location)))
        if before.trimmingCharacters(in: .whitespaces).hasPrefix("```") { return true }
        return before.filter { $0 == "`" }.count % 2 == 1
    }
}
