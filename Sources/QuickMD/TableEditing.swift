import Foundation

/// Pipe tables: parsing cells, lining up columns, and finding the cell
/// Tab should move to. Pure and UTF-16 indexed, like Checkbox.
enum TableEditing {
    /// Is this line a table row? It starts with a pipe (after indent).
    static func isRow(_ line: String) -> Bool {
        line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("|")
    }

    static func isDelimiter(_ line: String) -> Bool {
        line.contains("-") && line.wholeMatch(of: /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/) != nil
    }

    /// Cell texts of a row: outer pipes dropped, split on unescaped
    /// pipes outside code spans. Untrimmed.
    static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|"), !t.hasSuffix("\\|") { t.removeLast() }
        var result: [String] = []
        var current = ""
        var inCode = false
        var previous: Character = " "
        for c in t {
            if c == "`" { inCode.toggle() }
            if c == "|", !inCode, previous != "\\" {
                result.append(current); current = ""
            } else {
                current.append(c)
            }
            previous = c
        }
        result.append(current)
        return result
    }

    /// The contiguous run of table rows around `location`.
    static func blockRange(in ns: NSString, at location: Int) -> NSRange? {
        let here = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        guard isRow(ns.substring(with: here)) else { return nil }
        var start = here.location
        while start > 0 {
            let previous = ns.lineRange(for: NSRange(location: start - 1, length: 0))
            guard isRow(ns.substring(with: previous)) else { break }
            start = previous.location
        }
        var end = NSMaxRange(here)
        while end < ns.length {
            let next = ns.lineRange(for: NSRange(location: end, length: 0))
            guard isRow(ns.substring(with: next)) else { break }
            end = NSMaxRange(next)
        }
        return NSRange(location: start, length: end - start)
    }

    /// One laid-out table: its text, and where each cell's content
    /// starts and how long it is, per row.
    struct Layout {
        var text: String
        var cells: [[NSRange]]
        var delimiterRow: Int?
    }

    /// Rows padded so the pipes line up in a monospaced font.
    static func format(_ lines: [String]) -> Layout {
        let rows = lines.map { cells($0).map { $0.trimmingCharacters(in: .whitespaces) } }
        let delimiter = lines.firstIndex(where: isDelimiter)
        let columns = rows.map(\.count).max() ?? 0
        var widths = Array(repeating: 3, count: columns)
        for (r, row) in rows.enumerated() where r != delimiter {
            for (c, cell) in row.enumerated() { widths[c] = max(widths[c], cell.count) }
        }
        var text = ""
        var layout: [[NSRange]] = []
        var offset = 0
        for (r, row) in rows.enumerated() {
            var line = "|"
            var ranges: [NSRange] = []
            for c in 0..<columns {
                var cell = c < row.count ? row[c] : ""
                if r == delimiter {
                    let left = cell.hasPrefix(":"), right = cell.hasSuffix(":") && cell.count > 1
                    let dashes = widths[c] - (left ? 1 : 0) - (right ? 1 : 0)
                    cell = (left ? ":" : "") + String(repeating: "-", count: max(1, dashes)) + (right ? ":" : "")
                }
                let start = offset + line.utf16.count + 1
                ranges.append(NSRange(location: start, length: cell.utf16.count))
                line += " " + cell + String(repeating: " ", count: max(0, widths[c] - cell.count)) + " |"
            }
            text += line + "\n"
            offset += line.utf16.count + 1
            layout.append(ranges)
        }
        return Layout(text: text, cells: layout, delimiterRow: delimiter)
    }

    /// Which cell (row, column) holds `offset` within a block's text.
    static func cellIndex(in text: String, at offset: Int) -> (row: Int, column: Int) {
        let ns = text as NSString
        var row = 0
        var lineStart = 0
        while lineStart < ns.length {
            let line = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            if offset < NSMaxRange(line) || NSMaxRange(line) >= ns.length {
                var column = -1
                var i = line.location
                var inCode = false
                while i < min(offset, NSMaxRange(line)) {
                    let c = ns.character(at: i)
                    if c == 0x60 { inCode.toggle() }
                    if c == 0x7C, !inCode, !(i > 0 && ns.character(at: i - 1) == 0x5C) { column += 1 }
                    i += 1
                }
                return (row, max(0, column))
            }
            row += 1
            lineStart = NSMaxRange(line)
        }
        return (row, 0)
    }
}
