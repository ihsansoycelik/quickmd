import AppKit

/// Line and block commands: moving and deleting lines, heading levels,
/// ticking tasks in bulk, a table of contents, front matter and heading
/// links. Pure and UTF-16 indexed; the text view applies each result as
/// one edit, so it undoes in one step.
enum BlockEditing {
    /// One replacement and where the selection goes after it.
    struct Edit: Equatable {
        var range: NSRange
        var replacement: String
        var selection: NSRange
    }

    /// Every line's range, terminator included. A text that is empty or
    /// ends in a newline gets a last, empty line at its end.
    static func lineRanges(_ ns: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var location = 0
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            result.append(line)
            location = NSMaxRange(line)
        }
        if ns.length == 0 || ns.character(at: ns.length - 1) == 0x0A {
            result.append(NSRange(location: ns.length, length: 0))
        }
        return result
    }

    private static func lineIndex(at location: Int, in lines: [NSRange]) -> Int {
        for (i, line) in lines.enumerated() where location < NSMaxRange(line) { return i }
        return lines.count - 1
    }

    /// First and last line the selection touches; a selection ending
    /// at a line's start doesn't take that line.
    static func selectedLineIndices(_ selection: NSRange, in ns: NSString, lines: [NSRange]) -> (Int, Int) {
        let first = lineIndex(at: selection.location, in: lines)
        let end = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        return (first, max(first, lineIndex(at: end, in: lines)))
    }

    private static func content(_ i: Int, _ lines: [NSRange], _ ns: NSString) -> String {
        var s = ns.substring(with: lines[i])
        if s.hasSuffix("\n") { s.removeLast() }
        return s
    }

    /// Width of a line's leading whitespace, a tab counting four.
    static func indentWidth(_ line: String) -> Int {
        var width = 0
        for c in line {
            if c == " " { width += 1 } else if c == "\t" { width += 4 } else { break }
        }
        return width
    }

    static func isListItem(_ line: String) -> Bool {
        line.range(of: #"^[ \t]*(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)"#, options: .regularExpression) != nil
    }

    private static func isBlank(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A list item's last line: its nested items and continuation lines
    /// come with it, up to a blank line or a line indented no deeper.
    private static func itemEnd(from i: Int, _ lines: [NSRange], _ ns: NSString) -> Int {
        let head = content(i, lines, ns)
        guard isListItem(head) else { return i }
        let indent = indentWidth(head)
        var end = i
        while end + 1 < lines.count {
            let next = content(end + 1, lines, ns)
            guard !isBlank(next), indentWidth(next) > indent, lines[end + 1].length > 0 else { break }
            end += 1
        }
        return end
    }

    /// Moves the selected lines (a list item with its children when the
    /// caret is on one) past the line or item above or below them.
    static func moveLines(in text: String, selection: NSRange, up: Bool) -> Edit? {
        let ns = text as NSString
        let lines = lineRanges(ns)
        var (first, last) = selectedLineIndices(selection, in: ns, lines: lines)
        if first == last { last = itemEnd(from: first, lines, ns) }
        // The empty line after a final newline isn't something to move.
        if first == last, lines[first].length == 0 { return nil }
        let unit: ClosedRange<Int>
        if up {
            guard first > 0 else { return nil }
            var start = first - 1
            let head = content(first, lines, ns)
            if isListItem(head) {
                // Above a sibling item, not into its children.
                let indent = indentWidth(head)
                while start > 0 {
                    let line = content(start, lines, ns)
                    guard !isBlank(line), indentWidth(line) > indent else { break }
                    start -= 1
                }
            }
            unit = start...(first - 1)
        } else {
            guard last + 1 < lines.count, lines[last + 1].length > 0 else { return nil }
            unit = (last + 1)...itemEnd(from: last + 1, lines, ns)
        }
        let block = (first...last).map { content($0, lines, ns) }.joined(separator: "\n")
        let other = unit.map { content($0, lines, ns) }.joined(separator: "\n")
        let start = min(lines[first].location, lines[unit.lowerBound].location)
        let end = max(NSMaxRange(lines[last]), NSMaxRange(lines[unit.upperBound]))
        let range = NSRange(location: start, length: end - start)
        let trailing = ns.substring(with: range).hasSuffix("\n") ? "\n" : ""
        let replacement = (up ? block + "\n" + other : other + "\n" + block) + trailing
        let shift = other.utf16.count + 1
        let moved = NSRange(location: selection.location + (up ? -shift : shift), length: selection.length)
        return Edit(range: range, replacement: replacement, selection: moved)
    }

    /// Deletes the selected lines whole; the caret goes to the line after.
    static func deleteLines(in text: String, selection: NSRange) -> Edit? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let lines = lineRanges(ns)
        let (first, last) = selectedLineIndices(selection, in: ns, lines: lines)
        var range = NSRange(location: lines[first].location, length: NSMaxRange(lines[last]) - lines[first].location)
        // The last line has no newline of its own: take the one before it.
        if !ns.substring(with: range).hasSuffix("\n"), range.location > 0 {
            range = NSRange(location: range.location - 1, length: range.length + 1)
        }
        guard range.length > 0 else { return nil }
        let caret = range.location > 0 && NSMaxRange(range) >= ns.length && !ns.substring(with: range).hasSuffix("\n")
            ? (ns.lineRange(for: NSRange(location: range.location - 1, length: 0)).location)
            : range.location
        return Edit(range: range, replacement: "", selection: NSRange(location: caret, length: 0))
    }

    /// An ATX heading one level up (`by: -1`, fewer `#`) or down, kept
    /// within H1…H6. Other lines are left as they are.
    static func shiftHeading(_ line: String, by delta: Int) -> String {
        guard let match = line.firstMatch(of: /^( {0,3})(#{1,6})([ \t]+|$)/) else { return line }
        let level = min(6, max(1, match.2.count + delta))
        return String(match.1) + String(repeating: "#", count: level) + line[match.2.endIndex...]
    }

    /// Where a heading's text starts on its line (after `## `).
    static func headingContentStart(_ line: String) -> Int {
        if let match = line.firstMatch(of: /^ {0,3}#{1,6}[ \t]+/) { return match.0.utf16.count }
        return line.prefix(while: { $0 == " " }).count
    }

    /// `[Title](#slug)` text, brackets in the title escaped.
    static func link(title: String, id: String) -> String {
        let label = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "[\(label)](#\(id))"
    }

    /// A nested bullet list linking every heading, the way the renderer
    /// names their anchors. Nil when the note has no headings.
    static func tableOfContents(_ text: String) -> String? {
        let headings = Headings.find(in: text)
        let anchors = Headings.anchors(in: text)
        guard let top = headings.map(\.level).min(), headings.count == anchors.count else { return nil }
        var previous = -1
        var lines: [String] = []
        for (heading, anchor) in zip(headings, anchors) {
            // One level deeper at most: a jump from H1 to H3 still nests once.
            let depth = min(heading.level - top, previous + 1)
            previous = depth
            lines.append(String(repeating: "    ", count: depth) + "- " + link(title: heading.title, id: anchor.id))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The link to the heading on the line at `location`, or nil when
    /// that line isn't a heading (a setext underline counts as its heading).
    static func headingLink(in text: String, at location: Int) -> String? {
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        let above = line.location > 0 ? ns.lineRange(for: NSRange(location: line.location - 1, length: 0)).location : -1
        let headings = Headings.find(in: text)
        let anchors = Headings.anchors(in: text)
        guard headings.count == anchors.count,
              let i = headings.firstIndex(where: { $0.location == line.location })
                ?? headings.firstIndex(where: { $0.location == above && !$0.title.isEmpty && !ns.substring(with: line).hasPrefix("#")
                    && HorizontalRuleLayoutManager.setextLevel(underline: line, in: ns) != nil }) else { return nil }
        return link(title: headings[i].title, id: anchors[i].id)
    }

    static func hasFrontMatter(_ text: String) -> Bool {
        MarkdownHTML.frontMatterEnd(text.components(separatedBy: "\n")) != nil
    }

    /// `---`, a title and today's date, `---`, then a blank line.
    static func frontMatter(title: String, date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return "---\ntitle: \(yamlValue(title))\ndate: \(f.string(from: date))\n---\n\n"
    }

    /// A YAML scalar: quoted when plain would misread it.
    static func yamlValue(_ s: String) -> String {
        let special = s.isEmpty || s.contains(": ") || s.contains(" #") || s.hasSuffix(":")
            || "!&*[]{}|>'\"%@`#,?-".contains(s.first!) || s != s.trimmingCharacters(in: .whitespaces)
        guard special else { return s }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

extension Checkbox {
    /// The line with its box ticked or cleared, or nil when it has none.
    static func setting(_ line: String, checked: Bool) -> String? {
        guard let box = boxRange(in: line) else { return nil }
        guard isChecked(line) != checked else { return line }
        return (line as NSString).replacingCharacters(in: NSRange(location: box.location + 1, length: 1), with: checked ? "x" : " ")
    }
}

// MARK: Commands

extension MarkdownTextView {
    private func apply(_ edit: BlockEditing.Edit?) {
        guard let edit, !hasMarkedText() else { return NSSound.beep() }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        let length = (string as NSString).length
        let location = min(max(0, edit.selection.location), length)
        setSelectedRange(NSRange(location: location, length: min(edit.selection.length, length - location)))
        scrollRangeToVisible(selectedRange())
    }

    @objc func moveLineUp(_ sender: Any?) { apply(BlockEditing.moveLines(in: string, selection: selectedRange(), up: true)) }
    @objc func moveLineDown(_ sender: Any?) { apply(BlockEditing.moveLines(in: string, selection: selectedRange(), up: false)) }
    @objc func deleteLine(_ sender: Any?) { apply(BlockEditing.deleteLines(in: string, selection: selectedRange())) }

    @objc func promoteHeading(_ sender: Any?) { transformLines { BlockEditing.shiftHeading($0, by: -1) } }
    @objc func demoteHeading(_ sender: Any?) { transformLines { BlockEditing.shiftHeading($0, by: 1) } }

    @objc func checkSelectedTasks(_ sender: Any?) { transformLines { Checkbox.setting($0, checked: true) ?? $0 } }
    @objc func uncheckSelectedTasks(_ sender: Any?) { transformLines { Checkbox.setting($0, checked: false) ?? $0 } }

    @objc func toggleHighlight(_ sender: Any?) { MarkdownWrap.toggle(in: self, marker: "==") }

    @objc func insertTableOfContents(_ sender: Any?) {
        guard let toc = BlockEditing.tableOfContents(string) else { return NSSound.beep() }
        insertBlock(toc)
    }

    @objc func insertFrontMatter(_ sender: Any?) {
        guard !BlockEditing.hasFrontMatter(string) else { return NSSound.beep() }
        let document = window?.windowController?.document as? NSDocument
        let title = document?.fileURL?.deletingPathExtension().lastPathComponent ?? document?.displayName ?? L("Untitled")
        let block = BlockEditing.frontMatter(title: title, date: Date())
        replace(NSRange(location: 0, length: 0), with: block)
        // The title, ready to retype.
        let value = BlockEditing.yamlValue(title)
        setSelectedRange(NSRange(location: 11, length: value.utf16.count))
        scrollRangeToVisible(selectedRange())
    }

    @objc func copyLinkToHeading(_ sender: Any?) {
        guard let link = BlockEditing.headingLink(in: string, at: selectedRange().location) else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    /// The table the caret is in, as a block range, when it is one.
    var currentTable: NSRange? {
        let ns = string as NSString
        let location = selectedRange().location
        guard !isInCodeBlock(location), let block = TableEditing.blockRange(in: ns, at: location) else { return nil }
        return ns.substring(with: block).components(separatedBy: "\n").contains(where: TableEditing.isDelimiter) ? block : nil
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(tableCommand(_:)):
            return isEditable && currentTable != nil
        case #selector(copyLinkToHeading(_:)):
            return BlockEditing.headingLink(in: string, at: selectedRange().location) != nil
        case #selector(insertFrontMatter(_:)):
            return isEditable && !BlockEditing.hasFrontMatter(string)
        case #selector(foldSection(_:)), #selector(unfoldSection(_:)), #selector(unfoldAll(_:)):
            return folding?.canPerform(menuItem.action!, in: self) ?? false
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
