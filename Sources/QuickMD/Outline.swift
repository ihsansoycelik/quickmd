import Foundation

/// The headings of a note, for the outline sidebar. Pure, no AppKit.
enum Outline {
    struct Heading: Equatable {
        let level: Int
        let title: String
        /// UTF-16 offset of the heading line.
        let location: Int
    }

    /// ATX headings (up to three spaces in) and setext ones (`===`/`---`
    /// under text), outside fenced code and front matter: the headings
    /// the preview renders.
    static func headings(in text: String) -> [Heading] {
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

/// Counts for the footer.
enum TextStats {
    struct Counts {
        var words = 0
        var characters = 0
    }

    static func counts(in text: String) -> Counts {
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        return Counts(words: words, characters: text.count)
    }

    static func words(in text: String) -> Int { counts(in: text).words }
}

/// What the footer counts. Click it to cycle.
enum FooterStat: String, CaseIterable {
    case words, characters, readingTime

    var next: FooterStat {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    func label(_ counts: TextStats.Counts) -> String {
        switch self {
        case .words: return counts.words == 0 ? "" : counts.words == 1 ? "1 word" : "\(counts.words) words"
        case .characters: return counts.characters == 0 ? "" : counts.characters == 1 ? "1 character" : "\(counts.characters) characters"
        case .readingTime:
            guard counts.words > 0 else { return "" }
            // About 230 words a minute.
            let minutes = max(1, Int((Double(counts.words) / 230).rounded()))
            return "\(minutes) min read"
        }
    }

    func label(_ selected: TextStats.Counts, of total: TextStats.Counts) -> String {
        switch self {
        case .words: return "\(selected.words) of \(total.words) words"
        case .characters: return "\(selected.characters) of \(total.characters) characters"
        case .readingTime: return label(selected) + " selected"
        }
    }
}
