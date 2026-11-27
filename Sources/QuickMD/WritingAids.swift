import AppKit
import NaturalLanguage

/// View › Show Writing Aids, after Lede: on-device hints drawn as dotted
/// underlines (layout-manager temporary attributes, never in the text or
/// the file). Long sentences, a word typed twice, fillers and hedges
/// (English and Turkish), -ly adverbs and possible passives (English).
/// Code, math, links, front matter and markdown's own marks are skipped.
enum WritingAids {
    enum Kind: String, CaseIterable {
        case longSentence, repeatedWord, filler, adverb, passive

        var displayName: String {
            switch self {
            case .longSentence: return L("Long sentences")
            case .repeatedWord: return L("Repeated words")
            case .filler: return L("Fillers and hedges")
            case .adverb: return L("Adverbs")
            case .passive: return L("Passive voice")
            }
        }

        var explanation: String {
            switch self {
            case .longSentence: return L("Over 20 words is tinted, over 30 stronger.")
            case .repeatedWord: return L("The same word twice in a row.")
            case .filler: return L("Words like “very”, “just”, “aslında”, “bence”.")
            case .adverb: return L("English words ending in -ly.")
            case .passive: return L("English “was written”, “is done” and the like.")
            }
        }
    }

    struct Finding: Equatable {
        var range: NSRange
        var kind: Kind
        /// A long sentence over 30 words.
        var strong = false
    }

    static let fillers: [String] = [
        // English
        "very", "really", "basically", "just", "actually", "perhaps", "literally", "quite", "simply",
        "somewhat", "maybe", "i think", "i guess", "kind of", "sort of", "in my opinion",
        // Turkish
        "çok", "gerçekten", "aslında", "sadece", "belki", "bence", "galiba", "yani", "açıkçası", "sanırım",
    ]

    private static let fillerPattern: NSRegularExpression = {
        let words = fillers.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
        return try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}'’])(?:" + words.joined(separator: "|") + ")(?![\\p{L}\\p{N}'’])",
                                        options: [.caseInsensitive])
    }()

    private static let irregularParticiples = [
        "been", "born", "brought", "built", "bought", "caught", "chosen", "done", "drawn", "driven", "eaten", "fallen",
        "felt", "found", "forgotten", "given", "gone", "grown", "heard", "held", "hidden", "kept", "known", "laid", "led",
        "left", "lost", "made", "meant", "met", "paid", "put", "read", "run", "said", "seen", "sent", "set", "shown",
        "shut", "sold", "spent", "spoken", "stolen", "struck", "taken", "taught", "thought", "thrown", "told", "understood",
        "won", "worn", "written", "begun", "broken", "frozen",
    ]

    private static let passivePattern = try! NSRegularExpression(
        pattern: "\\b(?:am|is|are|was|were|be|been|being|isn't|aren't|wasn't|weren't)\\s+(?:(?:not|never|also|often|always)\\s+)?"
            + "(?:[a-z]{2,}ed|" + irregularParticiples.joined(separator: "|") + ")\\b",
        options: [.caseInsensitive]
    )

    /// The findings in `text`, a paragraph or more of plain prose (marks
    /// and code already blanked to spaces, so ranges match the note).
    static func findings(in text: String, kinds: Set<Kind>) -> [Finding] {
        guard !kinds.isEmpty, !text.isEmpty else { return [] }
        var out: [Finding] = []
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        let english = isEnglish(text)

        if kinds.contains(.longSentence) {
            let sentences = NLTokenizer(unit: .sentence)
            sentences.string = text
            let words = NLTokenizer(unit: .word)
            words.string = text
            sentences.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                var count = 0
                words.enumerateTokens(in: range) { _, _ in count += 1; return true }
                if count > 20 {
                    var r = NSRange(range, in: text)
                    // Underline the words, not the trailing spaces.
                    while r.length > 0, let scalar = Unicode.Scalar(ns.character(at: NSMaxRange(r) - 1)),
                          CharacterSet.whitespacesAndNewlines.contains(scalar) { r.length -= 1 }
                    out.append(Finding(range: r, kind: .longSentence, strong: count > 30))
                }
                return true
            }
        }

        if kinds.contains(.repeatedWord) {
            let words = NLTokenizer(unit: .word)
            words.string = text
            var previous: (word: String, range: NSRange)?
            words.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let r = NSRange(range, in: text)
                let word = ns.substring(with: r).lowercased()
                if let previous, previous.word == word, word.first?.isLetter == true {
                    let gap = ns.substring(with: NSRange(location: NSMaxRange(previous.range), length: r.location - NSMaxRange(previous.range)))
                    if gap.allSatisfy({ $0 == " " || $0 == "\t" }) && !gap.isEmpty {
                        out.append(Finding(range: NSRange(location: previous.range.location, length: NSMaxRange(r) - previous.range.location),
                                           kind: .repeatedWord))
                    }
                }
                previous = (word, r)
                return true
            }
        }

        var fillerRanges: [NSRange] = []
        if kinds.contains(.filler) {
            fillerPattern.enumerateMatches(in: text, range: all) { match, _, _ in
                guard let r = match?.range else { return }
                fillerRanges.append(r)
                out.append(Finding(range: r, kind: .filler))
            }
        }

        if english, kinds.contains(.adverb) {
            let tagger = NLTagger(tagSchemes: [.lexicalClass])
            tagger.string = text
            tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                                 options: [.omitWhitespace, .omitPunctuation]) { tag, range in
                let word = text[range].lowercased()
                let r = NSRange(range, in: text)
                if tag == .adverb, word.count > 4, word.hasSuffix("ly"),
                   !fillerRanges.contains(where: { NSIntersectionRange($0, r).length > 0 }) {
                    out.append(Finding(range: r, kind: .adverb))
                }
                return true
            }
        }

        if english, kinds.contains(.passive) {
            passivePattern.enumerateMatches(in: text, range: all) { match, _, _ in
                if let r = match?.range { out.append(Finding(range: r, kind: .passive)) }
            }
        }
        return out
    }

    /// English adverbs and passives only when the text reads as English.
    static func isEnglish(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return true }
        return language == .english
    }

    /// `storage`'s text over `range` with everything aids must not judge
    /// (code, math, links, tables, front matter, markdown marks) blanked
    /// to spaces, keeping UTF-16 offsets.
    static func prose(_ storage: NSAttributedString, range: NSRange) -> String {
        let ns = storage.string as NSString
        let chars = NSMutableString(string: ns.substring(with: range))
        func blank(_ r: NSRange) {
            let local = NSIntersectionRange(r, range)
            guard local.length > 0 else { return }
            chars.replaceCharacters(in: NSRange(location: local.location - range.location, length: local.length),
                                    with: String(repeating: " ", count: local.length))
        }
        let skip: [NSAttributedString.Key] = [.qmCodeBlock, .qmMathBlock, .qmMathInline, .qmLink, .qmSyntax, .qmTable, .qmImage]
        let codeGrounds = [Palette.for(.light).codeBackground, Palette.for(.dark).codeBackground]
        storage.enumerateAttributes(in: range) { attributes, run, _ in
            if skip.contains(where: { attributes[$0] != nil }) { blank(run); return }
            // Inline code: the code ground behind it (a highlight has its own colour).
            if let ground = attributes[.backgroundColor] as? NSColor, codeGrounds.contains(ground) { blank(run) }
        }
        if let close = HorizontalRuleLayoutManager.frontMatterClose(in: ns) {
            blank(NSRange(location: 0, length: NSMaxRange(ns.lineRange(for: NSRange(location: close, length: 0)))))
        }
        return chars as String
    }
}

