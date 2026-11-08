import AppKit

/// A pipe table laid out as a real grid for reading mode: columns sized
/// like a browser's auto layout, cells wrapped, the header bold. The
/// source rows stay in storage (their glyphs are hidden); the grid is
/// drawn over the room the first row's line fragment makes for it.
struct TableGrid {
    struct Row {
        var cells: [NSAttributedString]
        var height: CGFloat
        var isHeader: Bool
    }

    var columns: [CGFloat]
    var alignments: [NSTextAlignment]
    var rows: [Row]
    var width: CGFloat { columns.reduce(0, +) }
    var height: CGFloat { rows.reduce(0) { $0 + $1.height } }

    static let padX: CGFloat = 10
    static let padY: CGFloat = 7
    /// Space above and below the grid inside the first row's fragment.
    static let margin: CGFloat = 6

    // MARK: Building

    /// The grid for the table rows in `range`, fitted to `available`
    /// points. Nil without a delimiter row (it isn't a table then).
    static func build(storage: NSTextStorage, range: NSRange, available: CGFloat, bodyFont: NSFont) -> TableGrid? {
        let ns = storage.string as NSString
        var lines: [NSRange] = []
        var location = range.location
        while location < NSMaxRange(range) {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            lines.append(HorizontalRuleLayoutManager.lineContent(line, in: ns))
            location = NSMaxRange(line)
        }
        guard let delimiterIndex = lines.firstIndex(where: { TableEditing.isDelimiter(ns.substring(with: $0)) }),
              delimiterIndex > 0 else { return nil }

        let alignments = cellRanges(lines[delimiterIndex], in: ns).map { r -> NSTextAlignment in
            let t = ns.substring(with: r)
            switch (t.hasPrefix(":"), t.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .right
            default: return .left
            }
        }

        var raw: [(cells: [NSAttributedString], header: Bool)] = []
        for (i, line) in lines.enumerated() where i != delimiterIndex {
            let header = i < delimiterIndex
            raw.append((cellRanges(line, in: ns).map { cell(storage, $0, header: header, bodyFont: bodyFont) }, header))
        }
        let count = max(alignments.count, raw.map(\.cells.count).max() ?? 0)
        guard count > 0 else { return nil }

        // Natural (one line) and minimum (longest word) widths per column.
        var natural = [CGFloat](repeating: 0, count: count)
        var minimum = [CGFloat](repeating: 0, count: count)
        for row in raw {
            for (c, text) in row.cells.enumerated() where c < count {
                natural[c] = max(natural[c], ceil(text.size().width))
                minimum[c] = max(minimum[c], longestWord(text))
            }
        }
        let pad = 2 * padX
        let budget = max(available - pad * CGFloat(count), CGFloat(count) * 24)
        var widths: [CGFloat]
        let naturalSum = natural.reduce(0, +)
        if naturalSum <= budget {
            widths = natural
        } else {
            let minSum = minimum.reduce(0, +)
            if minSum >= budget {
                widths = minimum.map { $0 * budget / max(minSum, 1) }
            } else {
                let spare = budget - minSum
                let want = zip(natural, minimum).map { $0 - $1 }
                let wantSum = max(want.reduce(0, +), 1)
                widths = zip(minimum, want).map { $0 + spare * $1 / wantSum }
            }
        }
        // Short tables keep their natural size; a wrapping one fills the column.
        let columns = widths.map { floor($0) + pad }

        var rows: [Row] = []
        for row in raw {
            var cells = row.cells
            while cells.count < count { cells.append(NSAttributedString()) }
            var h: CGFloat = bodyFont.ascender - bodyFont.descender + bodyFont.leading
            for (c, text) in cells.prefix(count).enumerated() where text.length > 0 {
                let bound = text.boundingRect(
                    with: NSSize(width: columns[c] - pad, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
                h = max(h, ceil(bound.height))
            }
            rows.append(Row(cells: Array(cells.prefix(count)), height: h + 2 * padY, isHeader: row.header))
        }
        var aligned = alignments
        while aligned.count < count { aligned.append(.left) }
        return TableGrid(columns: columns, alignments: aligned, rows: rows)
    }

    /// Cell content ranges of a row: outer pipes dropped, split on
    /// unescaped pipes outside code spans, whitespace trimmed.
    static func cellRanges(_ line: NSRange, in ns: NSString) -> [NSRange] {
        var start = line.location
        var end = NSMaxRange(line)
        while start < end, isSpace(ns.character(at: start)) { start += 1 }
        while end > start, isSpace(ns.character(at: end - 1)) { end -= 1 }
        if start < end, ns.character(at: start) == 0x7C { start += 1 }
        if end > start, ns.character(at: end - 1) == 0x7C, !(end - 2 >= start && ns.character(at: end - 2) == 0x5C) { end -= 1 }
        var result: [NSRange] = []
        var cellStart = start
        var inCode = false
        var i = start
        while i < end {
            let c = ns.character(at: i)
            if c == 0x60 { inCode.toggle() }
            if c == 0x7C, !inCode, !(i > start && ns.character(at: i - 1) == 0x5C) {
                result.append(trim(NSRange(location: cellStart, length: i - cellStart), ns))
                cellStart = i + 1
            }
            i += 1
        }
        result.append(trim(NSRange(location: cellStart, length: end - cellStart), ns))
        return result
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }

    private static func trim(_ r: NSRange, _ ns: NSString) -> NSRange {
        var s = r.location, e = NSMaxRange(r)
        while s < e, isSpace(ns.character(at: s)) { s += 1 }
        while e > s, isSpace(ns.character(at: e - 1)) { e -= 1 }
        return NSRange(location: s, length: e - s)
    }

    /// The cell as it reads: hidden tokens dropped, the table's mono
    /// face swapped for the body face (bold/italic kept, code kept).
    private static func cell(_ storage: NSTextStorage, _ range: NSRange, header: Bool, bodyFont: NSFont) -> NSAttributedString {
        guard range.length > 0 else { return NSAttributedString() }
        let out = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let all = NSRange(location: 0, length: out.length)
        out.removeAttribute(.paragraphStyle, range: all)
        out.enumerateAttribute(.font, in: all) { value, run, _ in
            guard let font = value as? NSFont, font.isFixedPitch,
                  out.attribute(.backgroundColor, at: run.location, effectiveRange: nil) == nil else { return }
            var traits = font.fontDescriptor.symbolicTraits.intersection([.bold, .italic])
            if header { traits.insert(.bold) }
            let swapped = traits.isEmpty ? bodyFont
                : NSFont(descriptor: bodyFont.fontDescriptor.withSymbolicTraits(traits), size: bodyFont.pointSize) ?? bodyFont
            out.addAttribute(.font, value: swapped, range: run)
        }
        // Emoji and other fallback runs keep their own face but match the size.
        out.enumerateAttribute(.font, in: all) { value, run, _ in
            guard let font = value as? NSFont, font.pointSize != bodyFont.pointSize, !font.isFixedPitch else { return }
            out.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: bodyFont.pointSize) ?? font, range: run)
        }
        var hidden: [NSRange] = []
        out.enumerateAttribute(.qmSyntax, in: all) { value, run, _ in if value != nil { hidden.append(run) } }
        for r in hidden.reversed() { out.deleteCharacters(in: r) }
        return out
    }

