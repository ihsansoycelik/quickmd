import AppKit

/// The editor's text view: markdown-aware Return and Tab, clickable
/// checkboxes, ⌘-click links, and the Format menu's commands. The text
/// stays plain markdown; every change goes through the normal
/// shouldChange/didChange path so undo and autosave see it.
final class MarkdownTextView: NSTextView {
    /// Where relative links resolve from: the document's folder.
    var baseURL: URL?

    /// Markdown marks are hidden (reading mode, Show Markdown Syntax
    /// off): the caret steps over them and Backspace takes a block's
    /// marker in one go.
    var concealsMarkup = false

    /// Between shouldChangeText and didChangeText: the selection set
    /// there follows the edit and is left as it is.
    private var isEditingText = false
    /// The key command being performed, so an arrow step can be told
    /// from a click or a jump.
    private var currentCommand: Selector?

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let ok = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if ok { isEditingText = true }
        return ok
    }

    // MARK: Caret

    /// The caret is trimmed to the font's height instead of the whole
    /// (1.35×) line, so it sits on the text rather than towering over it.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: Self.caretRect(in: rect, font: caretFont), color: color, turnedOn: flag)
    }

    /// The font of the text the caret sits in: the character before it on
    /// the same line, else the one after, so a caret on a heading is
    /// heading height.
    private var caretFont: NSFont? {
        guard let storage = textStorage, storage.length > 0 else { return font }
        let ns = storage.string as NSString
        let location = min(selectedRange().location, storage.length)
        var index: Int?
        if location > 0, !"\n\r\u{2028}\u{2029}".utf16.contains(ns.character(at: location - 1)) {
            index = location - 1
        } else if location < storage.length {
            index = location
        }
        guard let index else { return font }
        return storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? font
    }

    static func caretRect(in rect: NSRect, font: NSFont?) -> NSRect {
        guard let font else { return rect }
        let height = (font.ascender - font.descender).rounded(.up)
        guard height < rect.height else { return rect }
        return NSRect(x: rect.minX, y: rect.maxY - height, width: max(rect.width, caretWidth), height: height)
    }

    /// A firmer caret than AppKit's hairline, easy to find on the page.
    static let caretWidth: CGFloat = 2

    /// The wider caret must be erased whole when it blinks off.
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var rect = rect
        if rect.width <= Self.caretWidth { rect.size.width = Self.caretWidth + 1 }
        super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
    }

    // MARK: Return and Tab

    override func insertNewline(_ sender: Any?) {
        autoMarker = nil
        autoPair = nil
        let ns = string as NSString
        let selection = selectedRange()
        guard selection.length == 0, !hasMarkedText() else { return super.insertNewline(sender) }
        let line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let beforeCaret = ns.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        let indent = String(beforeCaret.prefix(while: { $0 == " " || $0 == "\t" }))
        let body = String(beforeCaret.dropFirst(indent.count))
        // Code keeps its indent and nothing else: no list or quote there.
        if isInCodeBlock(line.location) {
            insertText("\n" + indent, replacementRange: selection)
            return
        }
        // Return before a heading's hidden `## `: a new line above, the heading kept whole.
        if concealsMarkup, let storage = textStorage, let prefix = Concealment.blockPrefix(lineRange: line, in: storage),
           prefix.heading != nil, prefix.quote == nil, selection.location == prefix.contentStart {
            replace(NSRange(location: line.location, length: 0), with: "\n")
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            return
        }
        // With text after the caret the item isn't empty, whatever's before it.
        let afterCaret = ns.substring(with: NSRange(location: selection.location, length: NSMaxRange(line) - selection.location))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // `- - -` and `* * *` are rules, not list items.
        if HorizontalRuleLayoutManager.isHorizontalRuleLine(lineRange: line, in: ns) {
            return super.insertNewline(sender)
        }

        if body.hasPrefix(">") {
            let quote = body.prefix(while: { $0 == ">" || $0 == " " })
            if body.trimmingCharacters(in: CharacterSet(charactersIn: "> ")).isEmpty, afterCaret.isEmpty {
                // An empty quote line ends the quote.
                replace(NSRange(location: line.location, length: beforeCaret.utf16.count), with: "")
                return
            }
            insertText("\n" + indent + quote, replacementRange: selection)
            return
        }

        // The marker has to be before the caret: Return at the start of
        // `- foo` (or inside `1.`) just breaks the line.
        guard SmartEditing.nextListMarker(for: body) != nil,
              let marker = SmartEditing.nextListMarker(for: afterCaret.isEmpty ? body : body + afterCaret) else {
            return super.insertNewline(sender)
        }
        if marker.isEmpty {
            // Return on an empty item ends the list (or outdents it one level).
            if !indent.isEmpty {
                let outdented = String(indent.dropFirst(min(indent.count, 4)))
                replace(NSRange(location: line.location, length: indent.utf16.count), with: outdented)
                // The caret stays after the marker, not before it.
                setSelectedRange(NSRange(location: selection.location - (indent.utf16.count - outdented.utf16.count), length: 0))
            } else {
                replace(NSRange(location: line.location, length: beforeCaret.utf16.count), with: "")
            }
            return
        }
        insertText("\n" + indent + marker, replacementRange: selection)
        autoMarker = (selection.location + 1, indent + marker)
    }

    /// The marker Return just put on a new line: typing another block
    /// marker right after it replaces it instead of nesting.
    private var autoMarker: (lineStart: Int, prefix: String)?

    private static let blockMarkerPattern = try! NSRegularExpression(
        pattern: #"^(?:[-*+] \[[ xX]\]|\[[ xX]\]|>|#{1,6}|\d{1,9}[.)]|[-*+])$"#
    )

    /// `- ` from Return, then `> ` typed: the line becomes `> `, not `- > `.
    private func replaceFreshMarker(_ typed: String, at location: Int) -> Bool {
        guard typed == " ", let auto = autoMarker else { return false }
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: location, length: 0))
        guard line.location == auto.lineStart, location >= line.location else { return false }
        let before = ns.substring(with: NSRange(location: line.location, length: location - line.location))
        let after = ns.substring(with: NSRange(location: location, length: NSMaxRange(line) - location))
        guard before.hasPrefix(auto.prefix), after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let newMarker = String(before.dropFirst(auto.prefix.count))
        guard !newMarker.isEmpty,
              Self.blockMarkerPattern.firstMatch(in: newMarker, range: NSRange(location: 0, length: newMarker.utf16.count)) != nil
        else { return false }
        let indent = String(auto.prefix.prefix(while: { $0 == " " || $0 == "\t" }))
        let oldMarker = auto.prefix.dropFirst(indent.count)
        let replacement: String
        if newMarker.hasPrefix("[") {
            // A bare box: the same item, now a task.
            let bullet = oldMarker.replacingOccurrences(of: #"\[[ xX]\] $"#, with: "", options: .regularExpression)
            replacement = indent + bullet + "[ ] "
        } else if newMarker.hasPrefix(">") || newMarker.hasPrefix("#") {
            // A quote or heading leaves the list: no indent.
            replacement = newMarker + " "
        } else {
            replacement = indent + newMarker + " "
        }
        autoMarker = nil
        replace(NSRange(location: line.location, length: location - line.location), with: replacement)
        return true
    }

    override func insertTab(_ sender: Any?) {
        if moveInTable(forward: true) { return }
        if isListContext, !isInCodeBlock(selectedRange().location) { shiftLines(right: true) } else { super.insertTab(sender) }
    }

    /// Is `location` inside fenced code? The styler marks those lines.
    private func isInCodeBlock(_ location: Int) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let line = (string as NSString).lineRange(for: NSRange(location: min(location, storage.length), length: 0))
        guard line.location < storage.length else { return false }
        return storage.attribute(.qmCodeBlock, at: line.location, effectiveRange: nil) != nil
    }

    override func insertBacktab(_ sender: Any?) {
        if moveInTable(forward: false) { return }
        shiftLines(right: false)
    }

    // MARK: Typing over a selection

    /// Typed with text selected, these wrap it instead of replacing it.
    private static let wrapPairs: [String: String] = ["*": "*", "_": "_", "`": "`", "~": "~", "=": "=", "[": "]", "(": ")", "\"": "\""]

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let selection = selectedRange()
        if let typed = string as? String, replacementRange.location == NSNotFound, selection.length == 0, !hasMarkedText() {
            if stepOverClosingMark(typed, at: selection.location) { return }
            if replaceFreshMarker(typed, at: selection.location) { return }
            if insertAutoPair(typed, at: selection.location) { return }
        }
        if let typed = string as? String, let close = Self.wrapPairs[typed], replacementRange.location == NSNotFound,
           selection.length > 0, !hasMarkedText(),
           !(self.string as NSString).substring(with: selection).contains("\n") {
            let inner = (self.string as NSString).substring(with: selection)
            replace(selection, with: typed + inner + close)
            setSelectedRange(NSRange(location: selection.location + typed.utf16.count, length: selection.length))
            return
        }
        super.insertText(string, replacementRange: replacementRange)
        if string as? String == "/" { openSlashMenuIfAtWordStart() }
    }

    // MARK: Auto-pairs

    /// A closing mark typed for the writer (`**`, a backtick, `~~`):
    /// counted from the end of its line, which typing inside the pair
    /// doesn't move.
    private var autoPair: (lineStart: Int, fromEnd: Int, opener: String, closer: String)?

    private func lineContentEnd(_ line: NSRange, _ ns: NSString) -> Int {
        var end = NSMaxRange(line)
        while end > line.location, "\n\r\u{2028}\u{2029}".utf16.contains(ns.character(at: end - 1)) { end -= 1 }
        return end
    }

    /// Where the pending closing mark is, if it is still there.
    private func autoPairCloser(at location: Int) -> Int? {
        guard let pair = autoPair else { return nil }
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        let closer = lineContentEnd(line, ns) - pair.fromEnd
        guard line.location == pair.lineStart, closer >= line.location,
              closer + pair.closer.utf16.count <= ns.length,
              ns.substring(with: NSRange(location: closer, length: pair.closer.utf16.count)) == pair.closer else {
            autoPair = nil
            return nil
        }
        return closer
    }

    /// The rest of a closing mark stepped over in one go: typing it
    /// next is swallowed, so `**` typed in full still lands after it.
    private var swallow: (location: Int, text: String)?

    private func stepOverClosingMark(_ typed: String, at location: Int) -> Bool {
        if let pending = swallow {
            swallow = nil
            if pending.location == location, pending.text.hasPrefix(typed) {
                let rest = String(pending.text.dropFirst(typed.count))
                if !rest.isEmpty { swallow = (location, rest) }
                return true
            }
        }
        guard let pair = autoPair, pair.closer.hasPrefix(typed), autoPairCloser(at: location) == location else { return false }
        // The whole closer at once: with marks hidden, a caret between
        // its two `*` would look the same and step out anyway.
        autoPair = nil
        let end = location + pair.closer.utf16.count
        let rest = String(pair.closer.dropFirst(typed.count))
        if !rest.isEmpty { swallow = (end, rest) }
        setSelectedRange(NSRange(location: end, length: 0))
        return true
    }

    /// `**`, `` ` `` or `~~` typed before a space or the line's end, after
    /// a space or the line's start: the closing half goes in too.
    private func insertAutoPair(_ typed: String, at location: Int) -> Bool {
        guard typed == "*" || typed == "`" || typed == "~", !isInCodeBlock(location) else { return false }
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: location, length: 0))
        let end = lineContentEnd(line, ns)
        func isSpaceOrEdge(_ i: Int) -> Bool {
            guard i >= line.location, i < end else { return true }
            return ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09
        }
        guard isSpaceOrEdge(location) else { return false }
        // An odd number of backticks before: inside inline code.
        let before = ns.substring(with: NSRange(location: line.location, length: location - line.location))
        guard before.filter({ $0 == "`" }).count % 2 == 0 else { return false }
        let opener: String
        if typed == "`" {
            guard isSpaceOrEdge(location - 1) else { return false }
            opener = "`"
        } else {
            guard location - 1 >= line.location, ns.character(at: location - 1) == typed.utf16.first,
                  isSpaceOrEdge(location - 2) else { return false }
            opener = typed + typed
        }
        let closer = opener
        super.insertText(typed + closer, replacementRange: NSRange(location: location, length: 0))
        setSelectedRange(NSRange(location: location + typed.utf16.count, length: 0))
        let newLine = (self.string as NSString).lineRange(for: NSRange(location: location, length: 0))
        let closerAt = location + typed.utf16.count
        autoPair = (newLine.location, lineContentEnd(newLine, self.string as NSString) - closerAt, opener, closer)
        return true
    }

    // MARK: Backspace

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, !hasMarkedText(), let storage = textStorage {
            // Right after an auto-paired opener, with nothing typed in it: both go.
            if let pair = autoPair, pair.closer == pair.opener, autoPairCloser(at: selection.location) == selection.location {
                let length = pair.opener.utf16.count
                let ns = string as NSString
                if selection.location >= length,
                   ns.substring(with: NSRange(location: selection.location - length, length: length)) == pair.opener {
                    autoPair = nil
                    replace(NSRange(location: selection.location - length, length: 2 * length), with: "")
                    return
                }
            }
            // At a block's content start: its whole marker goes, the
            // innermost first (a heading or list item becomes a paragraph).
            if concealsMarkup {
                let line = (string as NSString).lineRange(for: NSRange(location: selection.location, length: 0))
                if let prefix = Concealment.blockPrefix(lineRange: line, in: storage), selection.location == prefix.contentStart,
                   let marker = prefix.heading ?? prefix.list ?? prefix.quote {
                    autoMarker = nil
                    replace(marker, with: "")
                    return
                }
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: Slash menu

    private lazy var slashMenu = SlashMenu(textView: self)

    /// A `/` at the start of a line or after a space, outside code.
    private func openSlashMenuIfAtWordStart() {
        let ns = string as NSString
        let caret = selectedRange()
        guard caret.length == 0, caret.location > 0, !hasMarkedText(), !isInCodeBlock(caret.location) else { return }
        let slash = caret.location - 1
        guard slash == 0 || Character(UnicodeScalar(ns.character(at: slash - 1)) ?? " ").isWhitespace else { return }
        slashMenu.open(at: slash)
    }

    override func doCommand(by selector: Selector) {
        if slashMenu.handle(selector) { return }
        currentCommand = selector
        defer { currentCommand = nil }
        super.doCommand(by: selector)
    }

    override func didChangeText() {
        isEditingText = false
        super.didChangeText()
        slashMenu.update()
    }

    // MARK: Arrows over hidden marks

    /// AppKit's own ← and → stall or jump at a hidden glyph, so with
    /// marks hidden the caret moves one visible character itself.
    override func moveRight(_ sender: Any?) { if !stepCaret(forward: true) { super.moveRight(sender) } }
    override func moveLeft(_ sender: Any?) { if !stepCaret(forward: false) { super.moveLeft(sender) } }
    override func moveForward(_ sender: Any?) { if !stepCaret(forward: true) { super.moveForward(sender) } }
    override func moveBackward(_ sender: Any?) { if !stepCaret(forward: false) { super.moveBackward(sender) } }

    override func moveRightAndModifySelection(_ sender: Any?) {
        if !extendSelection(forward: true) { super.moveRightAndModifySelection(sender) }
    }
    override func moveLeftAndModifySelection(_ sender: Any?) {
        if !extendSelection(forward: false) { super.moveLeftAndModifySelection(sender) }
    }

    /// The fixed end of a selection grown with ⇧← and ⇧→.
    private var extendAnchor: Int?

    private func extendSelection(forward: Bool) -> Bool {
        let selection = selectedRange()
        guard concealsMarkup, !hasMarkedText(), let storage = textStorage else { return false }
        let anchor: Int
        if selection.length == 0 {
            anchor = selection.location
        } else if let known = extendAnchor, known == selection.location || known == NSMaxRange(selection) {
            anchor = known
        } else {
            anchor = forward ? selection.location : NSMaxRange(selection)
        }
        let head = anchor == selection.location ? NSMaxRange(selection) : selection.location
        guard var moved = Concealment.step(from: head, forward: forward, in: storage) else { return false }
        // Only hidden marks left between the ends: nothing is selected.
        let between = NSRange(location: min(anchor, moved), length: abs(moved - anchor))
        if between.length > 0, (between.location..<NSMaxRange(between)).allSatisfy({
            storage.attribute(.qmConceal, at: $0, effectiveRange: nil) != nil
        }) { moved = anchor }
        extendAnchor = anchor
        setSelectedRange(NSRange(location: min(anchor, moved), length: abs(moved - anchor)))
        scrollRangeToVisible(NSRange(location: moved, length: 0))
        return true
    }

    private func stepCaret(forward: Bool) -> Bool {
        let selection = selectedRange()
        guard concealsMarkup, selection.length == 0, !hasMarkedText(), let storage = textStorage else { return false }
        guard let target = Concealment.step(from: selection.location, forward: forward, in: storage) else { return false }
        setSelectedRange(NSRange(location: target, length: 0))
        scrollRangeToVisible(selectedRange())
        return true
    }

    private static let stepCommands: Set<Selector> = [
        #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)),
        #selector(NSResponder.moveForward(_:)), #selector(NSResponder.moveBackward(_:)),
    ]

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        // A caret never rests inside hidden marks: it goes to their edge,
        // or past them when an arrow key moved it.
        if concealsMarkup, !isEditingText, !stillSelecting, !hasMarkedText(), ranges.count == 1,
           let storage = textStorage, ranges[0].rangeValue.length == 0 {
            let target = ranges[0].rangeValue.location
            let old = selectedRange()
            let step = currentCommand.map(Self.stepCommands.contains) ?? false
            let snapped = Concealment.snap(target, from: old.length == 0 ? old.location : nil, step: step, in: storage)
            if snapped != target { ranges = [NSValue(range: NSRange(location: snapped, length: 0))] }
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        slashMenu.update()
    }

    override func resignFirstResponder() -> Bool {
        slashMenu.close()
        return super.resignFirstResponder()
    }

    /// Pasting a URL over selected words links them: `[words](url)`.
    override func paste(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length > 0,
           let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           clip.range(of: #"^(https?|mailto):\S+$"#, options: .regularExpression) != nil {
            let label = (string as NSString).substring(with: selection)
            if !label.contains("\n") {
                replace(selection, with: "[\(label)](\(clip))")
                return
            }
        }
        let board = NSPasteboard.general
        // Files copied in Finder paste as links, the way dropping them does.
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            replace(selection, with: markdownLinks(for: urls))
            return
        }
        // A screenshot or a copied image: saved beside the note, linked in.
        if board.string(forType: .string) == nil,
           let image = NSImage(pasteboard: board) {
            pasteImage(image, over: selection)
            return
        }
        super.paste(sender)
    }

    private func pasteImage(_ image: NSImage, over selection: NSRange) {
        guard let folder = baseURL,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return NSSound.beep()  // an untitled note has no folder to keep the image in
        }
        let write = { [weak self] in
            guard let self else { return }
            let stamp = Self.stampFormatter.string(from: Date())
            var file = folder.appendingPathComponent("Pasted image \(stamp).png")
            var n = 2
            while FileManager.default.fileExists(atPath: file.path) {
                file = folder.appendingPathComponent("Pasted image \(stamp) \(n).png"); n += 1
            }
            do {
                try png.write(to: file, options: .withoutOverwriting)
                self.replace(selection, with: self.markdownLinks(for: [file]))
            } catch {
                NSSound.beep()
            }
        }
        if FolderAccess.canRead(folder) { write() } else {
            FolderAccess.request(folder, for: window) { granted in if granted { write() } }
        }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    // MARK: Dropping files

    /// Files dropped in become links, images become images, with paths
    /// relative to the note's folder when they're inside it.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        let index = characterIndexForInsertion(at: point)
        setSelectedRange(NSRange(location: index, length: 0))
        replace(NSRange(location: index, length: 0), with: markdownLinks(for: urls))
        window?.makeFirstResponder(self)
        return true
    }

    /// Image files as images, other files as links, one per line.
    private func markdownLinks(for urls: [URL]) -> String {
        let images: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "tif", "tiff", "bmp"]
        return urls.map { url -> String in
            let name = url.deletingPathExtension().lastPathComponent
            let target = relativePath(to: url)
            return images.contains(url.pathExtension.lowercased()) ? "![\(name)](\(target))" : "[\(name)](\(target))"
        }.joined(separator: "\n")
    }

    /// `url` as a markdown link target: relative to the note's folder
    /// when it's inside it, else a file URL. Spaces are escaped.
    private func relativePath(to url: URL) -> String {
        let file = url.standardizedFileURL.path
        if let base = baseURL?.standardizedFileURL.path, file.hasPrefix(base + "/") {
            let relative = String(file.dropFirst(base.count + 1))
            return relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
        }
        return url.absoluteString
    }

    // MARK: Tables

    /// Tab and ⇧Tab in a table: line the columns up, then select the
    /// next (or previous) cell. Tab past the last cell adds a row.
    private func moveInTable(forward: Bool) -> Bool {
        let ns = string as NSString
        let selection = selectedRange()
        guard !hasMarkedText(), !isInCodeBlock(selection.location),
              let block = TableEditing.blockRange(in: ns, at: selection.location) else { return false }
        let original = ns.substring(with: block)
        var lines = original.components(separatedBy: "\n")
        if original.hasSuffix("\n") { lines.removeLast() }
        // Without a delimiter row it's text with pipes, not a table.
        guard lines.contains(where: TableEditing.isDelimiter) else { return false }
        let here = TableEditing.cellIndex(in: original, at: selection.location - block.location)
        var layout = TableEditing.format(lines)
        let columns = layout.cells.first?.count ?? 0
        guard columns > 0 else { return false }

        var row = here.row, column = here.column
        func step() {
            if forward {
                column += 1
                if column >= columns { column = 0; row += 1 }
            } else {
                column -= 1
                if column < 0 { column = columns - 1; row -= 1 }
            }
        }
        step()
        // The delimiter row isn't a place to type: skip the whole row.
        if row == layout.delimiterRow {
            row += forward ? 1 : -1
            column = forward ? 0 : columns - 1
        }
        if row < 0 { row = 0; column = 0 }
        if row >= layout.cells.count {
            // A fresh empty row at the end.
            lines = layout.text.components(separatedBy: "\n").filter { !$0.isEmpty }
            lines.append("|" + String(repeating: " |", count: columns))
            layout = TableEditing.format(lines)
            row = layout.cells.count - 1
            column = 0
        }
        // The block's own trailing newline may be missing at the end of the file.
        var replacement = layout.text
        if !original.hasSuffix("\n") { replacement.removeLast() }
        if replacement != original {
            replace(block, with: replacement)
        }
        let cell = layout.cells[row][column]
        setSelectedRange(NSRange(location: block.location + cell.location, length: cell.length))
        scrollRangeToVisible(selectedRange())
        return true
    }

    /// Ticks or unticks the task on line `n` of the note (counting
    /// `\n`s, as the preview does), from a click in the preview.
    func toggleTask(line n: Int) {
        let ns = string as NSString
        var start = 0
        for _ in 0..<n {
            let next = ns.range(of: "\n", options: .literal, range: NSRange(location: start, length: ns.length - start))
            guard next.location != NSNotFound else { return }
            start = NSMaxRange(next)
        }
        let newline = ns.range(of: "\n", options: .literal, range: NSRange(location: start, length: ns.length - start))
        let lineRange = NSRange(location: start, length: (newline.location == NSNotFound ? ns.length : newline.location) - start)
        let line = ns.substring(with: lineRange)
        guard let match = line.firstMatch(of: /^[ \t]*(?:>[ \t]?)*[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\[[ xX]\]/) else { return }
        // The character between the brackets: two before the match's end.
        let offset = line.utf16.distance(from: line.startIndex, to: match.range.upperBound) - 2
        let at = NSRange(location: lineRange.location + offset, length: 1)
        replace(at, with: ns.substring(with: at) == " " ? "x" : " ", keepSelection: true)
    }

    // MARK: Insert

    private func insertBlock(_ block: String, select: String? = nil) {
        let ns = string as NSString
        let selection = selectedRange()
        let line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let lead = selection.location == line.location ? "" : "\n"
        let text = lead + block
        insertText(text, replacementRange: selection)
        if let select, let found = text.range(of: select) {
            let offset = text.utf16.distance(from: text.startIndex, to: found.lowerBound)
            setSelectedRange(NSRange(location: selection.location + offset, length: select.utf16.count))
        }
    }

    @objc func insertTable(_ sender: Any?) {
        insertBlock("| Column | Column |\n| ------ | ------ |\n| Cell   |        |\n", select: "Column")
    }

    @objc func insertCallout(_ sender: NSMenuItem) {
        let kind = CalloutKind(rawValue: sender.representedObject as? String ?? "") ?? .note
        insertBlock("> [!\(kind.rawValue.uppercased())]\n> Text\n", select: "Text")
    }

    @objc func insertMathBlock(_ sender: Any?) {
        insertBlock("$$\ne^{i\\pi} + 1 = 0\n$$\n", select: "e^{i\\pi} + 1 = 0")
    }

    @objc func insertDiagram(_ sender: Any?) {
        insertBlock("```mermaid\ngraph LR\n  A[Draft] --> B[Review] --> C[Publish]\n```\n", select: "A[Draft] --> B[Review] --> C[Publish]")
    }

    /// Today as `yyyy-MM-dd`, over the selection.
    @objc func insertTodaysDate(_ sender: Any?) {
        replace(selectedRange(), with: Self.isoDay.string(from: Date()))
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The next free footnote number: one past the highest `[^n]`.
    static func nextFootnote(in text: String) -> Int {
        let numbers = text.matches(of: /\[\^(\d{1,6})\]/).compactMap { Int($0.1) }
        return (numbers.max() ?? 0) + 1
    }

    /// `[^n]` at the caret, its `[^n]: ` definition at the end of the
    /// note, and the caret there to write it.
    @objc func insertFootnote(_ sender: Any?) {
        let n = Self.nextFootnote(in: string)
        let selection = selectedRange()
        replace(NSRange(location: NSMaxRange(selection), length: 0), with: "[^\(n)]")
        let ns = string as NSString
        var tail = ns.length == 0 || ns.hasSuffix("\n") ? "" : "\n"
        // A blank line before the first definition; later ones stack.
        let lastLine = ns.substring(with: ns.lineRange(for: NSRange(location: max(0, ns.length - 1), length: 0)))
        if !lastLine.hasPrefix("[^") { tail += "\n" }
        replace(NSRange(location: ns.length, length: 0), with: tail + "[^\(n)]: ")
        scrollRangeToVisible(selectedRange())
    }

    /// Format › Clear Formatting: the selected lines lose their block
    /// marker and inline marks, links keep their text.
    @objc func clearFormatting(_ sender: Any?) {
        transformLines(Self.plainLine)
    }

    static func plainLine(_ line: String) -> String {
        var s = line.replacingOccurrences(
            of: #"^[ \t]*(?:>[ \t]?)*[ \t]*(?:#{1,6}[ \t]+|(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\](?:[ \t]+|$))?)?"#,
            with: "", options: .regularExpression)
        let inline: [(String, String)] = [
            (#"!?\[([^\]]*)\]\([^)\s]*\)"#, "$1"),
            (#"\*\*([^*]+)\*\*"#, "$1"), (#"__([^_]+)__"#, "$1"),
            (#"\*([^*]+)\*"#, "$1"), (#"(?<!\w)_([^_]+)_(?!\w)"#, "$1"),
            (#"~~([^~]+)~~"#, "$1"), (#"==([^=]+)=="#, "$1"), (#"`([^`]+)`"#, "$1"),
        ]
        for (pattern, template) in inline {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s
    }

    @objc func indentLines(_ sender: Any?) { shiftLines(right: true) }
    @objc func outdentLines(_ sender: Any?) { shiftLines(right: false) }

    private var isListContext: Bool {
        let selection = selectedRange()
        if selection.length > 0, (string as NSString).substring(with: selection).contains("\n") { return true }
        let ns = string as NSString
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: selection.location, length: 0)))
        let body = line.drop(while: { $0 == " " || $0 == "\t" })
        return SmartEditing.nextListMarker(for: String(body)) != nil
    }

    private func shiftLines(right: Bool) {
        transformLines { line in
            if right { return line.isEmpty ? line : "    " + line }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix(while: { $0 == " " }).count
            return String(line.dropFirst(min(spaces, 4)))
        }
    }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, !event.modifierFlags.contains(.shift), let cell = tableCell(at: point) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: cell, length: 0))
            scrollRangeToVisible(NSRange(location: cell, length: 0))
            return
        }
        if let index = characterIndex(at: point) {
            if event.modifierFlags.contains(.command),
               let url = textStorage?.attribute(.qmLink, at: index, effectiveRange: nil) as? URL {
                open(url)
                return
            }
            if toggleCheckbox(at: index) { return }
        }
        super.mouseDown(with: event)
    }

    /// A click on a table drawn as a grid: the start of the clicked
    /// cell's source text, so editing opens right where it was aimed.
    private func tableCell(at point: NSPoint) -> Int? {
        guard let grids = layoutManager as? HorizontalRuleLayoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = grids.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard let block = grids.renderedTable(at: min(index, storage.length - 1)),
              let (grid, origin) = grids.gridFrame(for: block),
              let hit = grid.cellIndex(at: CGPoint(x: local.x - origin.x, y: local.y - origin.y)) else { return nil }
        let ns = storage.string as NSString
        var rows: [NSRange] = []
        var location = block.location
        while location < NSMaxRange(block) {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let content = HorizontalRuleLayoutManager.lineContent(line, in: ns)
            if !TableEditing.isDelimiter(ns.substring(with: content)) { rows.append(content) }
            location = NSMaxRange(line)
        }
        guard hit.row < rows.count else { return nil }
        let cells = TableGrid.cellRanges(rows[hit.row], in: ns)
        guard !cells.isEmpty else { return rows[hit.row].location }
        return cells[min(hit.column, cells.count - 1)].location
    }

    /// The character under `point`, only when the point is on its glyph.
    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, textStorage?.length ?? 0 > 0 else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: inContainer, in: textContainer)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -2, dy: 0).contains(inContainer) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    @discardableResult
    func toggleCheckbox(at index: Int) -> Bool {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
        let line = ns.substring(with: lineRange)
        guard let box = Checkbox.boxRange(in: line) else { return false }
        let absolute = NSRange(location: lineRange.location + box.location, length: box.length)
        guard NSLocationInRange(index, absolute) else { return false }
        let mark = Checkbox.isChecked(line) ? " " : "x"
        replace(NSRange(location: absolute.location + 1, length: 1), with: mark, keepSelection: true)
        return true
    }

    private func open(_ url: URL) {
        if url.scheme == nil {
            // `[see](#setup)`: a heading in this note.
            if url.path.isEmpty, let fragment = url.fragment {
                jumpToHeading(fragment.removingPercentEncoding ?? fragment)
                return
            }
            guard let baseURL else { return }
            let path = url.path.removingPercentEncoding ?? url.path
            NoteLinks.open(URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL, from: window)
            return
        }
        NoteLinks.open(link: url, from: window)
    }

    /// Puts the caret on the heading whose anchor (as the preview makes them) is `id`.
    func jumpToHeading(_ id: String) {
        let wanted = id.lowercased()
        guard let heading = Headings.anchors(in: string).first(where: { $0.id.lowercased() == wanted }) else {
            NSSound.beep()
            return
        }
        setSelectedRange(NSRange(location: heading.location, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    // MARK: Format menu

    @objc func toggleBold(_ sender: Any?) { MarkdownWrap.toggle(in: self, marker: "**") }
    @objc func toggleItalic(_ sender: Any?) { MarkdownWrap.toggle(in: self, marker: "*") }
    @objc func toggleInlineCode(_ sender: Any?) { MarkdownWrap.toggle(in: self, marker: "`") }
    @objc func toggleStrikethrough(_ sender: Any?) { MarkdownWrap.toggle(in: self, marker: "~~") }

    @objc func insertLink(_ sender: Any?) {
        let selection = selectedRange()
        let label = (string as NSString).substring(with: selection)
        let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = clip.flatMap { $0.hasPrefix("http") && !$0.contains(" ") ? $0 : nil } ?? "url"
        let link = "[\(label)](\(url))"
        replace(selection, with: link)
        // Select what still needs typing: the label, or the URL placeholder.
        let labelLength = label.utf16.count
        if labelLength == 0 {
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        } else if url == "url" {
            setSelectedRange(NSRange(location: selection.location + labelLength + 3, length: 3))
        }
    }

    @objc func setHeading(_ sender: NSMenuItem) {
        let level = sender.tag
        transformLines { line in
            let stripped = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            return level == 0 ? stripped : String(repeating: "#", count: level) + " " + stripped
        }
    }

    @objc func toggleBulletList(_ sender: Any?) { toggleLinePrefix("- ", pattern: #"^(\s*)[-*+]\s(?!\[[ xX]\](?:\s|$))"#) }
    @objc func toggleTaskList(_ sender: Any?) { toggleLinePrefix("- [ ] ", pattern: #"^(\s*)[-*+]\s\[[ xX]\](?:\s|$)"#) }
    /// A quote goes in front of a list item rather than replacing it.
    @objc func toggleQuote(_ sender: Any?) { toggleLinePrefix("> ", pattern: #"^(\s*)>\s?"#, swapsMarkers: false) }

    @objc func toggleNumberedList(_ sender: Any?) {
        let pattern = #"^(\s*)\d+[.)][ \t]+(?:\[[ xX]\](?:[ \t]+|$))?"#
        let lines = selectedLines()
        let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allNumbered = !filled.isEmpty && filled.allSatisfy { $0.range(of: pattern, options: .regularExpression) != nil }
        var n = 0
        transformLines { line in
            if allNumbered { return line.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression) }
            // A blank line takes the marker only when it's the whole selection.
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty || lines.count == 1 else { return line }
            n += 1
            let bare = line.replacingOccurrences(of: #"^(\s*)(?:[-*+][ \t]+|\d+[.)][ \t]+)(?:\[[ xX]\](?:[ \t]+|$))?"#, with: "$1", options: .regularExpression)
            let indent = bare.prefix(while: { $0 == " " || $0 == "\t" })
            return indent + "\(n). " + bare.dropFirst(indent.count)
        }
    }

    /// Ticks or unticks the task on every selected line.
    @objc func toggleTaskDone(_ sender: Any?) {
        transformLines { Checkbox.toggling($0) ?? $0 }
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let atLineStart = selection.location == line.location
        insertText((atLineStart ? "" : "\n") + "---\n", replacementRange: selection)
    }

    @objc func insertCodeBlock(_ sender: Any?) {
        let selection = selectedRange()
        let inner = (string as NSString).substring(with: selection)
        let ns = string as NSString
        let atLineStart = selection.location == ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let lead = atLineStart ? "" : "\n"
        insertText(lead + "```\n" + inner + (inner.hasSuffix("\n") || inner.isEmpty ? "" : "\n") + "```\n", replacementRange: selection)
        if inner.isEmpty {
            setSelectedRange(NSRange(location: selection.location + lead.utf16.count + 4, length: 0))
        }
    }

    // MARK: Line helpers

    private func toggleLinePrefix(_ prefix: String, pattern: String, swapsMarkers: Bool = true) {
        let lines = selectedLines()
        let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let all = !filled.isEmpty && filled.allSatisfy { $0.range(of: pattern, options: .regularExpression) != nil }
        transformLines { line in
            if all { return line.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression) }
            // A blank line takes the marker only when it's the whole selection.
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty || lines.count == 1,
                  line.range(of: pattern, options: .regularExpression) == nil else { return line }
            // Swap another list marker rather than stacking two.
            let bare = swapsMarkers ? line.replacingOccurrences(
                of: #"^(\s*)(?:[-*+][ \t]+|\d+[.)][ \t]+)(?:\[[ xX]\](?:[ \t]+|$))?|^(\s*)>\s?"#, with: "$1$2", options: .regularExpression
            ) : line
            let indent = bare.prefix(while: { $0 == " " || $0 == "\t" })
            return indent + prefix + bare.dropFirst(indent.count)
        }
    }

    private var selectedLinesRange: NSRange {
        let ns = string as NSString
        var selection = selectedRange()
        // A selection ending at the start of a line doesn't include it.
        if selection.length > 0, NSMaxRange(selection) > 0,
           ns.character(at: NSMaxRange(selection) - 1) == 0x0A {
            selection.length -= 1
        }
        return ns.lineRange(for: selection)
    }

    private func selectedLines() -> [String] {
        let text = (string as NSString).substring(with: selectedLinesRange)
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    /// Rewrites each line the selection touches and selects the result.
    private func transformLines(_ transform: (String) -> String) {
        let range = selectedLinesRange
        let original = (string as NSString).substring(with: range)
        let trailingNewline = original.hasSuffix("\n")
        var lines = original.components(separatedBy: "\n")
        if trailingNewline { lines.removeLast() }
        let wasCaret = selectedRange().length == 0
        let caretOffsetFromEnd = NSMaxRange(range) - selectedRange().location
        var result = lines.map(transform).joined(separator: "\n")
        if trailingNewline { result += "\n" }
        guard result != original else { return }
        replace(range, with: result, keepSelection: false)
        let newLength = result.utf16.count
        if wasCaret && lines.count == 1 {
            let location = max(range.location, range.location + newLength - caretOffsetFromEnd)
            setSelectedRange(NSRange(location: location, length: 0))
        } else {
            setSelectedRange(NSRange(location: range.location, length: newLength - (trailingNewline ? 1 : 0)))
        }
    }

    func replace(_ range: NSRange, with text: String, keepSelection: Bool = false) {
        let selection = selectedRange()
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        if keepSelection {
            setSelectedRange(selection)
        } else {
            setSelectedRange(NSRange(location: range.location + text.utf16.count, length: 0))
        }
    }
}
