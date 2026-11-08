import AppKit

/// NSLayoutManager subclass that paints a full-width horizontal rule
/// over any line whose entire content is HR markers (`-` and/or `─`,
/// 3+ characters). The HR characters themselves are kept in storage
/// (so the file on disk stays plain markdown — `---`) but rendered
/// with `foregroundColor = .clear` from the styling pass, so the only
/// visible thing on the line is the rule we draw here.
///
/// The line spans the line fragment's full width, which means it
/// tracks panel-width changes for free — resize the window and the
/// rule grows/shrinks with it.
final class HorizontalRuleLayoutManager: NSLayoutManager {
    /// Color used when stroking the rule. The editor updates this on
    /// every theme flip via applyPalette.
    var ruleColor: NSColor = .secondaryLabelColor

    /// Ground painted behind fenced code and math blocks. Set alongside
    /// `ruleColor`; nil paints nothing.
    var codeBlockColor: NSColor?
    /// Border of table panels and ground of callouts.
    var panelBorderColor: NSColor = .separatorColor
    var panelFillColor: NSColor = .clear
    /// Outline of an unticked checkbox.
    var checkboxColor: NSColor = .secondaryLabelColor

    // MARK: Table grids

    /// Is the table at this range drawn as a grid (reading mode, caret
    /// elsewhere)? Set by the editor; nil draws every table as source.
    var tableIsRendered: ((NSRange) -> Bool)?
    /// Face the grid's cells read in.
    var tableBodyFont: NSFont = .systemFont(ofSize: 14) {
        didSet { gridCache.removeAll() }
    }
    private var gridCache: [String: TableGrid] = [:]

    func clearTableGrids() { gridCache.removeAll() }

    /// The whole table block around `location`, when it's drawn as a grid.
    func renderedTable(at location: Int) -> NSRange? {
        guard let storage = textStorage, let tableIsRendered, location < storage.length else { return nil }
        var block = NSRange()
        guard storage.attribute(.qmTable, at: location, longestEffectiveRange: &block,
                                in: NSRange(location: 0, length: storage.length)) != nil else { return nil }
        var hasDelimiter = false
        storage.enumerateAttribute(.qmTableDelimiter, in: block) { value, _, stop in
            if value != nil { hasDelimiter = true; stop.pointee = true }
        }
        return hasDelimiter && tableIsRendered(block) ? block : nil
    }

    /// The grid for a table block, fitted to `available` points.
    func grid(for block: NSRange, available: CGFloat) -> TableGrid? {
        guard let storage = textStorage else { return nil }
        let text = (storage.string as NSString).substring(with: block)
        let key = "\(block.location)|\(Int(available))|\(text)"
        if let cached = gridCache[key] { return cached }
        guard let grid = TableGrid.build(storage: storage, range: block, available: available, bodyFont: tableBodyFont) else { return nil }
        if gridCache.count > 64 { gridCache.removeAll() }
        gridCache[key] = grid
        return grid
    }

    // MARK: Inline images

    /// The picture for an image line's target, when it's drawn (reading
    /// mode, caret elsewhere, a local file that loads). Set by the editor.
    var imageForLine: ((NSRange, String) -> NSImage?)?
    static let imageMargin: CGFloat = 6
    static let imageMaxHeight: CGFloat = 520

    /// The image line around `location` and its picture, when drawn.
    func renderedImage(at location: Int) -> (NSRange, NSImage)? {
        guard let storage = textStorage, let imageForLine, location < storage.length else { return nil }
        var line = NSRange()
        guard let target = storage.attribute(.qmImage, at: location, longestEffectiveRange: &line,
                                             in: NSRange(location: 0, length: storage.length)) as? String,
              let image = imageForLine(line, target) else { return nil }
        return (line, image)
    }

    /// The size an image is drawn at in `available` points.
    static func imageSize(_ image: NSImage, available: CGFloat) -> CGSize {
        var size = image.size
        guard size.width > 0, size.height > 0 else { return .zero }
        if size.width > available { size = CGSize(width: available, height: size.height * available / size.width) }
        if size.height > imageMaxHeight { size = CGSize(width: size.width * imageMaxHeight / size.height, height: imageMaxHeight) }
        return CGSize(width: size.width.rounded(), height: size.height.rounded())
    }

    /// Width a grid gets inside a line fragment of `width`.
    func gridWidth(forFragmentWidth width: CGFloat) -> CGFloat {
        width - 2 * (textContainers.first?.lineFragmentPadding ?? 5)
    }

