import AppKit
import os

extension NSAttributedString.Key {
    /// Inline `$…$` math, literal like code.
    static let qmMathInline = NSAttributedString.Key("qmMathInline")
    /// The URL a run of text points at. Deliberately not `.link`:
    /// NSTextView follows `.link` on a plain click, which would make the
    /// text of a URL impossible to click into and edit. ⌘-click opens it.
    static let qmLink = NSAttributedString.Key("qmLink")
    /// A markdown token (`##`, `**`, a backtick…). Reading mode hides
    /// these characters; writing mode shows them dimmed.
    static let qmSyntax = NSAttributedString.Key("qmSyntax")
    /// A task's `- `: drawn on the caret line, zero width elsewhere.
    /// An image-only line; the value is the image's target as written.
    static let qmImage = NSAttributedString.Key("qmImage")
    static let qmTaskBullet = NSAttributedString.Key("qmTaskBullet")
    /// A dimmed marker that reading mode still shows (a list bullet).
    static let qmKeepSyntax = NSAttributedString.Key("qmKeepSyntax")
}

/// The styling pass behind the editor: headings, emphasis, code, rules,
/// ticked items and links, all as attributes over plain markdown.
///
/// Everything here is line-local except fenced code blocks, whose
/// extent depends on every fence above a line. That's what makes
/// restyling only the edited paragraph safe: the fences are re-listed
/// on each pass (a substring search, well under a millisecond on a
/// large note), and if an edit changed which lines are inside a block
/// the whole document is restyled instead.
@MainActor
enum MarkdownStyler {
    private static let signposter = OSSignposter(subsystem: "com.ursula.quickmd", category: "styling")

    /// The last Style built. Building one means resolving fonts (CoreText
    /// lookups) and paragraph styles, which every restyle would otherwise
    /// repeat; the inputs are a handful of settings, so a hit is the
    /// common case. The first build of a launch stays slow — that's the
    /// font system warming up, not the cache.
    private static var cachedStyle: (key: StyleKey, style: Style)?

    private struct StyleKey: Equatable {
        let size: CGFloat, theme: Theme
    }

    private static func style(size: CGFloat, theme: Theme) -> Style {
        let key = StyleKey(size: size, theme: theme)
        if let cachedStyle, cachedStyle.key == key { return cachedStyle.style }
        let style = Style(size: size, theme: theme)
        cachedStyle = (key, style)
        return style
    }

