import Foundation

/// HTML from the pasteboard (a web page, Mail, Pages, Google Docs) as
/// Markdown: headings, emphasis, code, links, images, lists (nested),
/// quotes, tables and rules. Scripts, styles and other embedders are
/// dropped with their content; unknown tags keep only their text.
/// Parsed with XMLDocument's HTML tidy, external entities never loaded.
enum HTMLToMarkdown {
    static func convert(_ html: String) -> String {
        // No DOCTYPE: nothing for the parser to go and fetch.
        let cleaned = html.replacingOccurrences(of: #"(?is)<!DOCTYPE[^>]*>"#, with: "", options: .regularExpression)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let doc = try? XMLDocument(xmlString: cleaned, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = doc.rootElement() else {
            return fallback(html)
        }
        let body = child(root, named: "body") ?? root
        return tidy(blocks(body.children ?? []).joined(separator: "\n\n"))
    }

    // MARK: Blocks

    private static let droppedTags: Set<String> = [
        "script", "style", "head", "title", "meta", "link", "noscript", "iframe", "frame", "frameset",
        "object", "embed", "applet", "svg", "math", "template", "canvas", "video", "audio", "source",
        "track", "form", "button", "select", "option", "textarea", "base", "map",
    ]
    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "aside", "nav", "body", "html",
        "center", "figure", "figcaption", "address", "details", "summary", "dl", "dt", "dd", "fieldset",
        "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "ul", "ol", "li", "table", "hr",
    ]

    private static func name(_ node: XMLNode) -> String { (node.localName ?? node.name ?? "").lowercased() }

    private static func child(_ element: XMLElement, named tag: String) -> XMLElement? {
        element.children?.first { name($0) == tag } as? XMLElement
    }

    /// Child nodes as Markdown blocks: runs of inline content become paragraphs.
    private static func blocks(_ nodes: [XMLNode]) -> [String] {
        var result: [String] = []
        var paragraph = ""
        func flush() {
            let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(text) }
            paragraph = ""
        }
        for node in nodes {
            if let element = node as? XMLElement, blockTags.contains(name(element)) {
                flush()
                result += block(element)
            } else {
                paragraph += inline(node)
            }
        }
        flush()
        return result
    }

    private static func block(_ element: XMLElement) -> [String] {
        let tag = name(element)
        let children = element.children ?? []
        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tag.last!)) ?? 1
            let text = inlineChildren(children).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? [] : [String(repeating: "#", count: level) + " " + text]
        case "hr":
            return ["---"]
        case "pre":
            return [codeBlock(element)]
        case "blockquote":
            let inner = blocks(children).joined(separator: "\n\n")
            guard !inner.isEmpty else { return [] }
            return [inner.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")]
        case "ul", "ol":
            let list = self.list(element, ordered: tag == "ol")
            return list.isEmpty ? [] : [list]
        case "li":
            let item = listItem(element, marker: "- ")
            return item.isEmpty ? [] : [item]
        case "table":
            return table(element).map { [$0] } ?? []
        default:
            return blocks(children)
        }
    }

    private static func codeBlock(_ pre: XMLElement) -> String {
        var code = pre.stringValue ?? ""
        if code.hasSuffix("\n") { code.removeLast() }
        let classes = [pre.attribute(forName: "class")?.stringValue,
                       child(pre, named: "code")?.attribute(forName: "class")?.stringValue]
            .compactMap { $0 }.joined(separator: " ")
        var language = ""
        if let range = classes.range(of: #"(?:language|lang)-([A-Za-z0-9_+#.-]+)"#, options: .regularExpression) {
            language = String(classes[range]).components(separatedBy: "-").dropFirst().joined(separator: "-")
        }
        var fence = "```"
        while code.contains(fence) { fence += "`" }
        return fence + language + "\n" + code + "\n" + fence
    }

    private static func list(_ element: XMLElement, ordered: Bool) -> String {
        var number = Int(element.attribute(forName: "start")?.stringValue ?? "") ?? 1
        var items: [String] = []
        for child in element.children ?? [] {
            guard let li = child as? XMLElement else {
                // Stray text between items joins the previous one.
                let text = inline(child).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { items.append((ordered ? "\(number). " : "- ") + text); number += 1 }
                continue
            }
            let tag = name(li)
            if tag == "ul" || tag == "ol" {
                // A list right inside a list nests under the item before it.
                let nested = list(li, ordered: tag == "ol")
                guard !nested.isEmpty else { continue }
                let indented = indent(nested, by: items.isEmpty ? 0 : (ordered ? "\(number - 1). ".count : 2))
                if items.isEmpty { items.append(indented) } else { items[items.count - 1] += "\n" + indented }
                continue
            }
            let marker = ordered ? "\(number). " : "- "
            let item = listItem(li, marker: marker)
            if !item.isEmpty { items.append(item); number += 1 }
        }
        return items.joined(separator: "\n")
    }

    private static func listItem(_ li: XMLElement, marker: String) -> String {
        let parts = blocks(li.children ?? [])
        guard !parts.isEmpty else { return "" }
        var text = ""
        for (index, part) in parts.enumerated() {
            if index > 0 {
                let previousIsList = isListBlock(parts[index - 1]), isList = isListBlock(part)
                text += (isList || previousIsList) ? "\n" : "\n\n"
            }
            text += part
        }
        text = text.replacingOccurrences(of: #"^\[( |x)\] +"#, with: "[$1] ", options: .regularExpression)
        return marker + indent(text, by: marker.count, skipFirst: true)
    }

    private static func isListBlock(_ text: String) -> Bool {
        text.range(of: #"^(?:[-*+]|\d{1,9}[.)]) "#, options: .regularExpression) != nil
    }

    private static func indent(_ text: String, by width: Int, skipFirst: Bool = false) -> String {
        let pad = String(repeating: " ", count: width)
        return text.components(separatedBy: "\n").enumerated().map { index, line in
            (skipFirst && index == 0) || line.isEmpty ? line : pad + line
        }.joined(separator: "\n")
    }

    private static func table(_ element: XMLElement) -> String? {
        var rows: [[String]] = []
        var headerFirst = false
        func collect(_ parent: XMLElement, section: String) {
            for child in parent.children ?? [] {
                guard let el = child as? XMLElement else { continue }
                switch name(el) {
                case "tr":
                    let cells = (el.children ?? []).compactMap { $0 as? XMLElement }.filter { ["td", "th"].contains(name($0)) }
                    if rows.isEmpty { headerFirst = section == "thead" || cells.contains { name($0) == "th" } }
                    rows.append(cells.map { inlineChildren($0.children ?? []) })
                case "thead", "tbody", "tfoot":
                    collect(el, section: name(el))
                default:
                    break
                }
            }
        }
        collect(element, section: "")
        rows = rows.filter { !$0.isEmpty }
        guard !rows.isEmpty else { return nil }
        // A table with no header row gets an empty one: Markdown needs it.
        if !headerFirst, rows.count > 0 {
            rows.insert(Array(repeating: "", count: rows.map(\.count).max() ?? 0), at: 0)
        }
        return MarkdownTable.make(rows)
    }

    // MARK: Inline

    private static func inlineChildren(_ nodes: [XMLNode]) -> String {
        nodes.map(inline).joined()
    }

    private static func inline(_ node: XMLNode) -> String {
        switch node.kind {
        case .text:
            let raw = (node.stringValue ?? "").replacingOccurrences(of: "\u{00A0}", with: " ")
            let collapsed = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return escape(collapsed)
        case .element:
            break
        default:
            return ""
        }
        guard let element = node as? XMLElement else { return "" }
        let tag = name(element)
        if droppedTags.contains(tag) { return "" }
        let children = element.children ?? []
        switch tag {
        case "br":
            return "\n"
        case "strong", "b":
            return wrap(inlineChildren(children), "**")
        case "em", "i", "cite", "dfn":
            return wrap(inlineChildren(children), "*")
        case "del", "s", "strike":
            return wrap(inlineChildren(children), "~~")
        case "mark":
            return wrap(inlineChildren(children), "==")
        case "code", "kbd", "samp", "tt":
            let code = (element.stringValue ?? "").replacingOccurrences(of: "\n", with: " ")
            guard !code.isEmpty else { return "" }
            var ticks = "`"
            while code.contains(ticks) { ticks += "`" }
            let pad = code.hasPrefix("`") || code.hasSuffix("`") ? " " : ""
            return ticks + pad + code + pad + ticks
        case "a":
            let text = inlineChildren(children)
            let href = (element.attribute(forName: "href")?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !href.isEmpty, !isScript(href) else { return text }
            let label = text.trimmingCharacters(in: .whitespaces)
            if label.isEmpty { return children.contains(where: { name($0) == "img" }) ? text : "<\(href)>" }
            return "[\(label)](\(destination(href)))"
        case "img":
            let src = (element.attribute(forName: "src")?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            let alt = escape(element.attribute(forName: "alt")?.stringValue ?? "")
            // Inline data and local files from another app don't belong in a note.
            guard !src.isEmpty, !isScript(src), !src.lowercased().hasPrefix("data:"), !src.lowercased().hasPrefix("file:") else { return alt }
            return "![\(alt)](\(destination(src)))"
        case "input":
            guard element.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox" else { return "" }
            return element.attribute(forName: "checked") != nil ? "[x] " : "[ ] "
        case "span", "font":
            let style = (element.attribute(forName: "style")?.stringValue ?? "").lowercased().replacingOccurrences(of: " ", with: "")
            var text = inlineChildren(children)
            // Google Docs and Word mark emphasis with inline styles.
            if style.range(of: #"font-weight:(bold|[6-9]00)"#, options: .regularExpression) != nil { text = wrap(text, "**") }
            if style.contains("font-style:italic") { text = wrap(text, "*") }
            return text
        default:
            if blockTags.contains(tag) { return " " + inlineChildren(children) + " " }
            return inlineChildren(children)
        }
    }

    /// `**` around text, its outer spaces kept outside the marks.
    private static func wrap(_ text: String, _ mark: String) -> String {
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return text }
        // Already wrapped (a <b> inside a bold span): leave it.
        if core.hasPrefix(mark) && core.hasSuffix(mark) && core.count > mark.count * 2 { return text }
        let lead = text.prefix(while: { $0.isWhitespace })
        let trail = String(text.reversed().prefix(while: { $0.isWhitespace }).reversed())
        return lead + mark + core + mark + trail
    }

    private static func destination(_ url: String) -> String {
        let spaced = url.replacingOccurrences(of: " ", with: "%20")
        return spaced.contains("(") || spaced.contains(")") ? "<\(spaced)>" : spaced
    }

    private static func isScript(_ url: String) -> Bool {
        let compact = url.lowercased().filter { !$0.isWhitespace }
        return compact.hasPrefix("javascript:") || compact.hasPrefix("vbscript:")
    }

    /// Characters that would turn plain pasted text into Markdown.
    private static func escape(_ text: String) -> String {
        var out = ""
        for c in text {
            switch c {
            case "\\", "*", "`", "[", "]", "<": out.append("\\"); out.append(c)
            default: out.append(c)
            }
        }
        return out
    }

    /// Trailing spaces off, no more than one blank line in a row, outside code.
    private static func tidy(_ markdown: String) -> String {
        var lines: [String] = []
        var inFence = false
        for raw in markdown.components(separatedBy: "\n") {
            let trimmedStart = raw.trimmingCharacters(in: .whitespaces)
            if trimmedStart.hasPrefix("```") { inFence.toggle() }
            if inFence || trimmedStart.hasPrefix("```") { lines.append(raw); continue }
            var line = raw
            while line.hasSuffix(" ") { line.removeLast() }
            // A line that starts with # or > in prose is text, not a heading or quote.
            if line.isEmpty, lines.last?.isEmpty == true { continue }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// When the markup won't parse: its text, tags removed.
    private static func fallback(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"(?is)<(script|style|head)\b.*?</\1\s*>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</li>|</h[1-6]>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
        return tidy(s)
    }
}

/// A Markdown table from rows of cells: the first row is the header,
/// pipes are escaped and columns padded to line up.
enum MarkdownTable {
    static func make(_ rows: [[String]]) -> String {
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0 else { return "" }
        let cells = rows.map { row in
            (0..<columns).map { index -> String in
                let raw = index < row.count ? row[index] : ""
                return escapePipes(raw.replacingOccurrences(of: "\r\n", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces))
            }
        }
        let widths = (0..<columns).map { column in max(3, cells.map { $0[column].count }.max() ?? 0) }
        func line(_ row: [String]) -> String {
            "| " + row.enumerated().map { $1.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }.joined(separator: " | ") + " |"
        }
        var out = [line(cells[0]), "| " + widths.map { String(repeating: "-", count: $0) }.joined(separator: " | ") + " |"]
        out += cells.dropFirst().map(line)
        return out.joined(separator: "\n")
    }

    /// `|` as `\|`, leaving ones already escaped alone.
    static func escapePipes(_ text: String) -> String {
        var out = ""
        var previous: Character?
        for c in text {
            if c == "|", previous != "\\" { out.append("\\") }
            out.append(c)
            previous = c
        }
        return out
    }

    /// Tab-separated text from a spreadsheet: two or more lines, each
    /// with the same number of tabs (at least one), and a first column
    /// that isn't empty everywhere (indented code has tabs too).
    static func tabSeparatedRows(_ text: String) -> [[String]]? {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard lines.count >= 2 else { return nil }
        let rows = lines.map { $0.components(separatedBy: "\t") }
        let count = rows[0].count
        guard count >= 2, rows.allSatisfy({ $0.count == count }),
              rows.contains(where: { !$0[0].trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        return rows
    }

    /// CSV or TSV text as rows: tabs win when present, then the commoner
    /// of `,` and `;` in the first line. Quoted fields may hold the
    /// separator, doubled quotes and line breaks.
    static func delimitedRows(_ text: String) -> [[String]]? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let firstLine = normalized.prefix(while: { $0 != "\n" })
        let separator: Character
        if normalized.contains("\t") { separator = "\t" } else {
            separator = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        }
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var atFieldStart = true
        let chars = Array(normalized)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && atFieldStart {
                quoted = true
                atFieldStart = false
            } else if c == separator {
                row.append(field); field = ""; atFieldStart = true
            } else if c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""; atFieldStart = true
            } else {
                field.append(c)
                if c != " " { atFieldStart = false }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        rows = rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
        guard !rows.isEmpty, rows.contains(where: { $0.count >= 2 }) else { return nil }
        return rows
    }
}
