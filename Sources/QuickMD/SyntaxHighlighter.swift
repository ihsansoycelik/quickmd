import Foundation

/// A small, line-at-a-time highlighter for fenced code: comments,
/// strings, numbers, keywords and capitalised type names. One rule set
/// with per-language comment markers and keywords; not a parser, just
/// enough colour to read code by. Used by the editor and the preview.
enum SyntaxHighlighter {
    enum Kind: String {
        case keyword, string, comment, number, type
    }

    struct Token {
        let range: NSRange
        let kind: Kind
    }

    private static let hashComment: Set<String> = [
        "python", "py", "sh", "bash", "zsh", "shell", "fish", "ruby", "rb", "yaml", "yml", "toml",
        "r", "perl", "pl", "make", "makefile", "dockerfile", "conf", "ini", "nix", "elixir", "ex", "coffee",
    ]
    private static let dashComment: Set<String> = ["sql", "lua", "haskell", "hs", "elm"]
    private static let percentComment: Set<String> = ["mermaid", "tex", "latex", "math", "erlang", "matlab"]

    private static let keywords: Set<String> = [
        // C family, Swift, JS/TS, Go, Rust, Java, Kotlin, C#
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return",
        "func", "function", "fn", "def", "let", "var", "const", "val", "mut", "static", "final",
        "class", "struct", "enum", "protocol", "interface", "trait", "impl", "extension", "type", "typealias",
        "import", "export", "from", "package", "module", "use", "using", "namespace", "include",
        "public", "private", "protected", "internal", "fileprivate", "open", "pub",
        "true", "false", "nil", "null", "undefined", "None", "True", "False", "self", "Self", "this", "super",
        "new", "delete", "in", "of", "is", "as", "not", "and", "or", "guard", "defer", "where",
        "async", "await", "try", "catch", "throw", "throws", "finally", "yield", "lambda", "with",
        "elif", "except", "raise", "pass", "global", "match", "when", "then", "end", "begin",
        "go", "chan", "select", "map", "range", "void", "int", "float", "double", "bool", "char", "string",
        "extends", "implements", "override", "abstract", "inout", "some", "any", "init", "deinit",
        "echo", "fi", "done", "esac", "local", "unless", "until", "loop", "crate", "ref", "dyn",
        "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "JOIN", "ON", "GROUP", "BY", "ORDER", "AS", "AND", "OR",
        "select", "where", "insert", "update", "join", "group", "order", "limit",
        // Mermaid
        "graph", "flowchart", "sequenceDiagram", "classDiagram", "stateDiagram", "erDiagram", "gantt", "pie",
        "journey", "mindmap", "timeline", "participant", "actor", "subgraph", "LR", "RL", "TD", "TB", "BT", "note", "loop", "alt", "opt",
    ]

    private static let wordPattern = try! NSRegularExpression(pattern: #"\b(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)\b|[A-Za-z_][A-Za-z0-9_]*"#)

    /// Tokens of one line of code (no newline), UTF-16 ranges into it.
    static func tokens(in line: NSString, language: String) -> [Token] {
        let lang = language.lowercased()
        var tokens: [Token] = []
        var plain: [NSRange] = []
        let n = line.length
        var i = 0
        var runStart = 0

        func startsWith(_ s: String, at index: Int) -> Bool {
            // No allocation: this runs at every character of a code line.
            let u = s.utf16
            guard index + u.count <= n else { return false }
            for (k, c) in u.enumerated() where line.character(at: index + k) != c { return false }
            return true
        }
        func isLineComment(at index: Int) -> Bool {
            if percentComment.contains(lang) { return startsWith("%%", at: index) || (lang != "mermaid" && startsWith("%", at: index)) }
            if dashComment.contains(lang) { return startsWith("--", at: index) }
            if hashComment.contains(lang) { return startsWith("#", at: index) && (index == 0 || line.character(at: index - 1) != 0x24) }
            if lang == "html" || lang == "xml" || lang == "md" || lang == "markdown" { return false }
            return startsWith("//", at: index)
        }

        while i < n {
            let c = line.character(at: i)
            if isLineComment(at: i) {
                if i > runStart { plain.append(NSRange(location: runStart, length: i - runStart)) }
                tokens.append(Token(range: NSRange(location: i, length: n - i), kind: .comment))
                runStart = n
                i = n
                break
            }
            if startsWith("/*", at: i) || startsWith("<!--", at: i) {
                let close = startsWith("/*", at: i) ? "*/" : "-->"
                if i > runStart { plain.append(NSRange(location: runStart, length: i - runStart)) }
                var j = i + 2
                while j < n, !startsWith(close, at: j) { j += 1 }
                j = min(n, j + close.utf16.count)
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .comment))
                i = j
                runStart = j
                continue
            }
            // Strings: "…", '…', `…`. An apostrophe inside a word (don't) isn't one.
            if c == 0x22 || c == 0x60 || (c == 0x27 && !(i > 0 && isWordChar(line.character(at: i - 1)))) {
                if i > runStart { plain.append(NSRange(location: runStart, length: i - runStart)) }
                var j = i + 1
                while j < n, line.character(at: j) != c {
                    if line.character(at: j) == 0x5C { j += 1 }
                    j += 1
                }
                j = min(n, j + 1)
                tokens.append(Token(range: NSRange(location: i, length: j - i), kind: .string))
                i = j
                runStart = j
                continue
            }
            i += 1
        }
        if runStart < n { plain.append(NSRange(location: runStart, length: n - runStart)) }

        let text = line as String
        for range in plain {
            for match in wordPattern.matches(in: text, range: range) {
                let word = line.substring(with: match.range)
                guard let first = word.utf16.first else { continue }
                if first >= 0x30 && first <= 0x39 {
                    tokens.append(Token(range: match.range, kind: .number))
                } else if keywords.contains(word) {
                    tokens.append(Token(range: match.range, kind: .keyword))
                } else if first >= 0x41 && first <= 0x5A, word.count > 1 {
                    tokens.append(Token(range: match.range, kind: .type))
                }
            }
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    private static func isWordChar(_ c: unichar) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
    }

    /// The code as HTML with `<span class="tk-…">` around tokens.
    static func html(_ code: String, language: String, escape: (String) -> String) -> String {
        code.components(separatedBy: "\n").map { line -> String in
            let ns = line as NSString
            var out = ""
            var last = 0
            for token in tokens(in: ns, language: language) {
                out += escape(ns.substring(with: NSRange(location: last, length: token.range.location - last)))
                out += "<span class=\"tk-\(token.kind.rawValue)\">\(escape(ns.substring(with: token.range)))</span>"
                last = NSMaxRange(token.range)
            }
            return out + escape(ns.substring(from: last))
        }.joined(separator: "\n")
    }
}