    // Spans never cross a line break of any kind: a paragraph restyle
    // only sees whole paragraphs, and NSString ends those at CR and
    // U+2029 as well as LF. Emphasis must touch a word at both ends —
    // markdown's own rule — so a `* ` bullet or `a * b` isn't a marker.
    private static let boldPattern = try! NSRegularExpression(
        pattern: #"\*\*([^\s*](?:[^*\n\r\u2029]*[^\s*])?)\*\*"#
    )
    private static let italicPattern = try! NSRegularExpression(
        pattern: #"\*([^\s*](?:[^*\n\r\u2029]*[^\s*])?)\*"#
    )
    private static let codePattern = try! NSRegularExpression(pattern: #"`([^`\n\r\u2029]+)`"#)
    private static let quotePattern = try! NSRegularExpression(pattern: #"^(>+ ?)"#)
    private static let listMarkerPattern = try! NSRegularExpression(pattern: #"^[ \t]*([-*+]|\d+[.)])[ \t]+"#)
    /// `[text](url)` and `![alt](url)`. The brackets and the URL dim; the
    /// text is the link.
    private static let mdLinkPattern = try! NSRegularExpression(
        pattern: #"!?\[([^\]\n\r\u2029]+)\]\(([^)\s]+)\)"#
    )
    private static let strikePattern = try! NSRegularExpression(
        pattern: #"~~([^\s~](?:[^~\n\r\u2029]*[^\s~])?)~~"#
    )
    /// `==highlight==`: what a writer (often an agent) wants read first.
    private static let markPattern = try! NSRegularExpression(
        pattern: #"==([^\s=](?:[^=\n\r\u2029]*[^\s=])?)=="#
    )
    private static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,6}\s+)\S"#)
    /// http(s) URLs, not ending on sentence punctuation. Parentheses
    /// count only in balanced pairs, so `(see https://x.io)` stops at
    /// the `)` while `…/wiki/Foo_(bar)` keeps it. A pattern rather than
    /// NSDataDetector: the detector's answer for a line depends on the
    /// text around it, which a paragraph restyle can't reproduce.
    /// `$…$`: no space just inside either dollar, and not `$5 and $10`.
    private static let inlineMathPattern = try! NSRegularExpression(
        pattern: #"(?<![\\$\w])\$([^\s$](?:[^$\n\r\u2029]*?[^\s$\\])?)\$(?![\d$])"#
    )
    private static let displayMathLinePattern = try! NSRegularExpression(pattern: #"^\s*\$\$.+\$\$\s*$"#)
    private static let calloutPattern = try! NSRegularExpression(pattern: #"^\s*>\s*\[!([A-Za-z]+)\]"#)
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"\bhttps?://(?:[^\s<>"'`()\[\]]|\([^\s<>"'`()]*\))*(?:[^\s<>"'`.,;:!?()\[\]*]|\([^\s<>"'`()]*\))"#
    )

    static func bodyFont(size: CGFloat) -> NSFont { Design.font(size: size) }

    /// Extra advance after a `-` bullet, in characters.
    static let bulletKern: CGFloat = 0.5
    /// Advance taken from each of a task box's three characters.
    static let boxKern: CGFloat = -0.5

    static func bodyParagraph(font: NSFont) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = multiple(for: font, leading: Design.leading)
        return paragraph
    }

    private static let measuring = NSLayoutManager()

    /// The lineHeightMultiple that gives `font` a line `leading` × its size.
    static func multiple(for font: NSFont, leading: CGFloat) -> CGFloat {
        let natural = measuring.defaultLineHeight(for: font)
        guard natural > 0 else { return 1 }
        return leading * font.pointSize / natural
    }

    /// Restyle `storage`. With `edited`, only the paragraphs it touches
    /// are restyled, unless the edit moved a code-block boundary. With
    /// `chunk`, exactly that range is restyled (a progressive chunk; the
    /// caller keeps its boundaries on paragraph and blank-line edges).
    /// `fenceIndex`, when given, keeps fence line starts across calls so
    /// an edit doesn't rescan a large note; it resets on a full restyle.
    static func restyle(
        _ storage: NSTextStorage,
        size: CGFloat,
        theme: Theme,
        edited: NSRange? = nil,
        chunk: NSRange? = nil,
        fenceIndex: FenceIndex? = nil
    ) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        let intervalName: StaticString = chunk != nil ? "restyle chunk" : (edited == nil ? "restyle full" : "restyle paragraph")
        let interval = signposter.beginInterval(intervalName)
        defer { signposter.endInterval(intervalName, interval) }
        let (fences, mathFences): ([Int], [Int])
        if let fenceIndex {
            if let edited {
                (fences, mathFences) = fenceIndex.update(ns: ns, edited: edited)
            } else {
                (fences, mathFences) = fenceIndex.reset(ns: ns)
            }
        } else {
            (fences, mathFences) = blockFenceLineStarts(in: ns)
        }
        var range = NSRange(location: 0, length: ns.length)
        if let chunk {
            range = chunk
        } else if let edited {
            let start = min(max(0, edited.location), ns.length)
            // One character past the edit: an edit ending in a newline
            // hands the next line a new start, and line-level styles
            // (heading, task, rule) depend on where a line starts.
            let end = min(max(start, NSMaxRange(edited)) + 1, ns.length)
            var dirty = ns.paragraphRange(for: NSRange(location: start, length: end - start))
            // Quotes and tables style each line by its neighbours (a
            // callout's first line, a table's delimiter row), and blank
            // lines and headings by the lines either side.
            dirty = expandToBlocks(dirty, in: ns)
            if blocksUnchanged(after: dirty, in: storage, fences: fences, mathFences: mathFences) {
                range = dirty
            }
        }
        guard range.length > 0 else { return }

        let style = Self.style(size: size, theme: theme)
        storage.beginEditing()
        defer { storage.endEditing() }
        // Replace, not add: anything a pass applied last time has to go,
        // or it outlives the text that justified it — a reopened
        // checkbox would stay struck through, a deleted fence would keep
        // its panel. The editor never restyles mid-composition, so
        // there's no input-method underline here to wipe.
        storage.setAttributes([
            .font: style.base,
            .foregroundColor: style.palette.text,
            .paragraphStyle: style.body,
        ], range: range)
        // One String for the regex passes. The storage's backing string
        // is mutable, so every `as String` is a full copy — done per
        // heading, that made a large note quadratic.
        let text = ns as String
        styleLines(in: range, storage: storage, ns: ns, text: text, fences: fences, mathFences: mathFences, style: style)
        styleInline(in: range, storage: storage, ns: ns, text: text, style: style)
        markSyntax(in: range, storage: storage, style: style)
    }

    /// Tags every dimmed token run so reading mode can hide it. 
    private static func markSyntax(in range: NSRange, storage: NSTextStorage, style: Style) {
        storage.enumerateAttribute(.foregroundColor, in: range) { value, run, _ in
            guard let color = value as? NSColor, color == style.syntax,
                  storage.attribute(.qmKeepSyntax, at: run.location, effectiveRange: nil) == nil else { return }
            storage.addAttribute(.qmSyntax, value: true, range: run)
        }
    }

    /// Grows `dirty` over whole quote and table blocks touching it, and
    /// one line either side.
    private static func expandToBlocks(_ dirty: NSRange, in ns: NSString) -> NSRange {
        func isBlockLine(_ r: NSRange) -> Bool {
            var i = r.location
            while i < NSMaxRange(r), ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
            guard i < NSMaxRange(r) else { return false }
            let c = ns.character(at: i)
            return c == 0x3E || c == 0x7C  // > |
        }
        var start = dirty.location
        var end = NSMaxRange(dirty)
        // One neighbour each way, then any block lines beyond.
        if start > 0 { start = ns.lineRange(for: NSRange(location: start - 1, length: 0)).location }
        if end < ns.length { end = NSMaxRange(ns.lineRange(for: NSRange(location: end, length: 0))) }
        while start > 0 {
            let previous = ns.lineRange(for: NSRange(location: start - 1, length: 0))
            guard isBlockLine(previous) else { break }
            start = previous.location
        }
        while end < ns.length {
            let next = ns.lineRange(for: NSRange(location: end, length: 0))
            guard isBlockLine(next) else { break }
            end = NSMaxRange(next)
        }
        return NSRange(location: start, length: end - start)
    }

    // MARK: Lines

    private static func contentRange(_ lineRange: NSRange, _ ns: NSString) -> NSRange {
        var content = lineRange
        while content.length > 0, isBreak(ns.character(at: NSMaxRange(content) - 1)) {
            content.length -= 1
        }
        return content
    }

    private static func isBlank(_ ns: NSString, lineAt location: Int) -> Bool {
        guard location >= 0, location < ns.length else { return true }
        let line = contentRange(ns.lineRange(for: NSRange(location: location, length: 0)), ns)
        for i in 0..<line.length where !(ns.character(at: line.location + i) == 0x20 || ns.character(at: line.location + i) == 0x09) {
            return false
        }
        return true
    }

    private static func styleLines(
        in range: NSRange, storage: NSTextStorage, ns: NSString, text: String,
        fences: [Int], mathFences: [Int], style: Style
    ) {
        var lineStart = range.location
        let end = NSMaxRange(range)
        // A quote block's callout kind, carried down its lines: looking
        // it up per line walks back to the block's start each time,
        // which made a long quote quadratic.
        var quoteKind: (end: Int, kind: CalloutKind?)?
        // Front matter reads as quiet metadata: keys dimmed, no headings or lists.
        let frontMatterEnd = HorizontalRuleLayoutManager.frontMatterClose(in: ns)
        while lineStart < end {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(lineRange)
            let content = contentRange(lineRange, ns)
            let previousBlank = lineRange.location == 0 || isBlank(ns, lineAt: lineRange.location - 1)
            let nextBlank = NSMaxRange(lineRange) >= ns.length || isBlank(ns, lineAt: NSMaxRange(lineRange))

            let isFence = contains(fences, lineRange.location)
            if isFence || isInsideBlock(lineRange.location, fences: fences) {
                // The ground is drawn by HorizontalRuleLayoutManager from
                // .qmCodeBlock, full width; an attribute background
                // would stop at each line's last glyph.
                storage.addAttributes([
                    .font: style.mono, .qmCodeBlock: true, .paragraphStyle: style.codeParagraph,
                ], range: lineRange)
                if isFence {
                    if content.length > 0 { storage.addAttribute(.foregroundColor, value: style.syntax, range: content) }
                } else if content.length > 0 {
                    let opener = fences[countBelow(fences, lineRange.location) - 1]
                    let language = fenceLanguage(ns, at: opener)
                    let line = ns.substring(with: content) as NSString
                    for token in SyntaxHighlighter.tokens(in: line, language: language) {
                        storage.addAttribute(
                            .foregroundColor, value: style.code.color(token.kind),
                            range: NSRange(location: content.location + token.range.location, length: token.range.length)
                        )
                    }
                }
                continue
            }

            if let close = frontMatterEnd, lineRange.location > 0, lineRange.location < close {
                if content.length > 0 {
                    let line = ns.substring(with: content) as NSString
                    let colon = line.range(of: ":")
                    let keyLength = colon.location == NSNotFound ? 0 : colon.location + 1
                    // Dimmed but kept: a value without its key means nothing.
                    storage.addAttributes([.foregroundColor: style.syntax, .qmKeepSyntax: true],
                                          range: NSRange(location: content.location, length: keyLength))
                }
                continue
            }

            let isMathFence = contains(mathFences, lineRange.location)
            if isMathFence || countBelow(mathFences, lineRange.location) % 2 == 1 {
                storage.addAttributes([
                    .font: style.mono, .qmMathBlock: true, .paragraphStyle: style.mathParagraph,
                    .foregroundColor: isMathFence ? style.syntax : style.palette.strong,
                ], range: lineRange)
                continue
            }

            guard content.length > 0 else { continue }

            if HorizontalRuleLayoutManager.setextLevel(underline: lineRange, in: ns) != nil {
                storage.addAttribute(.foregroundColor, value: style.syntax, range: content)
                continue
            }
            if NSMaxRange(lineRange) < ns.length,
               let level = HorizontalRuleLayoutManager.setextLevel(
                   underline: ns.lineRange(for: NSRange(location: NSMaxRange(lineRange), length: 0)), in: ns
               ) {
                storage.addAttributes([
                    .font: style.heading(level: level),
                    .foregroundColor: style.headingColor(level: level),
                    .paragraphStyle: style.headingParagraph(
                        level: level, first: lineRange.location == 0, previousBlank: previousBlank, nextBlank: false
                    ),
                ], range: content)
                continue
            }

            if HorizontalRuleLayoutManager.isHorizontalRuleLine(lineRange: lineRange, in: ns) {
                // The rule itself is drawn by the layout manager.
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: content)
                continue
            }

            let first = ns.character(at: content.location)
            if first == 0x23,  // #
               let match = headingPattern.firstMatch(in: text, range: content) {
                let marker = match.range(at: 1)
                var hashes = marker
                while hashes.length > 0, ns.character(at: NSMaxRange(hashes) - 1) != 0x23 { hashes.length -= 1 }
                storage.addAttributes([
                    .font: style.heading(level: hashes.length),
                    .foregroundColor: style.headingColor(level: hashes.length),
                    .paragraphStyle: style.headingParagraph(
                        level: hashes.length, first: lineRange.location == 0,
                        previousBlank: previousBlank, nextBlank: nextBlank
                    ),
                ], range: content)
                // The space after the hashes too, so reading mode hides it
                // and the heading lines up with the text below.
                storage.addAttribute(.foregroundColor, value: style.syntax, range: marker)
                continue
            }

            if mayBeDisplayMath(ns, content), displayMathLinePattern.firstMatch(in: text, range: content) != nil {
                storage.addAttributes([
                    .font: style.mono, .foregroundColor: style.palette.strong,
                    .paragraphStyle: style.centered, .qmMathInline: true,
                ], range: content)
                let line = ns.substring(with: content) as NSString
                let open = line.range(of: "$$"), close = line.range(of: "$$", options: .backwards)
                storage.addAttribute(.foregroundColor, value: style.syntax, range: NSRange(location: content.location + open.location, length: 2))
                storage.addAttribute(.foregroundColor, value: style.syntax, range: NSRange(location: content.location + close.location, length: 2))
                continue
            }

            let line = ns.substring(with: content)
            // A line that is only an image: reading mode draws the picture.
            if first == 0x21 || first == 0x20,  // ! (maybe indented)
               let image = imageLinePattern.firstMatch(in: text, range: content) {
                storage.addAttribute(.qmImage, value: ns.substring(with: image.range(at: 1)), range: lineRange)
            }

            if TableEditing.isRow(line) {
                styleTableRow(content, lineRange: lineRange, storage: storage, ns: ns, style: style)
                continue
            }

            if first == 0x3E || first == 0x20,  // > (maybe indented)
               let match = quotePattern.firstMatch(in: text, range: NSRange(location: content.location, length: content.length)) ?? quoteAfterIndent(ns, content) {
                let kind = quoteKind?.end == lineRange.location ? quoteKind?.kind : calloutKind(for: lineRange, in: ns, text: text)
                quoteKind = (NSMaxRange(lineRange), kind)
                if let kind {
                    styleCalloutLine(content, lineRange: lineRange, marker: match.range(at: 1), kind: kind, storage: storage, ns: ns, text: text, style: style)
                } else {
                    storage.addAttributes([
                        .foregroundColor: style.quote,
                        .font: style.quoteFont,
                        .paragraphStyle: style.quoteParagraph,
                        .qmQuote: true,
                    ], range: content)
                    storage.addAttribute(.foregroundColor, value: style.syntax, range: match.range(at: 1))
                }
                continue
            }

            if mayBeListMarker(ns, content),
               let marker = listMarkerPattern.firstMatch(in: text, range: content) {
                let bullet = marker.range(at: 1)
                // A task's box stands in for its marker: the bullet (or
                // the ordered number) hides in reading mode.
                let isTask = Checkbox.boxRange(in: line) != nil
                storage.addAttributes([.foregroundColor: style.syntax, .qmKeepSyntax: true], range: bullet)
                let advance = (" " as NSString).size(withAttributes: [.font: style.base]).width
                let isBullet = bullet.length == 1 && !isTask && "-*+".utf16.contains(ns.character(at: bullet.location))
                // Half a character more after `-`: the text starts where a task's text does.
                if isBullet { storage.addAttribute(.kern, value: advance * MarkdownStyler.bulletKern, range: bullet) }
                if isTask {
                    // Folded to zero width off the caret line (not hidden
                    // like a token, which would hang on the line before).
                    storage.addAttribute(.qmTaskBullet, value: true, range: NSRange(location: bullet.location, length: NSMaxRange(marker.range) - bullet.location))
                }
                // Nested items step in a clear indent, not two narrow spaces.
                var spaces = 0
                while content.location + spaces < bullet.location, ns.character(at: content.location + spaces) == 0x20 { spaces += 1 }
                let step = (style.base.pointSize * 0.5).rounded()
                if spaces > 0 {
                    storage.addAttribute(.kern, value: step, range: NSRange(location: content.location, length: spaces))
                }
                // Wrapped lines of an item hang under its text, not its
                // bullet. A task's box counts as part of the marker.
                var prefixEnd = NSMaxRange(marker.range)
                if let box = Checkbox.boxRange(in: line), content.location + NSMaxRange(box) + 1 <= NSMaxRange(content) {
                    prefixEnd = content.location + NSMaxRange(box) + 1
                }
                let prefixStart = isTask ? NSMaxRange(marker.range) : content.location
                let prefix = (isTask ? ns.substring(with: NSRange(location: content.location, length: spaces)) : "")
                    + ns.substring(with: NSRange(location: prefixStart, length: prefixEnd - prefixStart))
                    .replacingOccurrences(of: "\t", with: "    ")
                let paragraph = style.body.mutableCopy() as! NSMutableParagraphStyle
                var indent = (prefix as NSString).size(withAttributes: [.font: style.base]).width + CGFloat(spaces) * step
                if isBullet { indent += advance * MarkdownStyler.bulletKern }
                if Checkbox.boxRange(in: line) != nil, mayBeTask(ns, content) { indent += 3 * advance * MarkdownStyler.boxKern }
                paragraph.headIndent = indent
                storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
            }

            if mayBeTask(ns, content) {
                styleTask(content, storage: storage, ns: ns, style: style)
            }
        }
    }

