import AppKit
import UniformTypeIdentifiers

/// A small CommonMark-ish renderer for the preview and HTML export:
/// headings (ATX and setext), paragraphs, nested lists and task lists,
/// fenced and indented code, quotes, rules, GFM tables, raw HTML
/// blocks, and inline code, emphasis, strikethrough, links, images
/// and bare URLs; plus GitHub callouts, `$…$`/`$$…$$` math and
/// ```mermaid diagrams (typeset in the page by KaTeX and Mermaid), and
/// highlighted code. Not a full spec implementation; good enough to read.
///
/// Notes come from anywhere, so raw HTML is sanitised: nothing in a
/// note can run script or reach outside the page.
enum MarkdownHTML {
    /// State threaded through one render: the heading ids handed out.
    final class Context {
        var ids: Set<String> = []
        let interactive: Bool
        init(interactive: Bool) { self.interactive = interactive }
    }

    /// With `interactive`, task checkboxes are live and carry their
    /// source line as `data-task` (the preview); otherwise they're disabled.
    static func render(_ markdown: String, interactive: Bool = false) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = stripControls(normalized).components(separatedBy: "\n")
        var origin = Array(lines.indices)
        // YAML front matter is metadata for other tools, not prose.
        if let end = frontMatterEnd(lines) {
            lines.removeFirst(end + 1)
            origin.removeFirst(end + 1)
        }
        return renderBlocks(lines, origin, tight: false, context: Context(interactive: interactive))
    }

    /// Index of the closing `---` of a front matter block that opens the
    /// note (`---`, then `key: value` lines), or nil when there's none.
    static func frontMatterEnd(_ lines: [String]) -> Int? {
        guard lines.count > 2, lines[0] == "---",
              lines[1].range(of: #"^[A-Za-z0-9_-]+:"#, options: .regularExpression) != nil else { return nil }
        for i in 2..<min(lines.count, 300) where lines[i] == "---" || lines[i] == "..." { return i }
        return nil
    }

    // MARK: Blocks

    private static let atxPattern = regex(#"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$"#)
    private static let thematicPattern = regex(#"^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$"#)
    private static let listPattern = regex(#"^([ \t]*)([-*+]|(\d{1,9})[.)])([ \t]+|$)(.*)$"#)
    private static let htmlBlockPattern = regex(#"^[ \t]*<(?:/?[A-Za-z]|!)"#)

    /// `origin[k]` is the source line of `lines[k]`, so a task can name
    /// the line it came from however deeply it's nested.
    private static func renderBlocks(_ lines: [String], _ origin: [Int], tight: Bool, context: Context) -> String {
        var out = ""
        var paragraph: [String] = []
        var i = 0

        func flush() {
            guard !paragraph.isEmpty else { return }
            // Two trailing spaces end a line with a break, like a backslash.
            let text = paragraph.enumerated().map { index, original -> String in
                var line = original.trimmingCharacters(in: .whitespaces)
                if index < paragraph.count - 1, original.hasSuffix("  "), !line.hasSuffix("\\") { line += "\\" }
                return line
            }.joined(separator: "\n")
            let body = inline(text)
            out += tight ? body + "\n" : "<p>\(body)</p>\n"
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { flush(); i += 1; continue }

            // Fenced code, closed only by the same fence or a longer one.
            if let fence = openingFence(line) {
                flush()
                var code: [String] = []
                i += 1
                while i < lines.count, !closes(lines[i], fence) {
                    code.append(lines[i]); i += 1
                }
                i += 1
                let lang = fence.info.components(separatedBy: .whitespaces)[0]
                let source = code.joined(separator: "\n")
                switch lang.lowercased() {
                case "mermaid":
                    out += "<pre class=\"mermaid\">\(escape(source))</pre>\n"
                case "math":
                    out += "<div class=\"math math-display\">\(escape(source))</div>\n"
                default:
                    let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
                    out += "<pre><code\(cls)>\(SyntaxHighlighter.html(source, language: lang, escape: escape))</code></pre>\n"
                }
                continue
            }

            // Display math: `$$` (or LaTeX's `\[`) on its own line up to
            // the closing one, or all on one line. A line merely starting
            // with an escaped bracket (`\[draft] …`) stays text.
            if let (open, close) = [("$$", "$$"), ("\\[", "\\]")].first(where: { trimmed.hasPrefix($0.0) }),
               open == "$$" || trimmed == open || trimmed.hasSuffix(close) {
                flush()
                var tex = String(trimmed.dropFirst(open.count))
                if tex.hasSuffix(close) {
                    tex.removeLast(close.count)
                    i += 1
                } else {
                    var body: [String] = tex.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [tex]
                    i += 1
                    while i < lines.count {
                        let t = lines[i].trimmingCharacters(in: .whitespaces)
                        i += 1
                        if t.hasSuffix(close) {
                            let last = String(t.dropLast(close.count))
                            if !last.isEmpty { body.append(last) }
                            break
                        }
                        body.append(lines[i - 1])
                    }
                    tex = body.joined(separator: "\n")
                }
                out += "<div class=\"math math-display\">\(escape(tex))</div>\n"
                continue
            }

            // Setext heading under an open paragraph.
            if !paragraph.isEmpty, trimmed.allSatisfy({ $0 == "=" }) || (trimmed.allSatisfy({ $0 == "-" }) && trimmed.count >= 2) {
                let level = trimmed.hasPrefix("=") ? 1 : 2
                let title = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                paragraph.removeAll()
                out += heading(level: level, title: title, context: context)
                i += 1
                continue
            }

            // ATX heading.
            if let match = groups(atxPattern, line) {
                flush()
                out += heading(level: match[1].count, title: match[2], context: context)
                i += 1
                continue
            }

            // Thematic break.
            if groups(thematicPattern, line) != nil {
                flush()
                out += "<hr>\n"
                i += 1
                continue
            }

            // Block quote.
            if trimmed.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                var quotedOrigin: [Int] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var rest = t.dropFirst()
                    if rest.first == " " { rest = rest.dropFirst() }
                    quoted.append(String(rest))
                    quotedOrigin.append(origin[i])
                    i += 1
                }
                // GitHub callout: `> [!TIP]` on the first line.
                if let first = quoted.first,
                   let match = first.firstMatch(of: /^\s*\[!([A-Za-z]+)\]\s*(.*)$/),
                   let kind = CalloutKind(marker: String(match.1)) {
                    var body = Array(quoted.dropFirst())
                    var bodyOrigin = Array(quotedOrigin.dropFirst())
                    let rest = String(match.2)
                    if !rest.isEmpty { body.insert(rest, at: 0); bodyOrigin.insert(quotedOrigin[0], at: 0) }
                    out += "<div class=\"callout callout-\(kind.rawValue)\">\n<p class=\"callout-title\">\(kind.title)</p>\n"
                        + renderBlocks(body, bodyOrigin, tight: false, context: context) + "</div>\n"
                    continue
                }
                out += "<blockquote>\n\(renderBlocks(quoted, quotedOrigin, tight: false, context: context))</blockquote>\n"
                continue
            }

            // Table: a header row, then a delimiter row with as many cells.
            if line.contains("|"), i + 1 < lines.count, lines[i + 1].contains("|"), isTableDelimiter(lines[i + 1]),
               cells(line).count == cells(lines[i + 1]).count {
                flush()
                let aligns = cells(lines[i + 1]).map { cell -> String in
                    let c = cell.trimmingCharacters(in: .whitespaces)
                    switch (c.hasPrefix(":"), c.hasSuffix(":")) {
                    case (true, true): return " style=\"text-align:center\""
                    case (false, true): return " style=\"text-align:right\""
                    case (true, false): return " style=\"text-align:left\""
                    default: return ""
                    }
                }
                func row(_ line: String, tag: String) -> String {
                    let values = cells(line)
                    let items = aligns.indices.map { index -> String in
                        let value = index < values.count ? values[index].trimmingCharacters(in: .whitespaces) : ""
                        return "<\(tag)\(aligns[index])>\(inline(value))</\(tag)>"
                    }
                    return "<tr>\(items.joined())</tr>\n"
                }
                out += "<table>\n<thead>\n" + row(line, tag: "th") + "</thead>\n<tbody>\n"
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    out += row(lines[i], tag: "td"); i += 1
                }
                out += "</tbody>\n</table>\n"
                continue
            }

            // Indented code (not inside a paragraph), before lists: four
            // spaces in, `- x` is code, not an item.
            if paragraph.isEmpty, line.hasPrefix("    ") || line.hasPrefix("\t") {
                var code: [String] = []
                while i < lines.count, lines[i].hasPrefix("    ") || lines[i].hasPrefix("\t") || lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    let l = lines[i]
                    code.append(l.hasPrefix("\t") ? String(l.dropFirst()) : String(l.dropFirst(min(4, l.count))))
                    i += 1
                }
                while code.last?.isEmpty == true { code.removeLast() }
                out += "<pre><code>\(escape(code.joined(separator: "\n")))</code></pre>\n"
                continue
            }

            // List.
            if listItem(line) != nil {
                flush()
                let (html, next) = renderList(lines, origin, from: i, context: context)
                out += html
                i = next
                continue
            }

            // Raw HTML block, sanitised.
            if paragraph.isEmpty, groups(htmlBlockPattern, line) != nil {
                var block: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    block.append(lines[i]); i += 1
                }
                out += sanitize(block.joined(separator: "\n")) + "\n"
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flush()
        return out
    }

    private struct ListItem {
        let indent: Int
        let ordered: Bool
        let start: Int
        /// Column where the item's text starts.
        let contentColumn: Int
        let text: String
    }

    private static func listItem(_ line: String) -> ListItem? {
        guard let match = groups(listPattern, line) else { return nil }
        let indent = width(match[1])
        let spacing = width(match[4])
        return ListItem(
            indent: indent,
            ordered: !match[3].isEmpty,
            start: Int(match[3]) ?? 1,
            contentColumn: indent + match[2].count + max(1, min(spacing, 4)),
            text: match[5]
        )
    }

    private static func renderList(_ lines: [String], _ origin: [Int], from start: Int, context: Context) -> (String, Int) {
        guard let first = listItem(lines[start]) else { return ("", start + 1) }
        var items: [[String]] = []
        var itemOrigins: [[Int]] = []
        var i = start
        var sawBlank = false
        var loose = false
        func append(_ text: String, _ line: Int) {
            items[items.count - 1].append(text)
            itemOrigins[itemOrigins.count - 1].append(line)
        }
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                sawBlank = true
                i += 1
                continue
            }
            if let item = listItem(line), item.indent <= first.indent + 1 {
                guard item.ordered == first.ordered else { break }
                if sawBlank, !items.isEmpty { loose = true }
                sawBlank = false
                items.append([item.text])
                itemOrigins.append([origin[i]])
                i += 1
                continue
            }
            let indent = width(String(line.prefix(while: { $0 == " " || $0 == "\t" })))
            if indent > first.indent, !items.isEmpty {
                if sawBlank { append("", origin[i - 1]); loose = true }
                sawBlank = false
                // Dedent continuation lines to the item's content column.
                var dropped = 0
                var index = line.startIndex
                while index < line.endIndex, dropped < first.contentColumn, line[index] == " " || line[index] == "\t" {
                    dropped += line[index] == "\t" ? 4 : 1
                    index = line.index(after: index)
                }
                append(String(line[index...]), origin[i])
                i += 1
                continue
            }
            // A lazy continuation of the last item's paragraph.
            if !sawBlank, !items.isEmpty, listItem(line) == nil,
               !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                append(line.trimmingCharacters(in: .whitespaces), origin[i])
                i += 1
                continue
            }
            break
        }
        // Back off over trailing blanks so the caller sees them.
        while i > start, lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty { i -= 1 }

        let tag = first.ordered ? "ol" : "ul"
        let startAttr = first.ordered && first.start != 1 ? " start=\"\(first.start)\"" : ""
        let hasTasks = items.contains { task($0.first ?? "") != nil }
        var out = "<\(tag)\(startAttr)\(hasTasks ? " class=\"contains-task-list\"" : "")>\n"
        for (k, var body) in items.enumerated() {
            var prefix = ""
            var cls = ""
            if let state = task(body[0]) {
                body[0] = state.rest
                let attrs = context.interactive ? " data-task=\"\(itemOrigins[k][0])\"" : " disabled"
                prefix = "<input type=\"checkbox\"\(attrs)\(state.checked ? " checked" : "")> "
                cls = " class=\"task-list-item\""
            }
            let inner = renderBlocks(body, itemOrigins[k], tight: !loose, context: context)
                .trimmingCharacters(in: .newlines)
            out += "<li\(cls)>\(prefix)\(inner)</li>\n"
        }
        return (out + "</\(tag)>\n", i)
    }

    /// `[ ]` or `[x]` opening an item's text, then a space, a tab or nothing.
    private static func task(_ text: String) -> (checked: Bool, rest: String)? {
        let scalars = Array(text.unicodeScalars.prefix(4))
        guard scalars.count >= 3, scalars[0] == "[", scalars[2] == "]" else { return nil }
        let checked: Bool
        switch scalars[1] {
        case " ": checked = false
        case "x", "X": checked = true
        default: return nil
        }
        if scalars.count == 4, scalars[3] != " ", scalars[3] != "\t" { return nil }
        return (checked, String(text.unicodeScalars.dropFirst(scalars.count)))
    }

    private static func heading(level: Int, title: String, context: Context) -> String {
        let base = slug(title)
        var id = base
        var n = 0
        while context.ids.contains(id) { n += 1; id = "\(base)-\(n)" }
        context.ids.insert(id)
        return "<h\(level) id=\"\(escape(id))\">\(inline(title))</h\(level)>\n"
    }

    /// A heading's anchor: lowercase words joined by dashes, GitHub style.
    static func slug(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s_-]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
    }

    struct Fence {
        let character: Character
        let length: Int
        let info: String
    }

    /// A line opening fenced code: three or more backticks or tildes,
    /// indented at most three spaces.
    static func openingFence(_ line: String) -> Fence? {
        let indent = line.prefix(while: { $0 == " " }).count
        guard indent <= 3 else { return nil }
        let rest = line.dropFirst(indent)
        guard let c = rest.first, c == "`" || c == "~" else { return nil }
        let length = rest.prefix(while: { $0 == c }).count
        guard length >= 3 else { return nil }
        let info = rest.dropFirst(length).trimmingCharacters(in: .whitespaces)
        if c == "`", info.contains("`") { return nil }
        return Fence(character: c, length: length, info: info)
    }

    /// Does `line` close `fence`? The same character, at least as many,
    /// and nothing after them.
    static func closes(_ line: String, _ fence: Fence) -> Bool {
        let indent = line.prefix(while: { $0 == " " }).count
        guard indent <= 3 else { return false }
        let rest = line.dropFirst(indent)
        let length = rest.prefix(while: { $0 == fence.character }).count
        return length >= fence.length && rest.dropFirst(length).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        TableEditing.isDelimiter(line)
    }

    private static func cells(_ line: String) -> [String] {
        TableEditing.cells(line).map { $0.replacingOccurrences(of: "\\|", with: "|") }
    }

    private static func width(_ whitespace: String) -> Int {
        whitespace.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    // MARK: Inline

    static func inline(_ text: String) -> String {
        // Finished HTML is parked behind numbered placeholders so later
        // passes can't touch it.
        var stash: [String] = []
        func keep(_ html: String) -> String {
            stash.append(html)
            return "\u{E000}\(stash.count - 1)\u{E001}"
        }

        var s = text
        // The placeholder characters themselves, if a note has them, become entities.
        s = replace(s, "[\u{E000}-\u{E002}]") { m in
            keep("&#x\(String(m[0].unicodeScalars.first?.value ?? 0xFFFD, radix: 16));")
        }
        // Escaped dollars and backticks first, so they open nothing.
        s = replace(s, #"\\([$`])"#) { m in keep(escape(m[1])) }
        // Code spans: everything inside is literal.
        s = codeSpans(s) { code in
            keep("<code>\(escape(code.trimmingCharacters(in: .init(charactersIn: " "))))</code>")
        }
        // Math, literal too: KaTeX typesets it in the page.
        // LaTeX's own delimiters too, as chat assistants write them;
        // `\[…\]` only when it holds TeX, so `\[draft\]` stays a bracket.
        s = replace(s, #"(?s)\\\[(.+?)\\\]"#) { m in
            m[1].contains(where: { "\\^_=".contains($0) })
                ? keep("<span class=\"math math-display\">\(escape(m[1]))</span>") : m[0]
        }
        s = replace(s, #"(?s)\\\((.+?)\\\)"#) { m in keep("<span class=\"math\">\(escape(m[1]))</span>") }
        s = replace(s, #"(?s)\$\$(.+?)\$\$"#) { m in keep("<span class=\"math math-display\">\(escape(m[1]))</span>") }
        s = replace(s, #"(?<![\w$])\$([^\s$](?:[^$\n]*?[^\s$\\])?)\$(?![\d$])"#) { m in
            keep("<span class=\"math\">\(escape(m[1]))</span>")
        }
        // Other backslash escapes.
        s = replace(s, #"\\([\\*_{}\[\]()#+\-.!|~<>])"#) { m in keep(escape(m[1])) }
        // A backslash at the end of a line is a hard break.
        s = replace(s, "\\\\\n") { _ in keep("<br>\n") }
        // Autolinks.
        s = replace(s, #"<(https?://[^>\s]+)>"#) { m in
            keep("<a href=\"\(escape(safeURL(m[1])))\">\(escape(m[1]))</a>")
        }
        // Inline HTML tags pass through, sanitised.
        s = replace(s, #"</?[A-Za-z][A-Za-z0-9-]*(?:[^<>"']|"[^"]*"|'[^']*')*>"#) { m in keep(sanitize(m[0])) }
        s = escape(s)
        // Character references the note wrote (`&copy;`, `&#233;`) stay references.
        s = replace(s, entityPattern) { m in "&\(m[1]);" }
        // Images, then links; labels get emphasis but no nested links.
        s = links(s, keep)
        s = replace(s, #"(?<![\"'=])\bhttps?://[^\s<]*[^\s<.,;:!?)\]'\"*]"#) { m in
            keep("<a href=\"\(m[0])\">\(m[0])</a>")
        }
        s = emphasis(s)
        // Restore stashed fragments; they may nest, so repeat (a few
        // levels at most: links hold emphasis that holds code).
        var passes = 0
        while s.contains("\u{E000}"), passes < 8 {
            s = replace(s, "\u{E000}(\\d+)\u{E001}") { m in
                guard let index = Int(m[1]), stash.indices.contains(index) else { return "" }
                return stash[index]
            }
            passes += 1
        }
        return s
    }

    /// Code spans by scanning, not a regex: a run of backticks opens a
    /// span that the next run of the same length closes. Runs are
    /// indexed by length, so a line of unmatched backticks stays linear.
    private static func codeSpans(_ s: String, _ span: (String) -> String) -> String {
        let u = Array(s.utf16)
        guard u.contains(0x60) else { return s }
        var runs: [(start: Int, length: Int)] = []
        var i = 0
        while i < u.count {
            guard u[i] == 0x60 else { i += 1; continue }
            let start = i
            while i < u.count, u[i] == 0x60 { i += 1 }
            runs.append((start, i - start))
        }
        var byLength: [Int: [Int]] = [:]
        for (index, run) in runs.enumerated() { byLength[run.length, default: []].append(index) }
        var cursor: [Int: Int] = [:]
        func text(_ a: Int, _ b: Int) -> String { String(decoding: u[a..<b], as: UTF16.self) }
        var out = ""
        var pos = 0
        var r = 0
        while r < runs.count {
            let run = runs[r]
            let same = byLength[run.length] ?? []
            var c = cursor[run.length] ?? 0
            while c < same.count, same[c] <= r { c += 1 }
            cursor[run.length] = c
            guard c < same.count else { r += 1; continue }
            let close = runs[same[c]]
            out += text(pos, run.start)
            out += span(text(run.start + run.length, close.start).replacingOccurrences(of: "\n", with: " "))
            pos = close.start + close.length
            r = same[c] + 1
        }
        return out + text(pos, u.count)
    }

    /// `[label](url "title")` and `![alt](url)`, scanned over escaped
    /// text. The URL may hold balanced parentheses (`…/Foo_(bar)`).
    /// Each bracket looks up the next `]` and `[` in a table, so long
    /// runs of brackets stay linear; URLs and titles are capped.
    private static func links(_ s: String, _ keep: (String) -> String) -> String {
        let u = Array(s.utf16)
        guard u.contains(0x5B) else { return s }
        var nextClose = Array(repeating: Int.max, count: u.count + 1)
        var nextOpen = Array(repeating: Int.max, count: u.count + 1)
        for k in stride(from: u.count - 1, through: 0, by: -1) {
            nextClose[k] = u[k] == 0x5D ? k : nextClose[k + 1]
            nextOpen[k] = u[k] == 0x5B ? k : nextOpen[k + 1]
        }
        let quot = Array("&quot;".utf16)
        func has(_ needle: [UInt16], at k: Int) -> Bool {
            guard k + needle.count <= u.count else { return false }
            for (n, c) in needle.enumerated() where u[k + n] != c { return false }
            return true
        }
        func text(_ a: Int, _ b: Int) -> String { String(decoding: u[a..<b], as: UTF16.self) }
        var out = ""
        var pos = 0
        var i = 0
        while i < u.count {
            guard u[i] == 0x5B else { i += 1; continue }
            let image = i > pos && u[i - 1] == 0x21
            let close = nextClose[i + 1]
            // An inner `[` gets its own try.
            guard close != .max, nextOpen[i + 1] > close, close + 1 < u.count, u[close + 1] == 0x28,
                  image || close > i + 1 else { i += 1; continue }
            var j = close + 2
            while j < u.count, u[j] == 0x20 { j += 1 }
            let destStart = j
            var depth = 0
            while j < u.count, j - destStart < 4096 {
                let c = u[j]
                if c == 0x20 || c == 0x0A || c == 0x09 { break }
                if c == 0x28 { depth += 1 } else if c == 0x29 { if depth == 0 { break }; depth -= 1 }
                j += 1
            }
            let destEnd = j
            guard destEnd > destStart, depth == 0 else { i += 1; continue }
            while j < u.count, u[j] == 0x20 || u[j] == 0x0A { j += 1 }
            var title = ""
            if has(quot, at: j) {
                var k = j + quot.count
                while k < u.count, k - j < 1024, !has(quot, at: k) { k += 1 }
                guard has(quot, at: k) else { i += 1; continue }
                title = text(j + quot.count, k)
                j = k + quot.count
                while j < u.count, u[j] == 0x20 { j += 1 }
            }
            guard j < u.count, u[j] == 0x29 else { i += 1; continue }
            let label = text(i + 1, close)
            let destination = safeURL(text(destStart, destEnd))
            let titleAttr = title.isEmpty ? "" : " title=\"\(title)\""
            out += text(pos, image ? i - 1 : i)
            out += image
                ? keep("<img src=\"\(destination)\" alt=\"\(label)\"\(titleAttr)>")
                : keep("<a href=\"\(destination)\"\(titleAttr)>\(emphasis(label))</a>")
            pos = j + 1
            i = j + 1
        }
        return out + text(pos, u.count)
    }

    private static func emphasis(_ text: String) -> String {
        var s = text
        s = replace(s, #"\*\*\*(?=\S)([\s\S]*?\S)\*\*\*"#) { m in "<em><strong>\(m[1])</strong></em>" }
        s = replace(s, #"\*\*(?=\S)([\s\S]*?\S)\*\*"#) { m in "<strong>\(m[1])</strong>" }
        s = replace(s, #"(?<![\w])__(?=\S)([\s\S]*?\S)__(?![\w])"#) { m in "<strong>\(m[1])</strong>" }
        s = replace(s, #"\*(?=[^\s*])([^*]*?[^\s*])\*"#) { m in "<em>\(m[1])</em>" }
        s = replace(s, #"(?<![\w])_(?=[^\s_])([^_]*?[^\s_])_(?![\w])"#) { m in "<em>\(m[1])</em>" }
        s = replace(s, #"~~(?=\S)([\s\S]*?\S)~~"#) { m in "<del>\(m[1])</del>" }
        s = replace(s, #"==(?=\S)([^=]*?\S)=="#) { m in "<mark>\(m[1])</mark>" }
        return s
    }

    /// NUL and other C0 controls aren't valid in HTML; tabs and newlines stay.
    private static func stripControls(_ text: String) -> String {
        guard text.utf8.contains(where: { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A }) else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" }))
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let entityPattern = regex("&amp;(#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});")

    // MARK: Sanitising

    /// Elements dropped with everything inside them.
    private static let containers = "script|style|iframe|frame|frameset|object|embed|applet|noscript|template|textarea|title|xmp|noembed|noframes|svg|math"
    /// Elements dropped, keeping what's between their tags.
    private static let dropped = containers + "|base|meta|link|form|input|button|select|option|portal|param|source|track"

    private static let containerPattern = regex("(?is)<(\(containers))\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>.*?</\\1\\s*>")
    private static let tokenPattern = regex(#"(<!--[\s\S]*?-->)|(</?)([A-Za-z][A-Za-z0-9:-]*)((?:[^>"']|"[^"]*"|'[^']*')*)>|(<)"#)
    private static let droppedPattern = regex("(?i)^(?:\(dropped))$")
    // HTML separates attributes with a slash or a closing quote too: `<img/onerror=…>`.
    private static let handlerPattern = regex(#"(?i)(?<=[\s/"'])(?:on[a-z]+|srcdoc|formaction|data-task)(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>"']+))?"#)
    private static let urlAttributePattern = regex(#"(?i)(?<=[\s/"'])((?:href|src|xlink:href|action|poster|background|lowsrc|dynsrc|cite|data|ping)\s*=\s*)("[^"]*"|'[^']*'|[^\s>"']+)"#)

    /// Raw HTML from a note, minus anything that could run code or
    /// leave the page: scripts and other embedders, event handlers,
    /// script URLs. A stray `<` that isn't a whole tag becomes text.
    static func sanitize(_ html: String) -> String {
        var s = replace(html, containerPattern) { _ in "" }
        s = replace(s, tokenPattern) { m in
            if !m[1].isEmpty { return m[1] }  // comment
            if !m[5].isEmpty { return "&lt;" }
            let name = m[3]
            if groups(droppedPattern, name) != nil { return "" }
            guard m[2] == "<" else { return "</\(name)>" }
            var attributes = replace(m[4], handlerPattern) { _ in "" }
            attributes = replace(attributes, urlAttributePattern) { a in
                let raw = a[2].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return isDangerousURL(raw) ? a[1] + "\"#\"" : a[0]
            }
            return "<\(name)\(attributes)>"
        }
        return s
    }

    /// A link target that can't run script: `#` in place of a
    /// javascript:, vbscript:, file: or non-image data: URL.
    static func safeURL(_ url: String) -> String { isDangerousURL(url) ? "#" : url }

    private static func isDangerousURL(_ value: String) -> Bool {
        var v = value.replacingOccurrences(of: "&amp;", with: "&")
        // Entities a scheme could hide behind: `jav&#x61;script:`.
        v = replace(v, #"&#([xX])?([0-9A-Fa-f]{1,7});?"#) { m in
            let code = UInt32(m[2], radix: m[1].isEmpty ? 10 : 16) ?? 0
            return Unicode.Scalar(code).map { String(Character($0)) } ?? ""
        }
        v = v.replacingOccurrences(of: "&colon;", with: ":", options: .caseInsensitive)
            .replacingOccurrences(of: "&tab;", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "&newline;", with: "", options: .caseInsensitive)
        let compact = String(v.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F }).lowercased()
        if compact.hasPrefix("javascript:") || compact.hasPrefix("vbscript:") || compact.hasPrefix("file:") { return true }
        if compact.hasPrefix("data:") {
            return !(compact.hasPrefix("data:image/") && !compact.hasPrefix("data:image/svg"))
        }
        return false
    }

    // MARK: Regex

    private static let cache = NSCache<NSString, NSRegularExpression>()

    private static func regex(_ pattern: String) -> NSRegularExpression {
        if let cached = cache.object(forKey: pattern as NSString) { return cached }
        // Patterns are literals in this file; a bad one is a programming error.
        let compiled = try! NSRegularExpression(pattern: pattern)
        cache.setObject(compiled, forKey: pattern as NSString)
        return compiled
    }

    /// Capture groups of the first match ("" for a group that didn't take part).
    private static func groups(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let r = match.range(at: index)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// Regex replace with a closure over the capture groups (missing
    /// groups come through as ""). Compiled patterns are cached.
    private static func replace(_ text: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        replace(text, regex(pattern), transform)
    }

    private static func replace(_ text: String, _ regex: NSRegularExpression, _ transform: ([String]) -> String) -> String {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var result = ""
        var last = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let r = match.range(at: index)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            result += transform(groups)
            last = NSMaxRange(match.range)
        }
        result += ns.substring(from: last)
        return result
    }

    // MARK: Page

    /// Where the page's fonts and scripts come from: the app's own copies
    /// through the preview's URL scheme, public CDNs, or copied into the
    /// page itself (an exported file that works offline on any machine).
    enum Assets { case preview, cdn, embedded }

    private static let katexVersion = "0.16.11"
    private static let mermaidVersion = "11.4.1"

    /// The preview never falls back to a CDN: with its own copy
    /// missing, it goes without rather than fetch code.
    private static func asset(_ path: String, cdn: String, _ assets: Assets) -> String? {
        switch assets {
        case .preview: return AppResources.url(path) == nil ? nil : PreviewScheme.appURL(path)
        case .cdn: return cdn
        case .embedded: return dataURI(path)
        }
    }

    private static func dataURI(_ path: String) -> String? {
        guard let url = AppResources.url(path), let data = try? Data(contentsOf: url) else { return nil }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    /// KaTeX's stylesheet with its fonts inlined, for an embedded page.
    private static func embeddedKaTeXStyle() -> String? {
        guard let url = AppResources.url("katex/katex.min.css"), let css = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Only the woff2 faces ship; the woff/ttf fallbacks become empty.
        return replace(css, #"url\((fonts/[^)]+)\)"#) { m in "url(\(dataURI("katex/" + m[1]) ?? "data:,"))" }
    }

    private static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    /// A full HTML page around rendered markdown.
    static func page(
        body: String, title: String, theme: Theme, template: Template = .classic,
        fontFamily: String, headingFamily: String? = nil, fontSize: CGFloat, baseURL: URL?, transparent: Bool = false,
        assets: Assets = .cdn
    ) -> String {
        let base = baseURL.map { "<base href=\"\(escape($0.absoluteString))\">" } ?? ""
        let dark = theme == .dark
        let invisible = template == .invisible
        let looq = template == .looq
        let size = Int(fontSize.rounded())
        let code = CodeColors.for(theme)
        let lq = LooqColors.for(theme).css

        // Colours: body text, headings/bold, hairlines, panels, page.
        let prose = looq ? lq["text"]! : invisible ? (dark ? "#D6D6D6" : "#525252") : (dark ? "#F2EDE3" : "#1A1A1A")
        let primary = looq ? lq["heading"]! : invisible ? (dark ? "#FFFFFF" : "#000000") : prose
        let muted = looq ? lq["secondary"]! : dark ? "rgba(255,255,255,.45)" : "rgba(0,0,0,.4)"
        let border = dark ? "rgba(255,255,255,.12)" : "rgba(0,0,0,.10)"
        let panel = looq ? lq["codeBg"]! : dark ? "rgba(255,255,255,.055)" : "rgba(0,0,0,.035)"
        let ground = transparent ? "transparent" : looq ? lq["bg"]! : invisible ? (dark ? "#26292B" : "#FFFFFF") : (dark ? "#1C1C1C" : "#FEFEFE")

        // Scripts run only with this page's nonce: nothing a note
        // smuggles in can execute, nor fetch, frame or submit anything.
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let local = "'self' quickmd: file:"
        var head = """
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)'; \
        style-src 'unsafe-inline' \(local) https:; font-src \(local) data: https:; img-src * \(local) data: blob:; \
        media-src * \(local); connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri \(local)">
        """
        // The bundled faces are declared for both styles: the web view
        // can't see fonts registered in the app, and declaring is free
        // until a face is used.
        let fontFiles = [
            ("Inter", "Inter.ttf", "font-weight: 100 900; font-style: normal"),
            ("Inter", "Inter-Italic.ttf", "font-weight: 100 900; font-style: italic"),
            ("QuickMD Myeongjo", "QuickMDMyeongjo-Regular.ttf", "font-weight: 400"),
            ("QuickMD Myeongjo", "QuickMDMyeongjo-Bold.ttf", "font-weight: 700"),
        ]
        let families = fontFamily + (headingFamily ?? "")
        let usesBundledFaces = invisible || families.contains("Inter") || families.contains("Myeongjo")
        if assets == .preview || (assets == .embedded && usesBundledFaces) {
            let faces = fontFiles.compactMap { family, file, style -> String? in
                guard let url = asset("Fonts/\(file)", cdn: "", assets), !url.isEmpty else { return nil }
                return "@font-face { font-family: \"\(family)\"; src: url(\"\(url)\"); \(style); }"
            }
            head += "<style>\n\(faces.joined(separator: "\n"))\n</style>"
        } else if assets == .cdn && usesBundledFaces {
            head += #"<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:ital,opsz,wght@0,14..32,400..600;1,14..32,400..600&family=Nanum+Myeongjo:wght@400;700&display=swap">"#
        }
        let hasMath = body.contains("class=\"math")
        let hasMermaid = body.contains("class=\"mermaid\"")
        if hasMath, assets == .embedded, let style = embeddedKaTeXStyle(), let js = dataURI("katex/katex.min.js") {
            head += "<style>\(style)</style><script nonce=\"\(nonce)\" src=\"\(js)\"></script>"
        } else if hasMath,
           let css = asset("katex/katex.min.css", cdn: "https://cdn.jsdelivr.net/npm/katex@\(katexVersion)/dist/katex.min.css", assets),
           let js = asset("katex/katex.min.js", cdn: "https://cdn.jsdelivr.net/npm/katex@\(katexVersion)/dist/katex.min.js", assets) {
            head += "<link rel=\"stylesheet\" href=\"\(css)\"><script nonce=\"\(nonce)\" src=\"\(js)\"></script>"
        }
        if hasMermaid,
           let js = asset("mermaid/mermaid.min.js", cdn: "https://cdn.jsdelivr.net/npm/mermaid@\(mermaidVersion)/dist/mermaid.min.js", assets) {
            head += "<script nonce=\"\(nonce)\" src=\"\(js)\"></script>"
        }

        let callouts = CalloutKind.allCases.map { ".callout-\($0.rawValue) { --c: \($0.css(for: theme)); }" }.joined(separator: " ")

        let templateCSS: String
        // Looq's rules come after the shared ones, so they win.
        var lateCSS = ""
        if looq {
            // Looq's Markdown preview stylesheet with its default values.
            templateCSS = """
            :root { --bg: \(lq["bg"]!); --text: \(lq["text"]!); --heading: \(lq["heading"]!); --secondary: \(lq["secondary"]!);
              --link: \(lq["link"]!); --code-bg: \(lq["codeBg"]!); --body-size: \(size)px; }
            """
            lateCSS = """
            body { max-width: none; padding: 28px 32px 40px; color: var(--text);
              font-family: \(fontFamily), -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
              font-size: var(--body-size); font-weight: 400; line-height: 1.4; -webkit-font-smoothing: auto; }
            h1, h2, h3, h4, h5, h6 { color: var(--heading); line-height: 1.2; margin: 1.5em 0 0.55em;\(headingFamily.map { " font-family: \($0), -apple-system, sans-serif;" } ?? "") }
            h1 { font-size: 2.25em; margin-top: 0; } h2 { font-size: 1.6em; } h3 { font-size: 1.32em; } h4, h5, h6 { font-size: 1em; }
            p, ul, ol, blockquote, table, pre, figure { margin: 0 0 8px; }
            ul, ol { padding-left: 1.6em; } li + li { margin-top: 0.25em; } li > p { margin-bottom: 0.4em; }
            a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
            blockquote { margin-left: 0; padding: 0.2em 0 0.2em 1em; color: color-mix(in srgb, var(--text) 65%, var(--secondary));
              border-left: 3px solid color-mix(in srgb, var(--secondary) 70%, transparent); }
            hr { border: 0; border-top: 1px solid color-mix(in srgb, var(--secondary) 35%, transparent); margin: 1.5em 0; }
            code, pre { font-family: ui-monospace, "SF Mono", Menlo, Monaco, monospace; font-size: 13px; }
            :not(pre) > code { background: var(--code-bg); border-radius: 6px; padding: 0.12em 0.35em; font-size: 0.92em; box-shadow: none; color: inherit; }
            pre { background: var(--code-bg); border-radius: 8px; padding: 14px 16px; line-height: 1.4;
              font-size: max(calc(var(--body-size) - 2px), 11px); white-space: pre; overflow-x: auto; }
            pre code { color: var(--text); }
            table { width: 100%; border: 0.5px solid color-mix(in srgb, var(--secondary) 28%, transparent); border-collapse: separate;
              border-spacing: 0; overflow: hidden; border-radius: 6px; }
            th, td { border: 0; border-bottom: 0.5px solid color-mix(in srgb, var(--secondary) 28%, transparent);
              border-right: 0.5px solid color-mix(in srgb, var(--secondary) 28%, transparent); padding: 0.6em 0.8em; text-align: left; vertical-align: top; }
            tr > *:last-child { border-right: 0; } table tr:last-child > * { border-bottom: 0; }
            th { background: color-mix(in srgb, var(--code-bg) 85%, var(--bg)); color: var(--heading); font-weight: 600; }
            img { display: block; height: auto; margin: 0.5em auto; }
            mark { background: color-mix(in srgb, var(--link) 22%, transparent); color: var(--text); padding: 0.1em 0.25em; border-radius: 3px; }
            li.task-list-item:has(> input:checked) { color: color-mix(in srgb, var(--text) 50%, var(--secondary)); }
            .callout { border-left-width: 4px; padding: 0.6em 1em; background: none; border-radius: 0; }
            .katex { color: var(--text); }
            """
        } else if invisible {
            // invisibledetails.com's lesson prose, scaled from its 15px.
            templateCSS = """
            :root { --s: calc(\(size) / 15); }
            body { max-width: 30em; font: \(size)px/1.6 \(fontFamily), Inter, -apple-system, system-ui, sans-serif;
              font-optical-sizing: auto; }
            p { margin: 0 0 calc(16px * var(--s)); }
            h1, h2, h3, h4, h5, h6 { font-family: \(headingFamily.map { $0 + ", " } ?? "")"QuickMD Myeongjo", "Nanum Myeongjo", Georgia, "Times New Roman", serif; color: \(primary); }
            h1, h2, h3 { font-weight: 700; line-height: 1.1; margin: calc(64px * var(--s)) 0 calc(16px * var(--s)); }
            h1 { font-size: calc(24px * var(--s)); } h2 { font-size: calc(20px * var(--s)); } h3 { font-size: calc(17px * var(--s)); }
            h4, h5, h6 { font-weight: 400; font-size: 1em; line-height: 1.6; color: \(prose); margin: calc(16px * var(--s)) 0; }
            strong { font-weight: 500; color: \(primary); }
            ul, ol { margin: 0 0 calc(16px * var(--s)); padding-left: calc(24px * var(--s)); }
            li { margin-bottom: calc(8px * var(--s)); } li:last-child { margin-bottom: 0; }
            li > ul, li > ol { margin: calc(8px * var(--s)) 0 0; }
            ol > li::marker { color: \(primary); font-weight: 500; }
            blockquote { font-family: \(headingFamily.map { $0 + ", " } ?? "")"QuickMD Myeongjo", "Nanum Myeongjo", Georgia, serif; font-size: calc(17px * var(--s)); color: \(primary);
              margin: calc(24px * var(--s)) 0; padding: 0; border: 0; }
            hr { border: 0; border-top: 1px solid \(border); margin: calc(32px * var(--s)) 0; }
            a { color: \(primary); text-decoration: underline; text-decoration-color: \(border); text-underline-offset: 3px; }
            a:hover { text-decoration-color: currentColor; }
            code { font: 500 calc(13px * var(--s))/1 ui-monospace, "SF Mono", Menlo, monospace; color: \(primary);
              box-shadow: inset 0 0 0 .5px \(dark ? "rgba(255,255,255,.3)" : "rgba(0,0,0,.25)"); border-radius: 4px; padding: .2em .35em; }
            pre, pre code { font-size: calc(13px * var(--s)); }
            """
        } else {
            templateCSS = """
            body { max-width: 46em; font: \(size)px/1.6 \(fontFamily), Charter, Georgia, serif; }
            h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.6em 0 0.5em;\(headingFamily.map { " font-family: \($0), serif;" } ?? "") }
            h1 { font-size: 1.8em; } h2 { font-size: 1.4em; } h3 { font-size: 1.15em; } h4, h5, h6 { font-size: 1em; }
            a { color: \(dark ? "#8ab4ff" : "#1f5fd1"); text-decoration: none; }
            a:hover { text-decoration: underline; }
            code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.88em; background: \(panel); padding: .1em .35em; border-radius: 4px; }
            pre { font-size: 0.88em; }
            blockquote { margin: 1em 0; padding: 0 1em; border-left: 3px solid \(dark ? "#555" : "#d0d0d0"); color: \(dark ? "#bdb8ae" : "#555"); }
            hr { border: 0; border-top: 1px solid \(dark ? "#444" : "#ddd"); margin: 2em 0; }
            """
        }

        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(head)
        <title>\(escape(title))</title>
        \(base)
        <style>
        :root { color-scheme: \(dark ? "dark" : "light"); }
        body { margin: 0 auto; padding: 32px 28px 80px; color: \(prose); background: \(ground);
          -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
        \(templateCSS)
        body > :first-child { margin-top: 0; }
        img { max-width: 100%; }
        mark { background: \(dark ? "#6b5a1e" : "#fff3a3"); color: inherit; }
        pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; background: \(panel); padding: 16px 20px;
          border-radius: 10px; overflow-x: auto; line-height: 1.6; margin: 0 0 16px; }
        pre code { background: none; box-shadow: none; padding: 0; font: inherit; color: \(primary); }
        .tk-keyword { color: \(hex(code.keyword)); } .tk-string { color: \(hex(code.string)); }
        .tk-comment { color: \(hex(code.comment)); } .tk-number { color: \(hex(code.number)); } .tk-type { color: \(hex(code.type)); }
        table { border-collapse: separate; border-spacing: 0; width: 100%; margin: 0 0 16px;
          border: 1px solid \(border); border-radius: 10px; overflow: hidden; }
        th, td { padding: 6px 16px; text-align: left; border-bottom: 1px solid \(border); }
        tr:last-child td { border-bottom: 0; }
        th { background: \(panel); color: \(primary); font-weight: \(invisible ? 500 : 600); }
        ul.contains-task-list { list-style: none; padding-left: 0; }
        ul.contains-task-list ul.contains-task-list { padding-left: 1.6em; }
        li.task-list-item input { -webkit-appearance: none; appearance: none; box-sizing: border-box; width: 1.1em; height: 1.1em;
          margin: 0 .55em 0 0; vertical-align: -.14em; border: 1.5px solid \(muted); border-radius: .28em;
          display: inline-grid; place-content: center; cursor: default; }
        li.task-list-item input:checked { background: AccentColor; border-color: AccentColor; }
        li.task-list-item input:checked::after { content: ""; width: .48em; height: .26em; border: solid #fff;
          border-width: 0 0 .12em .12em; transform: translateY(-.05em) rotate(-45deg); }
        li.task-list-item:has(> input:checked) { color: \(muted); text-decoration: line-through; }
        .callout { margin: 0 0 16px; padding: 10px 16px; border-left: 3px solid var(--c); border-radius: 6px; background: \(panel); }
        .callout-title { margin: 0 0 4px; font-weight: 600; font-size: .92em; color: var(--c); }
        .callout > :last-child { margin-bottom: 0; }
        \(callouts)
        \(lateCSS)
        .math-display { display: block; text-align: center; margin: 0 0 16px; overflow-x: auto; overflow-y: hidden; padding: 4px 0; }
        .math-display .katex-display { margin: 0; }
        p > .math-display { margin: 8px 0; }
        .katex { color: \(primary); }
        pre.mermaid { background: \(panel); text-align: center; padding: 20px; font-family: inherit; }
        pre.mermaid svg { max-width: 100%; height: auto; }
        .qm-access { font: 13px/1.4 -apple-system, sans-serif; color: \(muted); background: \(panel); border-radius: 8px; padding: 8px 12px; margin: 0 0 16px; }
        .qm-access a { color: inherit; font-weight: 600; }
        @media print { body { background: #fff; color: #000; max-width: none; padding: 0; } }
        </style></head>
        <body>
        \(body)
        <script nonce="\(nonce)" id="qm-script">
        (function () {
          function typeset() {
            if (window.katex) document.querySelectorAll('.math').forEach(function (el) {
              try { katex.render(el.textContent, el, { displayMode: el.classList.contains('math-display'), throwOnError: false }); } catch (e) {}
            });
            // Measure labels in the page's own font, not a fallback.
            if (window.mermaid && document.querySelector('pre.mermaid:not([data-processed])')) document.fonts.ready.then(function () {
              configure();
              return mermaid.run({ querySelector: 'pre.mermaid:not([data-processed])' });
            }).catch(function () {});
          }
          // Charts take their colours from a palette: the base theme
          // derives them from the white node fill, so pies, bars and
          // timelines came out blank. Gantt can't measure its own
          // container, so it's handed the diagram's width.
          var palette = \(dark
            ? "['#7AA2D6','#E8A35C','#7DBF79','#E57D7F','#8CCBC6','#E6D07A','#C49BC0','#F2AFB7','#B8977F','#A8A3A0','#9FCFCA','#D9B7D2']"
            : "['#4E79A7','#F28E2B','#59A14F','#E15759','#76B7B2','#C9A227','#B07AA1','#FF9DA7','#9C755F','#8E8A86','#5FA39C','#B784A7']");
          function configure() {
            var box = document.querySelector('pre.mermaid'), width = box ? box.clientWidth - 40 : 800;
            var vars = { background: 'transparent', primaryColor: '\(dark ? "#26292B" : "#FFFFFF")',
              primaryBorderColor: '\(dark ? "#E5E5E5" : "#1A1A1A")', primaryTextColor: '\(primary)',
              lineColor: '\(prose)', textColor: '\(prose)', fontSize: '\(max(13, size - 1))px',
              secondaryColor: '\(dark ? "#33373A" : "#F4F5F5")', tertiaryColor: '\(dark ? "#1D2022" : "#FAFAFA")',
              pieStrokeColor: '\(dark ? "#1C1C1C" : "#FFFFFF")', pieStrokeWidth: '1.5px', pieOuterStrokeWidth: '0', pieOuterStrokeColor: 'transparent',
              pieSectionTextColor: '#FFFFFF', pieTitleTextColor: '\(primary)', pieLegendTextColor: '\(prose)', pieOpacity: '1',
              taskBkgColor: palette[0], taskBorderColor: palette[0], taskTextColor: '#FFFFFF', taskTextOutsideColor: '\(prose)',
              activeTaskBkgColor: palette[1], activeTaskBorderColor: palette[1], doneTaskBkgColor: '\(dark ? "#555A5E" : "#BAB0AC")',
              doneTaskBorderColor: '\(dark ? "#555A5E" : "#BAB0AC")', critBkgColor: palette[3], critBorderColor: palette[3],
              sectionBkgColor: '\(dark ? "rgba(255,255,255,.04)" : "rgba(0,0,0,.025)")', altSectionBkgColor: 'transparent',
              sectionBkgColor2: '\(dark ? "rgba(255,255,255,.04)" : "rgba(0,0,0,.025)")', gridColor: '\(border)', todayLineColor: palette[3],
              xyChart: { backgroundColor: 'transparent', titleColor: '\(primary)', plotColorPalette: palette.join(','),
                xAxisLabelColor: '\(prose)', xAxisTitleColor: '\(prose)', xAxisTickColor: '\(prose)', xAxisLineColor: '\(prose)',
                yAxisLabelColor: '\(prose)', yAxisTitleColor: '\(prose)', yAxisTickColor: '\(prose)', yAxisLineColor: '\(prose)' } };
            palette.forEach(function (c, i) { vars['pie' + (i + 1)] = c; vars['cScale' + i] = c; vars['cScaleLabel' + i] = '#FFFFFF'; });
            mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true, theme: 'base',
              fontFamily: '\(invisible ? "Inter, " : "")-apple-system, sans-serif', themeVariables: vars,
              gantt: { useWidth: Math.max(width, 400) } });
          }
          // Right away too: it also turns off Mermaid's own run on load.
          if (window.mermaid) configure();
          typeset();
          // The live preview swaps the body in place while typing, so
          // the page neither reloads nor loses its scroll position.
          window.qmUpdate = function (html) {
            var end = document.getElementById('qm-script'), range = document.createRange();
            range.setStart(document.body, 0);
            range.setEndBefore(end);
            range.deleteContents();
            end.insertAdjacentHTML('beforebegin', html);
            typeset();
          };
          document.addEventListener('change', function (e) {
            var t = e.target, h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.qmTask;
            if (h && t && t.dataset && t.dataset.task !== undefined) h.postMessage(parseInt(t.dataset.task, 10));
          });
        })();
        </script>
        </body></html>
        """
    }
}