    private static func longestWord(_ text: NSAttributedString) -> CGFloat {
        let ns = text.string as NSString
        var best: CGFloat = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { _, r, _, _ in
            best = max(best, ceil(text.attributedSubstring(from: r).size().width))
        }
        return min(best, 220)
    }

    // MARK: Drawing

    /// Draws the grid with its top-left at `origin` (flipped coordinates).
    func draw(at origin: CGPoint, border: NSColor, headerFill: NSColor, context: CGContext) {
        let frame = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        let path = CGPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.saveGState()
        context.addPath(path)
        context.clip()
        var y = origin.y
        for row in rows {
            if row.isHeader {
                context.setFillColor(headerFill.cgColor)
                context.fill(CGRect(x: frame.minX, y: y, width: frame.width, height: row.height))
            }
            var x = origin.x
            for (c, text) in row.cells.enumerated() {
                let rect = CGRect(x: x + Self.padX, y: y + Self.padY, width: columns[c] - 2 * Self.padX, height: row.height - 2 * Self.padY)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = alignments[c]
                paragraph.lineBreakMode = .byWordWrapping
                let styled = NSMutableAttributedString(attributedString: text)
                styled.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: styled.length))
                styled.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
                x += columns[c]
            }
            y += row.height
            if y < frame.maxY - 1 {
                context.setFillColor(border.cgColor)
                context.fill(CGRect(x: frame.minX, y: y - 0.5, width: frame.width, height: 1))
            }
        }
        // Column rules.
        context.setFillColor(border.withAlphaComponent(border.alphaComponent * 0.7).cgColor)
        var x = origin.x
        for w in columns.dropLast() {
            x += w
            context.fill(CGRect(x: x - 0.5, y: frame.minY, width: 1, height: frame.height))
        }
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(border.cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
    }

    /// The source character a click on the grid at `point` (relative to
    /// the grid's top-left) belongs to: the start of that cell's text.
    func cellIndex(at point: CGPoint) -> (row: Int, column: Int)? {
        guard point.x >= 0, point.y >= 0, point.x < width, point.y < height else { return nil }
        var y: CGFloat = 0
        for (r, row) in rows.enumerated() {
            if point.y < y + row.height {
                var x: CGFloat = 0
                for (c, w) in columns.enumerated() {
                    if point.x < x + w { return (r, c) }
                    x += w
                }
                return (r, columns.count - 1)
            }
            y += row.height
        }
        return nil
    }
}
