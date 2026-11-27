import AppKit

/// Edit › Check Links…: the note's local links, checked without the
/// network. Relative files and images must exist beside the note,
/// `#anchor` links must name a heading, footnote references need a
/// definition. Web links are only counted.
enum LinkCheck {
    struct Problem: Equatable {
        enum Kind: Equatable {
            case missingFile(String)
            case missingImage(String)
            case missingAnchor(String)
            case missingFootnote(String)
        }
        let kind: Kind
        /// 1-based source line.
        let line: Int
        /// The link in the note, UTF-16.
        let range: NSRange

        var message: String {
            switch kind {
            case .missingFile(let path): return String(format: L("File not found: %@"), path)
            case .missingImage(let path): return String(format: L("Image not found: %@"), path)
            case .missingAnchor(let anchor): return String(format: L("No heading for %@"), anchor)
            case .missingFootnote(let id): return String(format: L("Footnote [^%@] has no definition"), id)
            }
        }
    }

    struct Report: Equatable {
        var problems: [Problem] = []
        /// http(s) links, not checked: no network.
        var webLinks = 0
        /// Relative links left unchecked: an unsaved note has no folder,
        /// or the folder can't be read.
        var uncheckedFiles = 0
    }

    private static let inlineLink = try! NSRegularExpression(
        pattern: #"(!?)\[((?:[^\[\]\n]|\[[^\]\n]*\])*)\]\(\s*(<[^>\n]*>|[^\s)]+(?:\([^)\s]*\)[^\s)]*)*)(?:\s+(?:"[^"\n]*"|'[^'\n]*'))?\s*\)"#)
    private static let definition = try! NSRegularExpression(pattern: #"^ {0,3}\[([^\]^\n][^\]\n]*)\]:[ \t]*(<[^>\n]*>|\S+)"#)
    private static let autolink = try! NSRegularExpression(pattern: #"<(?:https?|mailto):[^>\s]+>"#, options: .caseInsensitive)
    private static let bareURL = try! NSRegularExpression(pattern: #"\bhttps?://[^\s<>()\[\]]+"#, options: .caseInsensitive)
    private static let footnoteRef = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\](?!:)"#)
    private static let footnoteDef = try! NSRegularExpression(pattern: #"^ {0,3}\[\^([^\]\s]+)\]:"#)
    private static let codeSpan = try! NSRegularExpression(pattern: #"(`+)[^`\n].*?\1"#)
    private static let scheme = try! NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z0-9+.-]*:"#)

    /// Checks `text`. `folder` is the note's folder (nil when unsaved);
    /// `exists` answers for a file URL, so tests need no disk.
    static func check(_ text: String, folder: URL?, canReadFolder: Bool = true,
                      exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> Report {
        let ns = text as NSString
        var report = Report()
        let anchors = Set(Headings.anchors(in: text).map(\.id))
        let htmlIDs = Set(matches(#"\b(?:id|name)\s*=\s*["']([^"']+)["']"#, in: text))
        var definitions = Set<String>()
        var references: [(id: String, line: Int, range: NSRange)] = []

        var lineNumber = 0
        var location = 0
        var fence: MarkdownHTML.Fence?
        let frontMatterLines = MarkdownHTML.frontMatterEnd(text.components(separatedBy: "\n")).map { $0 + 1 } ?? 0
        while location < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            defer { location = NSMaxRange(lineRange); lineNumber += 1 }
            if lineNumber < frontMatterLines { continue }
            let rawLine = ns.substring(with: lineRange)
            let line = rawLine.trimmingCharacters(in: .newlines)
            if let open = fence {
                if MarkdownHTML.closes(line, open) { fence = nil }
                continue
            }
            if let opening = MarkdownHTML.openingFence(line) { fence = opening; continue }
            // Code spans hide links: blanked, same length, so ranges hold.
            let masked = NSMutableString(string: line)
            for m in codeSpan.matches(in: line, range: NSRange(location: 0, length: masked.length)).reversed() {
                masked.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
            }
            let full = NSRange(location: 0, length: masked.length)
            let here = masked as String

            func target(_ raw: String, image: Bool, at range: NSRange) {
                var value = raw
                if value.hasPrefix("<"), value.hasSuffix(">") { value = String(value.dropFirst().dropLast()) }
                guard !value.isEmpty else { return }
                let docRange = NSRange(location: lineRange.location + range.location, length: range.length)
                let problem = classify(value, image: image, anchors: anchors, htmlIDs: htmlIDs, folder: folder,
                                       canReadFolder: canReadFolder, exists: exists, report: &report)
                if let problem { report.problems.append(Problem(kind: problem, line: lineNumber + 1, range: docRange)) }
            }

            for m in definition.matches(in: here, range: full) {
                target(masked.substring(with: m.range(at: 2)), image: false, at: m.range)
                masked.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
            }
            for m in footnoteDef.matches(in: here, range: full) {
                definitions.insert(masked.substring(with: m.range(at: 1)))
            }
            let current = masked as String
            for m in inlineLink.matches(in: current, range: full) {
                target(masked.substring(with: m.range(at: 3)), image: m.range(at: 1).length > 0, at: m.range)
            }
            for m in inlineLink.matches(in: current, range: full).reversed() {
                masked.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
            }
            let rest = masked as String
            report.webLinks += autolink.matches(in: rest, range: full).filter {
                masked.substring(with: $0.range).lowercased().hasPrefix("<http")
            }.count
            for m in autolink.matches(in: rest, range: full).reversed() {
                masked.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
            }
            report.webLinks += bareURL.numberOfMatches(in: masked as String, range: full)
            for m in footnoteRef.matches(in: masked as String, range: full) {
                references.append((masked.substring(with: m.range(at: 1)),
                                   lineNumber + 1,
                                   NSRange(location: lineRange.location + m.range.location, length: m.range.length)))
            }
        }
        for ref in references where !definitions.contains(ref.id) {
            report.problems.append(Problem(kind: .missingFootnote(ref.id), line: ref.line, range: ref.range))
        }
        report.problems.sort { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }
        return report
    }

    private static func classify(_ value: String, image: Bool, anchors: Set<String>, htmlIDs: Set<String>,
                                 folder: URL?, canReadFolder: Bool, exists: (URL) -> Bool,
                                 report: inout Report) -> Problem.Kind? {
        if value.hasPrefix("#") {
            let anchor = String(value.dropFirst())
            let decoded = anchor.removingPercentEncoding ?? anchor
            if anchor.isEmpty || anchors.contains(decoded) || anchors.contains(decoded.lowercased())
                || htmlIDs.contains(decoded) || decoded.hasPrefix("fn-") || decoded.hasPrefix("fnref-") {
                return nil
            }
            return .missingAnchor(value)
        }
        let range = NSRange(location: 0, length: (value as NSString).length)
        if scheme.firstMatch(in: value, range: range) != nil {
            let lower = value.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") { report.webLinks += 1; return nil }
            guard lower.hasPrefix("file:"), let url = URL(string: value), url.isFileURL else { return nil }
            return exists(url) ? nil : (image ? .missingImage(value) : .missingFile(value))
        }
        if value.hasPrefix("//") { report.webLinks += 1; return nil }
        // Path part only: `other.md#part`, `pic.png?v=2`.
        var path = value
        if let cut = path.firstIndex(where: { $0 == "#" || $0 == "?" }) { path = String(path[..<cut]) }
        guard !path.isEmpty else { return nil }
        path = path.removingPercentEncoding ?? path
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else if path.hasPrefix("~/") {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            guard let folder, canReadFolder else { report.uncheckedFiles += 1; return nil }
            url = folder.appendingPathComponent(path)
        }
        return exists(url.standardizedFileURL) ? nil : (image ? .missingImage(value) : .missingFile(value))
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }
}

// MARK: - The sheet

extension DocumentWindowController {
    @objc func checkLinks(_ sender: Any?) {
        guard let window else { return }
        let folder = editor.textView.baseURL
        let run = { [weak self] (readable: Bool) in
            guard let self else { return }
            let text = self.editor.currentText
            let report = LinkCheck.check(text, folder: folder, canReadFolder: readable)
            LinkCheckSheet(report: report, text: text) { [weak self] problem in
                guard let textView = self?.editor.textView,
                      NSMaxRange(problem.range) <= (textView.string as NSString).length else { return }
                textView.setSelectedRange(problem.range)
                textView.scrollRangeToVisible(problem.range)
                textView.showFindIndicator(for: problem.range)
            }.show(on: window)
        }
        if let folder, !FolderAccess.canRead(folder) {
            FolderAccess.request(folder, for: window) { granted in run(granted) }
        } else {
            run(true)
        }
    }
}

/// The problems as a list: line and what's wrong. Clicking a row selects
/// that link in the note behind the sheet.
final class LinkCheckSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let report: LinkCheck.Report
    private let reveal: (LinkCheck.Problem) -> Void
    private var panel: NSPanel?
    private var keepAlive: LinkCheckSheet?
    private let table = NSTableView()

    init(report: LinkCheck.Report, text: String, reveal: @escaping (LinkCheck.Problem) -> Void) {
        self.report = report
        self.reveal = reveal
    }

    private var summary: String {
        var parts: [String] = []
        if report.webLinks > 0 {
            parts.append(String(format: L("%d web links not checked (QuickMD checks without the network)."), report.webLinks))
        }
        if report.uncheckedFiles > 0 {
            parts.append(String(format: L("%d file links not checked: save the note or allow its folder first."), report.uncheckedFiles))
        }
        return parts.joined(separator: "\n")
    }

    func show(on window: NSWindow) {
        guard !report.problems.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L("No broken links")
            alert.informativeText = summary.isEmpty ? L("Every local link, heading anchor and footnote checks out.") : summary
            alert.addButton(withTitle: L("OK"))
            alert.beginSheetModal(for: window)
            return
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                            styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        panel.minSize = NSSize(width: 360, height: 220)
        let title = NSTextField(labelWithString: report.problems.count == 1
            ? L("1 link problem") : String(format: L("%d link problems"), report.problems.count))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let lineColumn = NSTableColumn(identifier: .init("line"))
        lineColumn.title = L("Line")
        lineColumn.width = 50
        lineColumn.minWidth = 40
        let problemColumn = NSTableColumn(identifier: .init("problem"))
        problemColumn.title = L("Problem")
        problemColumn.resizingMask = .autoresizingMask
        table.addTableColumn(lineColumn)
        table.addTableColumn(problemColumn)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked(_:))
        table.setAccessibilityLabel(L("Link problems"))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let note = NSTextField(wrappingLabelWithString: summary)
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.isHidden = summary.isEmpty
        let close = NSButton(title: L("Done"), target: self, action: #selector(done(_:)))
        close.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, scroll, note, close])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        close.setContentHuggingPriority(.required, for: .vertical)
        stack.setCustomSpacing(14, after: note)
        panel.contentView = content
        self.panel = panel
        keepAlive = self
        window.beginSheet(panel) { [weak self] _ in self?.keepAlive = nil }
    }

    @objc private func done(_ sender: Any?) {
        guard let panel, let parent = panel.sheetParent else { return }
        parent.endSheet(panel)
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard report.problems.indices.contains(row) else { return }
        reveal(report.problems[row])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { report.problems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let problem = report.problems[row]
        let isLine = tableColumn?.identifier.rawValue == "line"
        let field = NSTextField(labelWithString: isLine ? "\(problem.line)" : problem.message)
        field.lineBreakMode = .byTruncatingMiddle
        if isLine {
            field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        field.toolTip = problem.message
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) { rowClicked(nil) }
}
