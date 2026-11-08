import Foundation

/// The headings of a note, so `[x](#slug)` links can jump to them. Pure, no AppKit.
enum Headings {
    struct Heading: Equatable {
        let level: Int
        let title: String
        /// UTF-16 offset of the heading line.
        let location: Int
    }

    /// ATX headings (up to three spaces in) and setext ones (`===`/`---`
    /// under text), outside fenced code and front matter: the headings
    /// the preview renders.
    static func find(in text: String) -> [Heading] {
        let ns = text as NSString
        var result: [Heading] = []
        var fence: MarkdownHTML.Fence?
        var location = 0
        var previous: (text: String, location: Int)?
        var lineNumber = 0
        var frontMatter = false
        while location < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
            defer { location = NSMaxRange(lineRange); lineNumber += 1 }
            if lineNumber == 0, line == "---" { frontMatter = true; continue }
            if frontMatter {
                if line == "---" || line == "..." { frontMatter = false }
                // Not front matter after all: no `key:` on its first line.
                if lineNumber == 1, line.range(of: #"^[A-Za-z0-9_-]+:"#, options: .regularExpression) == nil { frontMatter = false }
                else { continue }
            }
            if let open = fence {
                if MarkdownHTML.closes(line, open) { fence = nil }
                previous = nil
                continue
            }
            if let opening = MarkdownHTML.openingFence(line) { fence = opening; previous = nil; continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Setext: an underline promotes the text line above it.
            if let above = previous, !trimmed.isEmpty,
               trimmed.allSatisfy({ $0 == "=" }) || (trimmed.count >= 2 && trimmed.allSatisfy({ $0 == "-" })) {
                result.append(Heading(level: trimmed.hasPrefix("=") ? 1 : 2, title: above.text, location: above.location))
                previous = nil
                continue
            }
            let indent = line.prefix(while: { $0 == " " }).count
            let body = line.dropFirst(indent)
            let level = body.prefix(while: { $0 == "#" }).count
            let rest = body.dropFirst(level)
            if indent <= 3, (1...6).contains(level), rest.isEmpty || rest.first == " " || rest.first == "\t" {
                var title = rest.trimmingCharacters(in: .whitespaces)
                // Closing hashes (`## Title ##`) are decoration.
                while title.hasSuffix("#") { title.removeLast() }
                title = title.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { result.append(Heading(level: level, title: title, location: lineRange.location)) }
                previous = nil
                continue
            }
            // Only plain text can sit over a setext underline.
            let plain = !trimmed.isEmpty && indent < 4 && !">|-*+".contains(trimmed.first!)
                && trimmed.range(of: #"^\d{1,9}[.)](\s|$)"#, options: .regularExpression) == nil
            previous = plain ? (trimmed, lineRange.location) : nil
        }
        return result
    }
}