/// Paints Writing Aids over what's on screen, a moment after typing or
/// scrolling stops, and clears them when the aids are off.
@MainActor
final class WritingAidsPainter {
    private weak var textView: NSTextView?
    private var timer: Timer?
    private var painted = false
    private var observers: [Any] = []

    init(textView: NSTextView) {
        self.textView = textView
        let center = NotificationCenter.default
        let onChange: (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.schedule() } }
        observers = [
            center.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main, using: onChange),
            center.addObserver(forName: .editorSettingsChanged, object: nil, queue: .main, using: onChange),
        ]
        if let clip = textView.enclosingScrollView?.contentView {
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main, using: onChange))
        }
        schedule()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        timer?.invalidate()
    }

    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.paint() }
        }
    }

    private static let keys: [NSAttributedString.Key] = [.underlineStyle, .underlineColor]

    func paint() {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let all = NSRange(location: 0, length: ns.length)
        guard Settings.showsWritingAids, ns.length > 0, !textView.hasMarkedText() else {
            if painted { Self.keys.forEach { layoutManager.removeTemporaryAttribute($0, forCharacterRange: all) } }
            painted = false
            return
        }
        // What's on screen, widened to whole paragraphs.
        var visible = textView.visibleRect
        visible.origin.x -= textView.textContainerOrigin.x
        visible.origin.y -= textView.textContainerOrigin.y
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible.insetBy(dx: 0, dy: -200), in: container)
        let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let range = ns.paragraphRange(for: NSIntersectionRange(chars, all))
        guard range.length > 0 else { return }

        Self.keys.forEach { layoutManager.removeTemporaryAttribute($0, forCharacterRange: all) }
        painted = true
        let text = WritingAids.prose(storage, range: range)
        let found = WritingAids.findings(in: text, kinds: Settings.writingAids)
        let colors = Self.colors(dark: Settings.theme == .dark)
        let dotted = NSUnderlineStyle([.single, .patternDot]).rawValue
        // Long sentences first, so a word-level hint inside one shows on top.
        for finding in found.sorted(by: { ($0.kind == .longSentence ? 0 : 1) < ($1.kind == .longSentence ? 0 : 1) }) {
            let r = NSRange(location: finding.range.location + range.location, length: finding.range.length)
            guard NSMaxRange(r) <= ns.length else { continue }
            let color = finding.kind == .longSentence
                ? colors[.longSentence]!.withAlphaComponent(finding.strong ? 1 : 0.5)
                : colors[finding.kind]!
            layoutManager.addTemporaryAttributes([.underlineStyle: dotted, .underlineColor: color], forCharacterRange: r)
        }
    }

    private static func colors(dark: Bool) -> [WritingAids.Kind: NSColor] {
        [
            .longSentence: dark ? srgb(0xE0A030) : srgb(0xC07A00),
            .repeatedWord: dark ? srgb(0xF0605A) : srgb(0xC8302B),
            .filler: dark ? srgb(0x5CB8F5) : srgb(0x0A6FC2),
            .adverb: dark ? srgb(0xB08CF0) : srgb(0x7A4FD0),
            .passive: dark ? srgb(0x4CC38A) : srgb(0x1E8A55),
        ]
    }
}