    /// Where the grid of a rendered table sits, in container coordinates.
    func gridFrame(for block: NSRange) -> (TableGrid, CGPoint)? {
        // The grid sits in the tallest fragment: the one the first row made room in.
        let glyphs = glyphRange(forCharacterRange: block, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var fragment = CGRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            if fragment.isNull || rect.height > fragment.height { fragment = rect }
        }
        guard !fragment.isNull else { return nil }
        guard let grid = grid(for: block, available: gridWidth(forFragmentWidth: fragment.width)) else { return nil }
        let padding = textContainers.first?.lineFragmentPadding ?? 5
        return (grid, CGPoint(x: fragment.minX + padding, y: fragment.minY + TableGrid.margin))
    }

    /// Paint one panel per block — code, math, table, callout — spanning
    /// the line fragments' full width so it tracks the window like the
    /// rule above. An attribute-only `.backgroundColor` would stop at
    /// the end of each line and leave a ragged right edge.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let context = NSGraphicsContext.current?.cgContext {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            let full = NSRange(location: 0, length: storage.length)

            /// Every block of `key` that the visible range touches, whole,
            /// so a partly scrolled block still gets its rounded ends.
            func blocks(_ key: NSAttributedString.Key, _ body: (CGRect, Any, NSRange) -> Void) {
                var location = charRange.location
                while location < NSMaxRange(charRange) {
                    var effective = NSRange()
                    let value = storage.attribute(key, at: location, longestEffectiveRange: &effective, in: full)
                    if let value, let rect = panelRect(for: effective) {
                        body(rect.offsetBy(dx: origin.x, dy: origin.y), value, effective)
                    }
                    location = max(location + 1, NSMaxRange(effective))
                }
            }

            for key in [NSAttributedString.Key.qmCodeBlock, .qmMathBlock] {
                guard let color = codeBlockColor else { break }
                blocks(key) { panel, _, _ in
                    context.saveGState()
                    context.setFillColor(color.cgColor)
                    context.addPath(CGPath(roundedRect: panel, cornerWidth: 8, cornerHeight: 8, transform: nil))
                    context.fillPath()
                    context.restoreGState()
                }
            }

            blocks(.qmQuote) { panel, _, _ in
                context.saveGState()
                context.setFillColor(ruleColor.cgColor)
                context.fill(CGRect(x: panel.minX, y: panel.minY, width: 3, height: panel.height))
                context.restoreGState()
            }

