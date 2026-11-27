import AppKit

/// Format › Table: rows and columns added, removed, moved and aligned
/// around the caret's cell. Each command rewrites the table block once,
/// lined up as Tab does, so it undoes in one step.
enum TableCommand: Int, CaseIterable {
    case addRowAbove = 1, addRowBelow, addColumnBefore, addColumnAfter
    case deleteRow, deleteColumn
    case moveRowUp, moveRowDown, moveColumnLeft, moveColumnRight
    case alignLeft, alignCenter, alignRight
    case tidy

    var title: String {
        switch self {
        case .addRowAbove: return "Add Row Above"
        case .addRowBelow: return "Add Row Below"
        case .addColumnBefore: return "Add Column Before"
        case .addColumnAfter: return "Add Column After"
        case .deleteRow: return "Delete Row"
        case .deleteColumn: return "Delete Column"
        case .moveRowUp: return "Move Row Up"
        case .moveRowDown: return "Move Row Down"
        case .moveColumnLeft: return "Move Column Left"
        case .moveColumnRight: return "Move Column Right"
        case .alignLeft: return "Align Column Left"
        case .alignCenter: return "Align Column Center"
        case .alignRight: return "Align Column Right"
        case .tidy: return "Tidy Table"
        }
    }
}

extension TableEditing {
    /// `command` applied to a table block's `text` with the caret at
    /// `offset` in it: the new block (newline-terminated) and where the
    /// caret goes in it. Nil when the command doesn't apply there.
    static func apply(_ command: TableCommand, to text: String, caret offset: Int) -> (text: String, caret: Int)? {
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        guard let d = lines.firstIndex(where: isDelimiter), d > 0 else { return nil }
        var rows = lines.map { cells($0).map { $0.trimmingCharacters(in: .whitespaces) } }
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0 else { return nil }
        for r in rows.indices where rows[r].count < columns {
            rows[r] += Array(repeating: r == d ? "---" : "", count: columns - rows[r].count)
        }
        let here = cellIndex(in: text, at: offset)
        // On the delimiter row the caret counts as in the header.
        var r = min(here.row == d ? d - 1 : here.row, rows.count - 1)
        var c = min(here.column, columns - 1)
        let inBody = r > d

        func insertColumn(at i: Int) {
            for k in rows.indices { rows[k].insert(k == d ? "---" : "", at: i) }
        }
        func align(_ marker: String) { rows[d][c] = marker }

        switch command {
        case .addRowAbove:
            guard inBody else { return nil }
            rows.insert(Array(repeating: "", count: columns), at: r)
        case .addRowBelow:
            let at = inBody ? r + 1 : d + 1
            rows.insert(Array(repeating: "", count: columns), at: at)
            r = at
        case .addColumnBefore:
            insertColumn(at: c)
        case .addColumnAfter:
            insertColumn(at: c + 1)
            c += 1
        case .deleteRow:
            guard inBody else { return nil }
            rows.remove(at: r)
            r = r < rows.count ? r : rows.count - 1
            if r == d { r = 0 }
        case .deleteColumn:
            guard columns > 1 else { return nil }
            for k in rows.indices { rows[k].remove(at: c) }
            c = min(c, columns - 2)
        case .moveRowUp:
            guard r > d + 1 else { return nil }
            rows.swapAt(r, r - 1)
            r -= 1
        case .moveRowDown:
            guard inBody, r + 1 < rows.count else { return nil }
            rows.swapAt(r, r + 1)
            r += 1
        case .moveColumnLeft:
            guard c > 0 else { return nil }
            for k in rows.indices { rows[k].swapAt(c, c - 1) }
            c -= 1
        case .moveColumnRight:
            guard c + 1 < columns else { return nil }
            for k in rows.indices { rows[k].swapAt(c, c + 1) }
            c += 1
        case .alignLeft: align(":---")
        case .alignCenter: align(":---:")
        case .alignRight: align("---:")
        case .tidy: break
        }
        let layout = format(rows.map { "| " + $0.joined(separator: " | ") + " |" })
        let cell = layout.cells[r][c]
        return (layout.text, cell.location + cell.length)
    }
}

extension MarkdownTextView {
    /// Format › Table: the item's tag is the command.
    @objc func tableCommand(_ sender: NSMenuItem) {
        guard let command = TableCommand(rawValue: sender.tag), let block = currentTable, !hasMarkedText() else {
            return NSSound.beep()
        }
        let original = (string as NSString).substring(with: block)
        guard var result = TableEditing.apply(command, to: original, caret: selectedRange().location - block.location) else {
            return NSSound.beep()
        }
        // The block's own newline may be missing at the end of the note.
        if !original.hasSuffix("\n") { result.text.removeLast() }
        if result.text != original {
            guard shouldChangeText(in: block, replacementString: result.text) else { return }
            textStorage?.replaceCharacters(in: block, with: result.text)
            didChangeText()
        }
        setSelectedRange(NSRange(location: block.location + min(result.caret, result.text.utf16.count), length: 0))
        scrollRangeToVisible(selectedRange())
    }
}
