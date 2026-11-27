import AppKit

/// Edit › Copy As (Markdown, Rich Text, Plain Text), Paste as Markdown
/// and Paste as Table, and the conversions behind them. Rich text is
/// built from the renderer's HTML with every image and media source
/// taken out first, so converting a note never touches the network.
enum RichText {
    /// The rendered note, minus anything that could load: images become
    /// their alt text, media and embeds go, `src`, `srcset`, `poster`,
    /// `background` and `style` attributes go. Task boxes become ☐ / ☑.
    static func offlineHTML(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"(?is)<(video|audio|picture|iframe|object|embed|svg|math|style|script)\b.*?</\1\s*>"#,
                                   with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<input\b[^>]*\bchecked\b[^>]*>"#, with: "☑", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<input\b[^>]*>"#, with: "☐", options: .regularExpression)
        s = replace(s, #"(?is)<img\b((?:[^>"']|"[^"]*"|'[^']*')*)>"#) { attributes in
            guard let alt = attributes.range(of: #"(?i)\balt\s*=\s*"([^"]*)""#, options: .regularExpression) else { return "" }
            let match = String(attributes[alt])
            return String(match[match.index(after: match.firstIndex(of: "\"")!)...].dropLast())
        }
        s = s.replacingOccurrences(of: #"(?i)<(source|track|link|meta|base|img|image)\b[^>]*>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\s(?:src|srcset|poster|background|style|xlink:href)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>"']+)"#,
                                   with: "", options: .regularExpression)
        return s
    }

    private static func replace(_ text: String, _ pattern: String, _ transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out += transform(ns.substring(with: match.range(at: 1)))
            last = NSMaxRange(match.range)
        }
        return out + ns.substring(from: last)
    }