            blocks(.qmTable) { panel, _, range in
                if renderedTable(at: range.location) != nil {
                    if let (grid, at) = gridFrame(for: range) {
                        grid.draw(at: CGPoint(x: at.x + origin.x, y: at.y + origin.y),
                                  border: panelBorderColor, headerFill: panelFillColor, context: context)
                    }
                    return
                }
                let path = CGPath(roundedRect: panel.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 8, cornerHeight: 8, transform: nil)
                context.saveGState()
                context.addPath(path)
                context.setFillColor(panelFillColor.cgColor)
                context.fillPath()
                context.addPath(path)
                context.clip()
                // Header ground, and a hairline under every row but the last.
                storage.enumerateAttribute(.qmTableHeader, in: range) { value, headerRange, _ in
                    guard value != nil, let header = panelRect(for: headerRange) else { return }
                    let r = CGRect(x: panel.minX, y: header.minY + origin.y, width: panel.width, height: header.height)
                    context.setFillColor(panelFillColor.cgColor)
                    context.fill(r)
                }
                context.setFillColor(panelBorderColor.cgColor)
                let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, lineGlyphs, _ in
                    let bottom = rect.maxY + origin.y
                    guard bottom < panel.maxY - 1 else { return }
                    // Only the last fragment of a wrapped row gets the line.
                    let chars = self.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
                    let end = NSMaxRange(chars)
                    guard end > 0, (storage.string as NSString).character(at: end - 1) == 0x0A else { return }
                    context.fill(CGRect(x: panel.minX, y: bottom - 0.5, width: panel.width, height: 1))
                }
                context.restoreGState()
                context.saveGState()
                context.addPath(path)
                context.setStrokeColor(panelBorderColor.cgColor)
                context.setLineWidth(1)
                context.strokePath()
                context.restoreGState()
            }

            var imageLocation = charRange.location
            while imageLocation < NSMaxRange(charRange) {
                var effective = NSRange()
                let value = storage.attribute(.qmImage, at: imageLocation, longestEffectiveRange: &effective, in: full)
                if value != nil, let (line, image) = renderedImage(at: imageLocation) {
                    let glyphs = glyphRange(forCharacterRange: line, actualCharacterRange: nil)
                    var fragment = CGRect.null
                    enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                        if fragment.isNull || rect.height > fragment.height { fragment = rect }
                    }
                    if !fragment.isNull {
                        let padding = textContainers.first?.lineFragmentPadding ?? 5
                        let size = Self.imageSize(image, available: gridWidth(forFragmentWidth: fragment.width))
                        let rect = CGRect(x: origin.x + fragment.minX + padding, y: origin.y + fragment.minY + Self.imageMargin,
                                          width: size.width, height: size.height)
                        NSGraphicsContext.saveGraphicsState()
                        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
                        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
                imageLocation = max(imageLocation + 1, NSMaxRange(effective))
            }

            blocks(.qmCallout) { panel, value, _ in
                guard let color = value as? NSColor else { return }
                context.saveGState()
                context.setFillColor(panelFillColor.cgColor)
                context.addPath(CGPath(roundedRect: panel, cornerWidth: 6, cornerHeight: 6, transform: nil))
                context.fillPath()
                context.setFillColor(color.cgColor)
                context.addPath(CGPath(roundedRect: CGRect(x: panel.minX, y: panel.minY, width: 3, height: panel.height), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                context.fillPath()
                context.restoreGState()
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    /// The union of the line fragments of a character range, in
    /// container coordinates.
    private func panelRect(for range: NSRange) -> CGRect? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var union = CGRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, lineGlyphs, _ in
            // Hidden glyphs opening a block (`> `, a fence) hang on the
            // line before; that line isn't part of the block's panel.
            let first = self.characterIndexForGlyph(at: lineGlyphs.location)
            guard first >= range.location || lineGlyphs.location >= glyphs.location && NSMaxRange(lineGlyphs) > NSMaxRange(glyphs) else { return }
            union = union.isNull ? rect : union.union(rect)
        }
        return union.isNull ? nil : union
    }

    /// A task's box: the `[ ]` characters are clear; a checkbox is drawn
    /// over them, centred on the text's cap height.
    private func drawCheckboxes(in charRange: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, let container = textContainers.first else { return }
        storage.enumerateAttribute(.qmCheckbox, in: charRange) { value, range, _ in
            guard let checked = value as? Bool else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let box = boundingRect(forGlyphRange: glyphs, in: container)
            let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let baseline = fragment.minY + location(forGlyphAt: glyphs.location).y
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
            let side = (font.pointSize * 0.95).rounded()
            let rect = NSRect(
                x: origin.x + box.minX + 1,  // left-aligned: `[x]` is wider than `[ ]`
                y: origin.y + baseline - font.capHeight / 2 - side / 2,
                width: side, height: side
            )
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: side * 0.24, yRadius: side * 0.24)
            if checked {
                NSColor.controlAccentColor.setFill()
                path.fill()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: rect.minX + side * 0.26, y: rect.minY + side * 0.52))
                tick.line(to: NSPoint(x: rect.minX + side * 0.43, y: rect.minY + side * 0.69))
                tick.line(to: NSPoint(x: rect.minX + side * 0.75, y: rect.minY + side * 0.32))
                tick.lineWidth = max(1.5, side * 0.12)
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                checkboxColor.setStroke()
                path.lineWidth = 1.25
                path.stroke()
            }
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawCheckboxes(in: characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil), at: origin)

        guard let textStorage = textStorage,
              let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let nsString = textStorage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        var lineStart = charRange.location
        let charEnd = charRange.location + charRange.length
        while lineStart < charEnd {
            let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
            // Inside a fenced block `---` is code, not a rule.
            if Self.isHorizontalRuleLine(lineRange: lineRange, in: nsString),
               textStorage.attribute(.qmCodeBlock, at: lineRange.location, effectiveRange: nil) == nil {
                let glyphRange = self.glyphRange(
                    forCharacterRange: lineRange,
                    actualCharacterRange: nil
                )
                if glyphRange.length > 0 {
                    let fragmentRect = lineFragmentRect(
                        forGlyphAt: glyphRange.location,
                        effectiveRange: nil
                    )
                    let cy = origin.y + fragmentRect.midY
                    let lineRect = CGRect(
                        x: origin.x + fragmentRect.minX,
                        y: cy - 0.5,
                        width: fragmentRect.width,
                        height: 1.0
                    )
                    context.saveGState()
                    context.setFillColor(ruleColor.cgColor)
                    context.fill(lineRect)
                    context.restoreGState()
                }
            }
            lineStart = lineRange.location + lineRange.length
        }
    }

    /// Pure: is the given line content (a line range in `nsString`)
    /// an HR-only line — at least three characters, all of which are
    /// either `-` (0x2D) or `─` (0x2500), with the trailing newline
    /// allowed.
    static func isHorizontalRuleLine(lineRange: NSRange, in nsString: NSString) -> Bool {
        let content = lineContent(lineRange, in: nsString)
        if content.length < 3 { return false }
        for i in 0..<content.length {
            let c = nsString.character(at: content.location + i)
            if c != 0x2D && c != 0x2500 { return false }
        }
        // Under a line of text, dashes make that line a heading instead.
        return setextLevel(underline: lineRange, in: nsString) == nil
    }

    /// The line without its line break (LF, CRLF or CR).
    static func lineContent(_ lineRange: NSRange, in ns: NSString) -> NSRange {
        var end = NSMaxRange(lineRange)
        while end > lineRange.location, ns.character(at: end - 1) == 0x0A || ns.character(at: end - 1) == 0x0D { end -= 1 }
        return NSRange(location: lineRange.location, length: end - lineRange.location)
    }

    /// Does this line read as paragraph text, not a heading, quote,
    /// table, fence, list item or indented code? By characters, not a
    /// regex: it runs per line and the storage's string would be copied.
    private static func isPlainText(_ line: NSRange, in ns: NSString) -> Bool {
        let end = NSMaxRange(line)
        var i = line.location
        while i < end, ns.character(at: i) == 0x20 { i += 1 }
        guard i < end, i - line.location < 4, ns.character(at: i) != 0x09 else { return false }
        let c = ns.character(at: i)
        if [0x23, 0x3E, 0x7C, 0x60, 0x7E].contains(c) { return false }  // # > | ` ~
        func spaceOrEnd(_ k: Int) -> Bool { k >= end || ns.character(at: k) == 0x20 || ns.character(at: k) == 0x09 }
        if c == 0x2D || c == 0x2A || c == 0x2B, spaceOrEnd(i + 1) { return false }  // - * +
        var j = i
        while j < end, j - i < 9, (0x30...0x39).contains(ns.character(at: j)) { j += 1 }
        if j > i, j < end, ns.character(at: j) == 0x2E || ns.character(at: j) == 0x29, spaceOrEnd(j + 1) { return false }
        return true
    }

    /// The heading level a setext underline gives the text above it:
    /// `===` makes it a level 1 heading, `---` level 2. Nil when the
    /// line isn't an underline, or the line above isn't plain text.
    static func setextLevel(underline lineRange: NSRange, in ns: NSString) -> Int? {
        guard lineRange.location > 0 else { return nil }
        let content = lineContent(lineRange, in: ns)
        guard content.length > 0 else { return nil }
        let first = ns.character(at: content.location)
        guard first == 0x3D || first == 0x2D else { return nil }  // = -
        for i in 0..<content.length where ns.character(at: content.location + i) != first { return nil }
        if first == 0x2D, content.length < 2 { return nil }
        // The `---` closing front matter ends metadata, not a heading.
        if first == 0x2D, frontMatterClose(in: ns) == lineRange.location { return nil }
        let above = lineContent(ns.lineRange(for: NSRange(location: lineRange.location - 1, length: 0)), in: ns)
        guard above.length > 0, isPlainText(above, in: ns) else { return nil }
        // A rule or another underline above isn't text (checked flat: no recursion down a run of rules).
        let ruleChars: Set<unichar> = [0x2D, 0x3D, 0x2500, 0x2A, 0x5F, 0x20]
        if (0..<above.length).allSatisfy({ ruleChars.contains(ns.character(at: above.location + $0)) }) { return nil }
        return first == 0x3D ? 1 : 2
    }

    /// Where the line closing a front matter block starts (`---`, then
    /// `key: value` lines, then `---` or `...`), or nil without one.
    static func frontMatterClose(in ns: NSString) -> Int? {
        guard ns.length > 4, ns.hasPrefix("---") else { return nil }
        let first = ns.lineRange(for: NSRange(location: 0, length: 0))
        guard lineContent(first, in: ns).length == 3, NSMaxRange(first) < ns.length else { return nil }
        var location = NSMaxRange(first)
        let second = lineContent(ns.lineRange(for: NSRange(location: location, length: 0)), in: ns)
        guard ns.substring(with: second).range(of: #"^[A-Za-z0-9_-]+:"#, options: .regularExpression) != nil else { return nil }
        var count = 0
        while location < ns.length, count < 300 {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let text = ns.substring(with: lineContent(line, in: ns))
            if text == "---" || text == "..." { return line.location }
            location = NSMaxRange(line)
            count += 1
        }
        return nil
    }

    /// Convenience for tests — takes a Swift String, treats the whole
    /// thing as the line content (no trailing newline expected).
    static func isHorizontalRuleLine(_ line: String) -> Bool {
        let ns = line as NSString
        return isHorizontalRuleLine(
            lineRange: NSRange(location: 0, length: ns.length),
            in: ns
        )
    }
}
