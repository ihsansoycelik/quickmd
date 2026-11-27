import AppKit

/// One command in the slash menu: a Format menu action, sent down the
/// responder chain to the text view with a stand-in menu item so
/// `tag` and `representedObject` arrive as they would from the menu bar.
struct SlashCommand {
    let title: String
    let symbol: String
    /// Other words that find it: `h1`, `todo`, `checkbox`…
    let keywords: [String]
    let action: Selector
    var tag = 0
    var represented: String?

    static let all: [SlashCommand] = {
        var commands = [
            SlashCommand(title: L("Text"), symbol: "text.alignleft", keywords: ["text", "body", "paragraph", "plain"],
                         action: #selector(MarkdownTextView.setHeading(_:)), tag: 0),
            SlashCommand(title: L("Heading 1"), symbol: "textformat.size.larger", keywords: ["heading 1", "h1", "title"],
                         action: #selector(MarkdownTextView.setHeading(_:)), tag: 1),
            SlashCommand(title: L("Heading 2"), symbol: "textformat.size", keywords: ["heading 2", "h2", "subtitle"],
                         action: #selector(MarkdownTextView.setHeading(_:)), tag: 2),
            SlashCommand(title: L("Heading 3"), symbol: "textformat.size.smaller", keywords: ["heading 3", "h3"],
                         action: #selector(MarkdownTextView.setHeading(_:)), tag: 3),
            SlashCommand(title: L("Bulleted List"), symbol: "list.bullet", keywords: ["bulleted list", "ul", "unordered", "bullet"],
                         action: #selector(MarkdownTextView.toggleBulletList(_:))),
            SlashCommand(title: L("Numbered List"), symbol: "list.number", keywords: ["numbered list", "ol", "ordered"],
                         action: #selector(MarkdownTextView.toggleNumberedList(_:))),
            SlashCommand(title: L("Task List"), symbol: "checklist", keywords: ["task list", "todo", "checkbox", "task"],
                         action: #selector(MarkdownTextView.toggleTaskList(_:))),
            SlashCommand(title: L("Quote"), symbol: "text.quote", keywords: ["quote", "blockquote"],
                         action: #selector(MarkdownTextView.toggleQuote(_:))),
            SlashCommand(title: L("Code Block"), symbol: "curlybraces", keywords: ["code block", "code", "fence", "snippet"],
                         action: #selector(MarkdownTextView.insertCodeBlock(_:))),
            SlashCommand(title: L("Table"), symbol: "tablecells", keywords: ["table", "grid"],
                         action: #selector(MarkdownTextView.insertTable(_:))),
        ]
        let calloutSymbols: [CalloutKind: String] = [
            .note: "info.circle", .tip: "lightbulb", .important: "exclamationmark.bubble",
            .warning: "exclamationmark.triangle", .caution: "exclamationmark.octagon",
        ]
        for kind in CalloutKind.allCases {
            commands.append(SlashCommand(title: L("Callout") + ": " + kind.title, symbol: calloutSymbols[kind] ?? "info.circle",
                                         keywords: ["callout", "admonition", "alert", kind.rawValue],
                                         action: #selector(MarkdownTextView.insertCallout(_:)), represented: kind.rawValue))
        }
        commands += [
            SlashCommand(title: L("Math Block"), symbol: "function", keywords: ["math block", "latex", "katex", "equation", "formula"],
                         action: #selector(MarkdownTextView.insertMathBlock(_:))),
            SlashCommand(title: L("Mermaid Diagram"), symbol: "point.3.connected.trianglepath.dotted",
                         keywords: ["mermaid", "diagram", "chart", "flow", "graph"],
                         action: #selector(MarkdownTextView.insertDiagram(_:))),
            SlashCommand(title: L("Horizontal Rule"), symbol: "minus", keywords: ["horizontal rule", "divider", "hr", "line", "separator"],
                         action: #selector(MarkdownTextView.insertHorizontalRule(_:))),
            SlashCommand(title: L("Footnote"), symbol: "textformat.superscript", keywords: ["footnote", "note", "reference"],
                         action: #selector(MarkdownTextView.insertFootnote(_:))),
            SlashCommand(title: L("Today’s Date"), symbol: "calendar", keywords: ["today", "date", "now"],
                         action: #selector(MarkdownTextView.insertTodaysDate(_:))),
        ]
        return commands
    }()

    /// Commands whose title or a keyword has a word starting with `query`,
    /// title matches first. An empty query matches everything.
    static func matching(_ query: String) -> [SlashCommand] {
        let q = query.lowercased()
        guard !q.isEmpty else { return all }
        func wordStarts(_ text: String) -> Bool {
            let lower = text.lowercased()
            return lower.hasPrefix(q) || lower.split(whereSeparator: { $0 == " " || $0 == ":" }).contains { $0.hasPrefix(q) }
        }
        let byTitle = all.filter { wordStarts($0.title) }
        let byKeyword = all.filter { command in !wordStarts(command.title) && command.keywords.contains(where: wordStarts) }
        return byTitle + byKeyword
    }

    var menuItem: NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = tag
        item.representedObject = represented
        return item
    }
}

/// The menu that opens under a `/` typed at the start of a line or
/// after a space: typing filters it, ↑↓ pick, Return or Tab apply, Esc
/// closes. A non-activating panel, so the text view keeps the keyboard
/// and the caret keeps blinking.
final class SlashMenu: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let textView: MarkdownTextView
    private var panel: NSPanel?
    private let table = NSTableView()
    private var commands: [SlashCommand] = []
    /// Where the `/` is. The query runs from just after it to the caret.
    private var slashLocation = 0
    private var observers: [Any] = []

    private static let rowHeight: CGFloat = 26
    private static let width: CGFloat = 240
    private static let maxRows = 9
    private static let inset: CGFloat = 5

    init(textView: MarkdownTextView) {
        self.textView = textView
        super.init()
    }

    deinit { removeObservers() }

    var isOpen: Bool { panel?.isVisible == true }

    func open(at location: Int) {
        slashLocation = location
        commands = SlashCommand.all
        if panel == nil { panel = makePanel() }
        table.reloadData()
        select(0)
        guard let panel, let window = textView.window else { return }
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        place()
        panel.orderFront(nil)
        observe(window)
    }

    func close() {
        guard let panel else { return }
        removeObservers()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// After every edit or caret move: refilter, or close once the caret
    /// leaves the query or the query stops being a word.
    func update() {
        guard isOpen else { return }
        let ns = textView.string as NSString
        let caret = textView.selectedRange()
        guard caret.length == 0, slashLocation < ns.length, ns.character(at: slashLocation) == 0x2F,
              caret.location > slashLocation else { return close() }
        let query = ns.substring(with: NSRange(location: slashLocation + 1, length: caret.location - slashLocation - 1))
        guard !query.contains(where: { $0.isWhitespace || $0 == "/" }) else { return close() }
        commands = SlashCommand.matching(query)
        guard !commands.isEmpty else { return close() }
        table.reloadData()
        select(0)
        place()
    }

    /// The text view's key commands while the menu is up. True when handled.
    func handle(_ selector: Selector) -> Bool {
        guard isOpen else { return false }
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            select((table.selectedRow - 1 + commands.count) % commands.count)
        case #selector(NSResponder.moveDown(_:)):
            select((table.selectedRow + 1) % commands.count)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            choose(table.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
            close()
        default:
            return false
        }
        return true
    }

    private func choose(_ row: Int) {
        guard commands.indices.contains(row) else { return close() }
        let command = commands[row]
        let typed = NSRange(location: slashLocation, length: textView.selectedRange().location - slashLocation)
        close()
        textView.replace(typed, with: "")
        NSApp.sendAction(command.action, to: textView, from: command.menuItem)
    }

    private func select(_ row: Int) {
        guard commands.indices.contains(row) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.animationBehavior = .utilityWindow

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.cgColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked(_:))
        table.setAccessibilityLabel(L("Insert block"))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.contentInsets = NSEdgeInsets(top: Self.inset, left: 0, bottom: Self.inset, right: 0)
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: background.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.inset),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.inset),
        ])
        panel.contentView = background
        return panel
    }

    /// Under the `/`, or above it when the screen runs out below.
    private func place() {
        guard let panel else { return }
        // A forced app theme must reach this child panel too.
        panel.appearance = textView.window?.appearance
        let rows = CGFloat(min(commands.count, Self.maxRows))
        let height = rows * Self.rowHeight + Self.inset * 2
        var actual = NSRange()
        let slash = textView.firstRect(forCharacterRange: NSRange(location: slashLocation, length: 1), actualRange: &actual)
        let visible = (textView.window?.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var origin = NSPoint(x: slash.minX - Self.inset - 8, y: slash.minY - height - 4)
        if origin.y < visible.minY { origin.y = slash.maxY + 4 }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - Self.width)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: Self.width, height: height)), display: true)
    }

    @objc private func clicked(_ sender: Any?) {
        if table.clickedRow >= 0 { choose(table.clickedRow) }
    }

    /// Scrolling, resizing or leaving the window would strand the menu.
    private func observe(_ window: NSWindow) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let closeMenu: (Notification) -> Void = { [weak self] _ in self?.close() }
        if let clip = textView.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main, using: closeMenu))
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main, using: closeMenu))
        }
        observers.append(center.addObserver(forName: .editorSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { commands.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SlashRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("SlashCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
        let command = commands[row]
        cell.textField?.stringValue = command.title
        cell.imageView?.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Selected rows draw on the accent colour: the text goes white.
        table.enumerateAvailableRowViews { rowView, row in
            guard let cell = rowView.view(atColumn: 0) as? NSTableCellView else { return }
            let selected = row == table.selectedRow
            cell.textField?.textColor = selected ? .selectedMenuItemTextColor : .labelColor
            cell.imageView?.contentTintColor = selected ? .selectedMenuItemTextColor : .secondaryLabelColor
        }
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let image = NSImageView()
        image.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        let label = NSTextField(labelWithString: "")
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        for view in [image, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = image
        cell.textField = label
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// A menu-style selection: a rounded accent-coloured bar, as in NSMenu,
/// even though the panel never becomes key.
private final class SlashRowView: NSTableRowView {
    override var isEmphasized: Bool { get { true } set {} }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}