    /// A standalone page around `body`, styled for pasting into Mail,
    /// Pages or Word. Our own CSS only, nothing it could fetch.
    static func document(body: String, title: String = "") -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(MarkdownHTML.escape(title))</title><style>
        body { font-family: "Helvetica Neue", Helvetica, Arial, sans-serif; font-size: 13px; line-height: 1.45; }
        h1 { font-size: 22px; } h2 { font-size: 18px; } h3 { font-size: 15px; } h4, h5, h6 { font-size: 13px; }
        code, pre { font-family: Menlo, Monaco, monospace; font-size: 12px; }
        pre { background: #f5f5f5; padding: 6px; }
        blockquote { color: #555555; margin-left: 12px; padding-left: 8px; border-left: 3px solid #dddddd; }
        table { border-collapse: collapse; } th, td { border: 1px solid #cccccc; padding: 3px 6px; } th { background: #f2f2f2; }
        mark { background: #fff3a3; }
        </style></head><body>
        \(offlineHTML(body))
        </body></html>
        """
    }

    /// Markdown as an attributed string, through the renderer. Main
    /// thread only (the HTML importer runs WebKit).
    @MainActor
    static func attributed(_ markdown: String, title: String = "", properties: Bool = false) -> NSAttributedString? {
        let page = document(body: MarkdownHTML.render(markdown, properties: properties), title: title)
        guard let data = page.data(using: .utf8) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )
    }

    /// The pasteboard's HTML as a string: plain HTML first, then the
    /// main page of a web archive (Safari), then RTF turned into HTML.
    @MainActor
    static func html(from board: NSPasteboard) -> String? {
        if let html = board.string(forType: .html), !html.isEmpty { return html }
        if let data = board.data(forType: NSPasteboard.PasteboardType("Apple Web Archive pasteboard type")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let main = plist["WebMainResource"] as? [String: Any],
           let bytes = main["WebResourceData"] as? Data,
           let html = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) {
            return html
        }
        for type in [NSPasteboard.PasteboardType.rtf, .rtfd] {
            guard let data = board.data(forType: type) else { continue }
            let kind: NSAttributedString.DocumentType = type == .rtf ? .rtf : .rtfd
            guard let text = try? NSAttributedString(data: data, options: [.documentType: kind], documentAttributes: nil),
                  let html = try? text.data(from: NSRange(location: 0, length: text.length),
                                            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) else { continue }
            return String(data: html, encoding: .utf8)
        }
        return nil
    }
}

/// Markdown with its marks taken out, for Copy As › Plain Text:
/// no `#`, `**` or link URLs; bullets become “• ”, tasks “☐ ” / “☑ ”.
enum PlainText {
    static func from(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        let skip = MarkdownHTML.frontMatterEnd(lines).map { $0 + 1 } ?? 0
        var out: [String] = []
        var fence: MarkdownHTML.Fence?
        for (index, line) in lines.enumerated() where index >= skip {
            if let open = fence {
                if MarkdownHTML.closes(line, open) { fence = nil } else { out.append(line) }
                continue
            }
            if let opening = MarkdownHTML.openingFence(line) { fence = opening; continue }
            if let converted = block(line, previous: out.last) { out.append(converted) }
        }
        return out.joined(separator: "\n")
    }

    private static func block(_ raw: String, previous: String?) -> String? {
        var line = raw
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Setext underlines and table delimiter rows carry no text.
        if let previous, !previous.trimmingCharacters(in: .whitespaces).isEmpty,
           !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "=" }) || (trimmed.count >= 2 && trimmed.allSatisfy({ $0 == "-" })) {
            return nil
        }
        if trimmed.contains("-"), trimmed.contains("|") || trimmed.hasPrefix(":"),
           trimmed.range(of: #"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$"#, options: .regularExpression) != nil {
            return nil
        }
        if trimmed.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil { return "———" }
        // Reference definitions are where URLs live: they go.
        if line.range(of: #"^ {0,3}\[[^\]^][^\]]*\]:\s*\S+"#, options: .regularExpression) != nil { return nil }
        // Quotes: every `>` level.
        while let quote = line.range(of: #"^\s*>\s?"#, options: .regularExpression) { line.removeSubrange(quote) }
        line = line.replacingOccurrences(of: #"^\[!([A-Za-z]+)\][+-]?\s*"#, with: "$1 ", options: .regularExpression)
        // Headings.
        if let heading = line.range(of: #"^ {0,3}#{1,6}(\s+|$)"#, options: .regularExpression) {
            line.removeSubrange(heading)
            line = line.replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
        }
        // Lists: tasks, then bullets. Numbers stay.
        line = line.replacingOccurrences(of: #"^(\s*)[-*+]\s+\[[xX]\](\s+|$)"#, with: "$1☑ ", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^(\s*)[-*+]\s+\[ \](\s+|$)"#, with: "$1☐ ", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^(\s*)[-*+]\s+"#, with: "$1• ", options: .regularExpression)
        // Footnote definitions.
        line = line.replacingOccurrences(of: #"^ {0,3}\[\^([^\]\s]+)\]:\s?"#, with: "[$1] ", options: .regularExpression)
        // Table rows: cells separated by tabs.
        let rowTrim = line.trimmingCharacters(in: .whitespaces)
        if rowTrim.hasPrefix("|") {
            var cells = rowTrim.components(separatedBy: "|")
            cells.removeFirst()
            if rowTrim.hasSuffix("|"), !rowTrim.hasSuffix("\\|") { cells.removeLast() }
            line = cells.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\t")
        }
        return inline(line)
    }

    static func inline(_ text: String) -> String {
        var s = text
        // Code spans first, kept aside so marks inside them survive.
        var codes: [String] = []
        s = replace(s, #"(`+)(.+?)\1"#) { m in
            codes.append(m[2].trimmingCharacters(in: .whitespaces))
            return "\u{E000}\(codes.count - 1)\u{E001}"
        }
        s = replace(s, #"!\[([^\]]*)\]\([^)]*\)"#) { $0[1] }
        s = replace(s, #"!\[([^\]]*)\]\[[^\]]*\]"#) { $0[1] }
        s = replace(s, #"\[\^([^\]\s]+)\]"#) { "[\($0[1])]" }
        s = replace(s, #"\[([^\]]+)\]\((?:<[^>]*>|[^)\s]*)(?:\s+"[^"]*")?\)"#) { $0[1] }
        s = replace(s, #"\[([^\]]+)\]\[[^\]]*\]"#) { $0[1] }
        s = replace(s, #"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]"#) { $0[2].isEmpty ? $0[1] : $0[2] }
        s = replace(s, #"<((?:https?|mailto):[^>\s]+)>"#) { $0[1] }
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"</?[A-Za-z][^>]*>"#, with: "", options: .regularExpression)
        s = replace(s, #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#) { $0[2] }
        s = replace(s, #"~~(?=\S)(.+?)(?<=\S)~~"#) { $0[1] }
        s = replace(s, #"==(?=\S)(.+?)(?<=\S)=="#) { $0[1] }
        s = replace(s, #"(?<![\\\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])"#) { $0[1] }
        s = replace(s, #"(?<![\\\w])_(?=\S)(.+?)(?<=\S)_(?!\w)"#) { $0[1] }
        s = replace(s, #"\\([\\`*_{}\[\]()#+\-.!|<>~=])"#) { $0[1] }
        s = replace(s, "\u{E000}(\\d+)\u{E001}") { codes[Int($0[1]) ?? 0] }
        return s
    }

    /// Regex replace with capture groups (missing groups are "").
    private static func replace(_ text: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { i -> String in
                let r = match.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            out += transform(groups)
            last = NSMaxRange(match.range)
        }
        return out + ns.substring(from: last)
    }
}

// MARK: - Edit menu actions

extension MarkdownTextView {
    /// The selection's source, or the whole note when nothing is selected.
    private var copySource: String {
        let range = selectedRange()
        return range.length > 0 ? (string as NSString).substring(with: range) : string
    }

    @objc func copyAsMarkdown(_ sender: Any?) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(copySource, forType: .string)
    }

    @objc func copyAsRichText(_ sender: Any?) {
        let source = copySource
        let board = NSPasteboard.general
        board.clearContents()
        let html = RichText.document(body: MarkdownHTML.render(source, properties: false))
        if let text = RichText.attributed(source),
           let rtf = text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]) {
            board.setData(rtf, forType: .rtf)
        }
        board.setString(html, forType: .html)
        board.setString(PlainText.from(source), forType: .string)
    }

    @objc func copyAsPlainText(_ sender: Any?) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(PlainText.from(copySource), forType: .string)
    }

    /// Edit › Paste as Markdown: HTML or rich text on the pasteboard,
    /// converted. Plain text pastes as it is.
    @objc func pasteAsMarkdown(_ sender: Any?) {
        let board = NSPasteboard.general
        if let html = RichText.html(from: board) {
            insertBlock(HTMLToMarkdown.convert(html), inline: true)
        } else if let text = board.string(forType: .string) {
            replace(selectedRange(), with: text)
        } else {
            NSSound.beep()
        }
    }

    /// Edit › Paste as Table: CSV or TSV text as a Markdown table.
    @objc func pasteAsTable(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string),
              let rows = MarkdownTable.delimitedRows(text) else { return NSSound.beep() }
        insertBlock(MarkdownTable.make(rows), inline: false)
    }

    /// For ⌘V: a spreadsheet's tab-separated cells paste as a table, and
    /// HTML with no plain text beside it pastes as Markdown. True when
    /// it handled the paste.
    func pasteConverted(from board: NSPasteboard) -> Bool {
        if let text = board.string(forType: .string) {
            guard !isInFencedCode(selectedRange().location), let rows = MarkdownTable.tabSeparatedRows(text) else { return false }
            insertBlock(MarkdownTable.make(rows), inline: false)
            return true
        }
        guard let html = RichText.html(from: board) else { return false }
        insertBlock(HTMLToMarkdown.convert(html), inline: true)
        return true
    }

    /// Puts `markdown` over the selection. A block (a table) gets a line
    /// of its own; `inline` text that is a single line goes in as is.
    private func insertBlock(_ markdown: String, inline: Bool) {
        guard !markdown.isEmpty else { return NSSound.beep() }
        let selection = selectedRange()
        let ns = string as NSString
        if inline, !markdown.contains("\n") { return replace(selection, with: markdown) }
        var text = markdown
        if selection.location > 0, ns.character(at: selection.location - 1) != 0x0A { text = "\n\n" + text }
        let end = NSMaxRange(selection)
        if end < ns.length, ns.character(at: end) != 0x0A { text += "\n\n" } else if end >= ns.length || !inline { text += "\n" }
        replace(selection, with: text)
    }

    private func isInFencedCode(_ location: Int) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let line = (string as NSString).lineRange(for: NSRange(location: min(location, storage.length), length: 0))
        guard line.location < storage.length else { return false }
        return storage.attribute(.qmCodeBlock, at: line.location, effectiveRange: nil) != nil
    }
}