    /// `>` after leading spaces, for indented quotes.
    private static func quoteAfterIndent(_ ns: NSString, _ content: NSRange) -> NSTextCheckingResult? {
        var i = content.location
        while i < NSMaxRange(content), ns.character(at: i) == 0x20 { i += 1 }
        guard i < NSMaxRange(content), i > content.location, ns.character(at: i) == 0x3E else { return nil }
        return quotePattern.firstMatch(in: ns as String, range: NSRange(location: i, length: NSMaxRange(content) - i))
    }

    /// The language named on a fence line: ```swift → "swift".
    private static func fenceLanguage(_ ns: NSString, at lineStart: Int) -> String {
        let line = ns.substring(with: contentRange(ns.lineRange(for: NSRange(location: lineStart, length: 0)), ns))
        return line.trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "`" || $0 == "~" })
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? ""
    }

    /// The callout a quote line belongs to: its block's first line reads
    /// `> [!TIP]` (or NOTE, IMPORTANT, WARNING, CAUTION).
    private static func calloutKind(for lineRange: NSRange, in ns: NSString, text: String) -> CalloutKind? {
        var start = lineRange.location
        while start > 0 {
            let previous = ns.lineRange(for: NSRange(location: start - 1, length: 0))
            let t = ns.substring(with: previous).drop(while: { $0 == " " || $0 == "\t" })
            guard t.hasPrefix(">") else { break }
            start = previous.location
        }
        let first = contentRange(ns.lineRange(for: NSRange(location: start, length: 0)), ns)
        guard let match = calloutPattern.firstMatch(in: text, range: first) else { return nil }
        return CalloutKind(marker: ns.substring(with: match.range(at: 1)))
    }

    private static func styleCalloutLine(
        _ content: NSRange, lineRange: NSRange, marker: NSRange, kind: CalloutKind,
        storage: NSTextStorage, ns: NSString, text: String, style: Style
    ) {
        let color = kind.color(for: style.theme)
        // The last line carries the panel's bottom padding.
        var next = NSMaxRange(lineRange)
        while next < ns.length, ns.character(at: next) == 0x20 { next += 1 }
        let isLast = next >= ns.length || ns.character(at: next) != 0x3E  // >
        storage.addAttributes([.qmCallout: color, .paragraphStyle: isLast ? style.calloutLastParagraph : style.calloutParagraph], range: lineRange)
        storage.addAttribute(.foregroundColor, value: style.syntax, range: marker)
        if let title = calloutPattern.firstMatch(in: text, range: content) {
            let word = title.range(at: 1)
            storage.addAttribute(.foregroundColor, value: style.syntax, range: NSRange(location: content.location, length: NSMaxRange(title.range) - content.location))
            storage.addAttributes([.foregroundColor: color, .font: style.strongFont], range: word)
        }
    }

    /// Table rows are monospaced so the padded columns (Tab lines them
    /// up) read as a grid; the pipes and the `|---|` row go quiet.
    private static func styleTableRow(_ content: NSRange, lineRange: NSRange, storage: NSTextStorage, ns: NSString, style: Style) {
        storage.addAttributes([
            .font: style.tableFont, .qmTable: true, .paragraphStyle: style.tableParagraph,
        ], range: lineRange)
        let line = ns.substring(with: content)
        if TableEditing.isDelimiter(line) {
            // The hide-me flag covers the whole line (the row collapses to
            // a hairline); the dim colour stops at the content, so the
            // line break keeps the body colour and never merges into a
            // foreground run with the next row's first pipe.
            storage.addAttribute(.qmTableDelimiter, value: true, range: lineRange)
            storage.addAttribute(.foregroundColor, value: style.syntax, range: content)
            return
        }
        // A header row is the one right above the delimiter.
        if NSMaxRange(lineRange) < ns.length {
            let next = ns.lineRange(for: NSRange(location: NSMaxRange(lineRange), length: 0))
            if TableEditing.isDelimiter(ns.substring(with: next)) {
                storage.addAttributes([
                    .font: style.tableHeaderFont, .foregroundColor: style.palette.strong, .qmTableHeader: true,
                ], range: content)
            }
        }
        for i in 0..<content.length where ns.character(at: content.location + i) == 0x7C {
            // A cell separator, not a token to hide: reading mode keeps the
            // pipe dimmed but drawn, so an unpadded table still shows its
            // columns. (Like a list marker, not like a `**`.)
            storage.addAttributes(
                [.foregroundColor: style.syntax, .qmKeepSyntax: true],
                range: NSRange(location: content.location + i, length: 1)
            )
        }
    }

    private static func isBreak(_ c: unichar) -> Bool {
        c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
    }

    /// The box is drawn as a real checkbox. A ticked item reads as done:
    /// the line dims and the text after the box is struck through. The
    /// file still says `- [x]`.
    private static func styleTask(
        _ content: NSRange, storage: NSTextStorage, ns: NSString, style: Style
    ) {
        let line = ns.substring(with: content)
        guard let box = Checkbox.boxRange(in: line) else { return }
        let checked = Checkbox.isChecked(line)
        let boxRange = NSRange(location: content.location + box.location, length: box.length)
        if checked {
            storage.addAttribute(.foregroundColor, value: style.done, range: content)
            var textStart = content.location + NSMaxRange(box)
            while textStart < NSMaxRange(content), ns.character(at: textStart) == 0x20 { textStart += 1 }
            let textLength = NSMaxRange(content) - textStart
            if textLength > 0 {
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: style.done,
                ], range: NSRange(location: textStart, length: textLength))
            }
        }
        // `[ ]` narrows to a character and a half, the box's own width.
        let advance = (" " as NSString).size(withAttributes: [.font: style.base]).width
        storage.addAttributes([.qmCheckbox: checked, .foregroundColor: NSColor.clear, .kern: advance * boxKern], range: boxRange)
    }

    /// Cheap pre-check so ordinary lines never allocate a substring.
    private static func mayBeTask(_ ns: NSString, _ content: NSRange) -> Bool {
        var i = content.location
        let end = NSMaxRange(content)
        while i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        guard i < end else { return false }
        let c = ns.character(at: i)
        if c == 0x2D || c == 0x2A || c == 0x2B { return true }  // - * +
        guard (0x30...0x39).contains(c) else { return false }
        while i < end, (0x30...0x39).contains(ns.character(at: i)) { i += 1 }
        return i < end && (ns.character(at: i) == 0x2E || ns.character(at: i) == 0x29)  // . )
    }

    /// `^\s*\$\$.+\$\$\s*$` without a regex pass: after indent the line
    /// must open with `$$`.
    private static func mayBeDisplayMath(_ ns: NSString, _ content: NSRange) -> Bool {
        var i = content.location
        let end = NSMaxRange(content)
        while i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        return i + 1 < end && ns.character(at: i) == 0x24 && ns.character(at: i + 1) == 0x24
    }

    /// `^[ \t]*([-*+]|\d+[.)])[ \t]+` without a regex pass: after indent,
    /// a bullet character or digits and a dot/paren. The regex still decides.
    private static func mayBeListMarker(_ ns: NSString, _ content: NSRange) -> Bool {
        var i = content.location
        let end = NSMaxRange(content)
        while i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        guard i < end else { return false }
        let c = ns.character(at: i)
        if c == 0x2D || c == 0x2A || c == 0x2B { return true }  // - * +
        guard (0x30...0x39).contains(c) else { return false }
        var j = i
        while j < end, (0x30...0x39).contains(ns.character(at: j)) { j += 1 }
        return j + 1 < end && (ns.character(at: j) == 0x2E || ns.character(at: j) == 0x29)  // . )
    }

    // MARK: Inline

    private static func styleInline(
        in range: NSRange, storage: NSTextStorage, ns: NSString, text: String, style: Style
    ) {
        func inCodeBlock(_ r: NSRange) -> Bool {
            storage.attribute(.qmCodeBlock, at: r.location, effectiveRange: nil) != nil
        }
        func dim(_ location: Int, _ length: Int) {
            storage.addAttribute(
                .foregroundColor, value: style.syntax,
                range: NSRange(location: location, length: length)
            )
        }

        // Code first: inside a span everything is literal, so the other
        // passes skip anything that starts or ends in one.
        codePattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !inCodeBlock(r) else { return }
            storage.addAttributes([
                .font: style.inlineMono, .backgroundColor: style.codeBackground, .foregroundColor: style.palette.strong,
            ], range: r)
            dim(r.location, 1)
            dim(NSMaxRange(r) - 1, 1)
        }
        func isCode(_ r: NSRange) -> Bool {
            inCodeBlock(r)
                || storage.attribute(.backgroundColor, at: r.location, effectiveRange: nil) != nil
                || storage.attribute(.backgroundColor, at: NSMaxRange(r) - 1, effectiveRange: nil) != nil
                || storage.attribute(.qmMathInline, at: r.location, effectiveRange: nil) != nil
                || storage.attribute(.qmMathInline, at: NSMaxRange(r) - 1, effectiveRange: nil) != nil
        }

        // Math is literal too: `$a*b*c$` mustn't turn italic.
        inlineMathPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !isCode(r),
                  storage.attribute(.qmMathBlock, at: r.location, effectiveRange: nil) == nil else { return }
            storage.addAttributes([
                .font: style.inlineMono, .foregroundColor: style.palette.strong, .qmMathInline: true,
            ], range: r)
            dim(r.location, 1)
            dim(NSMaxRange(r) - 1, 1)
        }

        boldPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !isCode(r) else { return }
            let current = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
            storage.addAttribute(.font, value: style.adding(.bold, to: current), range: r)
            dim(r.location, 2)
            dim(NSMaxRange(r) - 2, 2)
        }
        italicPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !isCode(r) else { return }
            // A `*` on either side means this is half of a **bold**.
            if r.location > 0, ns.character(at: r.location - 1) == 0x2A { return }
            if NSMaxRange(r) < ns.length, ns.character(at: NSMaxRange(r)) == 0x2A { return }
            let current = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
            storage.addAttribute(.font, value: style.adding(.italic, to: current), range: r)
            dim(r.location, 1)
            dim(NSMaxRange(r) - 1, 1)
        }
        strikePattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !isCode(r) else { return }
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: style.syntax,
            ], range: NSRange(location: r.location + 2, length: r.length - 4))
            dim(r.location, 2)
            dim(NSMaxRange(r) - 2, 2)
        }
        markPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !isCode(r) else { return }
            storage.addAttribute(.backgroundColor, value: style.highlight,
                                 range: NSRange(location: r.location + 2, length: r.length - 4))
            dim(r.location, 2)
            dim(NSMaxRange(r) - 2, 2)
        }
        mdLinkPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, !isCode(match.range) else { return }
            let r = match.range, label = match.range(at: 1), target = match.range(at: 2)
            dim(r.location, label.location - r.location)
            dim(NSMaxRange(label), NSMaxRange(r) - NSMaxRange(label))
            guard let url = linkURL(ns.substring(with: target)) else { return }
            storage.addAttributes(linkAttributes(url, style), range: label)
        }
        linkPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !isCode(r),
                  storage.attribute(.qmLink, at: r.location, effectiveRange: nil) == nil,
                  (storage.attribute(.foregroundColor, at: r.location, effectiveRange: nil) as? NSColor) != style.syntax,
                  let url = linkURL(ns.substring(with: r)) else { return }
            storage.addAttributes(linkAttributes(url, style), range: r)
        }
        // Footnotes: `[^1]` reads as a raised 1; a `[^1]:` definition
        // keeps its label, dimmed.
        footnotePattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, !isCode(match.range) else { return }
            let r = match.range, label = match.range(at: 1)
            let isDefinition = NSMaxRange(r) < ns.length && ns.character(at: NSMaxRange(r)) == 0x3A
                && (r.location == 0 || ns.character(at: r.location - 1) == 0x0A)
            if isDefinition {
                storage.addAttributes([.foregroundColor: style.syntax, .qmKeepSyntax: true],
                                      range: NSRange(location: r.location, length: r.length + 1))
                return
            }
            dim(r.location, 2)
            dim(NSMaxRange(r) - 1, 1)
            let font = storage.attribute(.font, at: label.location, effectiveRange: nil) as? NSFont ?? style.base
            storage.addAttributes([
                .font: NSFont(descriptor: font.fontDescriptor, size: (font.pointSize * 0.72).rounded()) ?? font,
                .baselineOffset: (font.pointSize * 0.35).rounded(),
                .foregroundColor: style.link ?? style.palette.strong,
            ], range: label)
        }
    }

    private static let imageLinePattern = try! NSRegularExpression(pattern: #"^\s{0,3}!\[[^\]]*\]\(<?([^)\s>]+)>?(?:\s+"[^"]*")?\)\s*$"#)
    private static let footnotePattern = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\]"#)

    /// Underlined in the body colour, or (Looq) the link colour alone.
    private static func linkAttributes(_ url: URL, _ style: Style) -> [NSAttributedString.Key: Any] {
        if let link = style.link { return [.qmLink: url, .foregroundColor: link] }
        return [.qmLink: url, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: style.syntax]
    }

    /// The URL for a matched link. macOS 13's URL(string:) rejects
    /// anything not already escaped — `Straße`, a `|` in a query — so
    /// those are percent-encoded rather than left unclickable.
    static func linkURL(_ text: String) -> URL? {
        if let url = URL(string: text) { return url }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#%")
        return text.addingPercentEncoding(withAllowedCharacters: allowed).flatMap(URL.init(string:))
    }

    // MARK: Fences

    /// Start offsets of every line that opens or closes a fenced block:
    /// optional leading whitespace, then three backticks. Ascending.
    static func fenceLineStarts(in ns: NSString) -> [Int] { blockFenceLineStarts(in: ns).code }

    /// Line starts of code fences (```` ``` ```` after optional spaces or
    /// tabs) and of `$$` math fences outside code, in one pass over the
    /// characters. Runs on every keystroke, so it reads a flat buffer
    /// rather than searching and slicing the string per hit.
    static func blockFenceLineStarts(in ns: NSString) -> (code: [Int], math: [Int]) {
        let (code, candidates) = scanFenceLineStarts(in: ns, range: NSRange(location: 0, length: ns.length))
        let math = candidates.filter { !isInsideBlock($0, fences: code) }
        return (code, math)
    }

    /// Code-fence line starts and raw `$$`-fence candidate line starts
    /// within `range`. Math candidates come back unfiltered: parity
    /// against code fences is the caller's business, so a partial rescan
    /// doesn't need the whole note in view.
    static func scanFenceLineStarts(in ns: NSString, range: NSRange) -> (code: [Int], mathCandidates: [Int]) {
        let lower = range.location
        let n = NSMaxRange(range)
        guard lower >= 0, n <= ns.length, n > lower else { return ([], []) }
        var buffer = [unichar](repeating: 0, count: n - lower)
        ns.getCharacters(&buffer, range: NSRange(location: lower, length: n - lower))
        var code: [Int] = [], candidates: [Int] = []
        buffer.withUnsafeBufferPointer { c in
            func isBreak(_ u: unichar) -> Bool { u == 0x0A || u == 0x0D || u == 0x2028 || u == 0x2029 }
            func isSpace(_ u: unichar) -> Bool { u == 0x20 || u == 0x09 || u == 0x0B || u == 0x0C || u == 0xA0 }
            var i = 0
            while i < n - lower {
                let start = i + lower
                var j = i
                while j < n - lower, c[j] == 0x20 || c[j] == 0x09 { j += 1 }
                if j + 2 < n - lower, c[j] == 0x60, c[j + 1] == 0x60, c[j + 2] == 0x60 {
                    code.append(start)
                } else {
                    var k = j
                    while k < n - lower, isSpace(c[k]) { k += 1 }
                    if k + 1 < n - lower, c[k] == 0x24, c[k + 1] == 0x24 {
                        var m = k + 2
                        while m < n - lower, isSpace(c[m]) { m += 1 }
                        if m >= n - lower || isBreak(c[m]) { candidates.append(start) }
                    }
                }
                // Next line: past the line break (CR LF counts as one).
                var e = j
                while e < n - lower, !isBreak(c[e]) { e += 1 }
                if e < n - lower, c[e] == 0x0D, e + 1 < n - lower, c[e + 1] == 0x0A { e += 1 }
                i = e + 1
            }
        }
        return (code, candidates)
    }

    static func mathFenceLineStarts(in ns: NSString, codeFences: [Int]) -> [Int] { blockFenceLineStarts(in: ns).math }

    /// A non-fence line is inside a block when an odd number of fences
    /// open above it. An unclosed fence runs to the end of the document,
    /// so a block looks like code while you're still typing it.
    static func isInsideBlock(_ lineStart: Int, fences: [Int]) -> Bool {
        countBelow(fences, lineStart) % 2 == 1
    }


    /// Would the lines after `dirty` still be styled correctly? Every
    /// one of them flips together when the fence count above changes,
    /// so checking the first ordinary line against its current
    /// attribute is enough.
    private static func blocksUnchanged(
        after dirty: NSRange, in storage: NSTextStorage, fences: [Int], mathFences: [Int]
    ) -> Bool {
        let ns = storage.string as NSString
        var location = NSMaxRange(dirty)
        var codeChecked = false, mathChecked = false
        while location < ns.length, !(codeChecked && mathChecked) {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            if !codeChecked, !contains(fences, line.location) {
                let expected = isInsideBlock(line.location, fences: fences)
                let actual = storage.attribute(.qmCodeBlock, at: line.location, effectiveRange: nil) != nil
                if expected != actual { return false }
                codeChecked = true
            }
            if !mathChecked, !contains(mathFences, line.location), !contains(fences, line.location) {
                let expected = countBelow(mathFences, line.location) % 2 == 1 && !isInsideBlock(line.location, fences: fences)
                let actual = storage.attribute(.qmMathBlock, at: line.location, effectiveRange: nil) != nil
                if expected != actual { return false }
                mathChecked = true
            }
            location = NSMaxRange(line)
        }
        return true
    }

    private static func countBelow(_ sorted: [Int], _ value: Int) -> Int {
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func contains(_ sorted: [Int], _ value: Int) -> Bool {
        let i = countBelow(sorted, value)
        return i < sorted.count && sorted[i] == value
    }

    // MARK: Fonts and colours for one pass

    @MainActor
    private struct Style {
        let theme: Theme
        let base: NSFont
        let strongFont: NSFont
        let italic: NSFont
        let mono: NSFont
        let inlineMono: NSFont
        let tableFont: NSFont
        let tableHeaderFont: NSFont
        let quoteFont: NSFont
        let palette: Palette
        let code: CodeColors
        let syntax: NSColor
        let done: NSColor
        let highlight: NSColor
        let codeBackground: NSColor
        let quote: NSColor
        /// Link text colour; nil keeps body colour with an underline.
        let link: NSColor?
        let body: NSParagraphStyle
        let quoteParagraph: NSParagraphStyle
        let calloutParagraph: NSParagraphStyle
        let calloutLastParagraph: NSParagraphStyle
        let tableParagraph: NSParagraphStyle
        let codeParagraph: NSParagraphStyle
        let mathParagraph: NSParagraphStyle
        let centered: NSParagraphStyle

        init(size: CGFloat, theme: Theme) {
            self.theme = theme
            palette = Palette.for(theme)
            code = CodeColors.for(theme)
            syntax = palette.syntax
            done = palette.text.withAlphaComponent(0.45)
            highlight = palette.highlight
            codeBackground = palette.codeBackground
            link = palette.link
            base = Design.font(size: size)
            strongFont = Design.font(size: size, weight: .semibold)
            italic = Self.trait(base, .italic)
            quoteFont = base
            quote = palette.text.withAlphaComponent(0.7)
            inlineMono = base
            mono = Design.font(size: (size * Design.codeScale).rounded())
            tableFont = mono
            tableHeaderFont = Design.font(size: mono.pointSize, weight: .semibold)
            body = MarkdownStyler.bodyParagraph(font: base)

            let indent = (base.pointSize * 1.2).rounded()
            let quoted = body.mutableCopy() as! NSMutableParagraphStyle
            quoted.headIndent = indent
            quoted.firstLineHeadIndent = 0
            quoteParagraph = quoted

            let pad = (size * 0.9).rounded()
            let callout = body.mutableCopy() as! NSMutableParagraphStyle
            callout.firstLineHeadIndent = pad
            callout.headIndent = pad + indent
            callout.tailIndent = -pad
            calloutParagraph = callout
            let calloutLast = callout.mutableCopy() as! NSMutableParagraphStyle
            calloutLast.paragraphSpacing = (size * 0.7).rounded()
            calloutLastParagraph = calloutLast

            let table = NSMutableParagraphStyle()
            table.lineHeightMultiple = MarkdownStyler.multiple(for: tableFont, leading: 1.9)
            table.firstLineHeadIndent = pad
            table.headIndent = pad
            table.tailIndent = -pad
            tableParagraph = table

            let codeStyle = NSMutableParagraphStyle()
            codeStyle.lineHeightMultiple = MarkdownStyler.multiple(for: mono, leading: 1.5)
            codeStyle.firstLineHeadIndent = pad
            codeStyle.headIndent = pad
            codeStyle.tailIndent = -pad
            codeParagraph = codeStyle

            let math = codeStyle.mutableCopy() as! NSMutableParagraphStyle
            math.alignment = .center
            mathParagraph = math

            let center = body.mutableCopy() as! NSMutableParagraphStyle
            center.alignment = .center
            centered = center
        }

        func heading(level: Int) -> NSFont {
            let factor = level <= Design.headingScale.count ? Design.headingScale[level - 1] : 1
            return Design.font(size: (base.pointSize * factor).rounded(), weight: .bold)
        }

        func headingColor(level: Int) -> NSColor { palette.strong }

        /// A blank source line already gives the gap below; headings
        /// get a little extra air above.
        func headingParagraph(level: Int, first: Bool, previousBlank: Bool, nextBlank: Bool) -> NSParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = MarkdownStyler.multiple(for: heading(level: level), leading: 1.4)
            let space = Design.headingSpaceAbove[min(level, Design.headingSpaceAbove.count) - 1]
            // The blank line above already gives one line of air.
            paragraph.paragraphSpacingBefore = first ? 0 : (base.pointSize * (previousBlank ? space - 0.5 : space)).rounded()
            return paragraph
        }

        func adding(_ traits: NSFontDescriptor.SymbolicTraits, to current: NSFont?) -> NSFont {
            guard let current, current != base else { return traits == .bold ? strongFont : italic }
            if traits == .bold { return Design.font(size: current.pointSize, weight: .semibold) }
            return Self.trait(current, traits)
        }

        static func trait(_ font: NSFont, _ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
            let merged = font.fontDescriptor.symbolicTraits.union(traits)
            return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(merged), size: font.pointSize) ?? font
        }
    }
}
