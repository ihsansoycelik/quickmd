import AppKit

/// View › Go to Heading: a small floating search over the note's
/// headings, indented by level. Typing filters, ↑↓ pick, Return jumps
/// (the heading a third of the way down, the caret at its text), Esc
/// or a click elsewhere closes.
@MainActor
final class OutlinePanel: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = OutlinePanel()

    private var panel: OutlineWindow?
    private let card = NSView()
    private let well = NSView()
    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private weak var textView: MarkdownTextView?
    private var headings: [Headings.Heading] = []
    private var shown: [Headings.Heading] = []
    private var topLevel = 1
    private var resignObserver: Any?

    private static let width: CGFloat = 380
    private static let rowHeight: CGFloat = 28
    private static let maxRows = 10
    private static let inset: CGFloat = 6
    private static let fieldHeight: CGFloat = 36
    /// Room around the card for its shadow.
    private static let margin: CGFloat = 12

    /// Headings whose title holds `query`, case and accents ignored.
    static func filter(_ headings: [Headings.Heading], _ query: String) -> [Headings.Heading] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return headings }
        return headings.filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    func show(for textView: MarkdownTextView) {
        let found = Headings.find(in: textView.string)
        guard !found.isEmpty, let window = textView.window else { return NSSound.beep() }
        self.textView = textView
        headings = found
        topLevel = found.map(\.level).min() ?? 1
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        field.stringValue = ""
        shown = headings
        table.reloadData()
        // Start on the caret's own section.
        let caret = textView.selectedRange().location
        select(shown.lastIndex(where: { $0.location <= caret }) ?? 0)
        style(for: window)
        place(over: window)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.close(refocus: false) } }
    }

    func close(refocus: Bool = true) {
        guard let panel, panel.isVisible else { return }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        let parent = panel.parent
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if refocus, let parent { parent.makeKeyAndOrderFront(nil) }
    }

    private func jump(to row: Int) {
        guard shown.indices.contains(row), let textView else { return close() }
        let heading = shown[row]
        close()
        let ns = textView.string as NSString
        guard heading.location <= ns.length else { return }
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: heading.location, length: 0)))
        let start = heading.location + BlockEditing.headingContentStart(line)
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: min(start, ns.length), length: 0))
        // The heading a third of the way down the window.
        guard let layout = textView.layoutManager, let clip = textView.enclosingScrollView?.contentView, ns.length > 0 else { return }
        let glyph = layout.glyphIndexForCharacter(at: min(heading.location, ns.length - 1))
        layout.ensureLayout(forGlyphRange: NSRange(location: 0, length: glyph + 1))
        let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        var origin = clip.bounds.origin
        origin.y = rect.minY + textView.textContainerOrigin.y - clip.bounds.height / 3
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        textView.enclosingScrollView?.reflectScrolledClipView(clip)
    }

    private func select(_ row: Int) {
        guard shown.indices.contains(row) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: Field

    func controlTextDidChange(_ obj: Notification) {
        shown = Self.filter(headings, field.stringValue)
        table.reloadData()
        select(0)
        if let window = textView?.window { place(over: window) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            if !shown.isEmpty { select((table.selectedRow - 1 + shown.count) % shown.count) }
        case #selector(NSResponder.moveDown(_:)):
            if !shown.isEmpty { select((table.selectedRow + 1) % shown.count) }
        case #selector(NSResponder.insertNewline(_:)):
            shown.isEmpty ? NSSound.beep() : jump(to: max(0, table.selectedRow))
        case #selector(NSResponder.cancelOperation(_:)):
            close()
        default:
            return false
        }
        return true
    }

    // MARK: Panel

    private func makePanel() -> OutlineWindow {
        let panel = OutlineWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        // The card draws its own crisp shadow; the window's is too soft.
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.animationBehavior = .none

        let root = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)

        well.wantsLayer = true
        well.layer?.cornerRadius = 6
        well.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(well)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = L("Go to heading")
        field.delegate = self
        field.cell?.isScrollable = true
        field.setAccessibilityLabel(L("Go to heading"))
        field.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(field)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.focusRingType = .none
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked(_:))
        table.setAccessibilityLabel(L("Headings"))

        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll)

        let m = Self.margin, i = Self.inset
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: root.topAnchor, constant: m),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -m),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),
            well.topAnchor.constraint(equalTo: card.topAnchor, constant: i),
            well.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: i),
            well.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -i),
            well.heightAnchor.constraint(equalToConstant: Self.fieldHeight),
            field.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: well.bottomAnchor, constant: i),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: i),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -i),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -i),
        ])
        panel.contentView = root
        return panel
    }

    /// Light: a white card, a fine ring and a crisp drop. Dark: one step
    /// above the page with a lighter 0.5px outline and a tight black drop.
    private func style(for window: NSWindow) {
        guard let panel, let layer = card.layer else { return }
        panel.appearance = window.appearance ?? NSAppearance(named: Settings.theme.appearanceName)
        let dark = Settings.theme == .dark
        let palette = Palette.for(Settings.theme)
        layer.backgroundColor = (dark ? srgb(0x252422) : .white).cgColor
        layer.borderWidth = dark ? 0.5 : 1
        layer.borderColor = (dark ? srgb(0x3B3935) : srgb(0x000000, 0.08)).cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = dark ? 0.5 : 0.16
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: -3)
        well.layer?.backgroundColor = (dark ? srgb(0xFFF6E6, 0.06) : palette.codeBackground).cgColor
        field.textColor = palette.strong
    }

    /// Centred over the note, near the top, sized to its rows.
    private func place(over window: NSWindow) {
        guard let panel else { return }
        let rows = CGFloat(max(1, min(shown.count, Self.maxRows)))
        let height = Self.fieldHeight + rows * Self.rowHeight + Self.inset * 3 + Self.margin * 2
        let width = Self.width + Self.margin * 2
        let frame = window.frame
        let top = window.contentLayoutRect.maxY + frame.minY - 56 + Self.margin
        let origin = NSPoint(x: (frame.midX - width / 2).rounded(), y: (top - height).rounded())
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    @objc private func clicked(_ sender: Any?) {
        if table.clickedRow >= 0 { jump(to: table.clickedRow) }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { OutlineRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("OutlineCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? OutlineCell ?? OutlineCell(id)
        let heading = shown[row]
        let depth = heading.level - topLevel
        cell.textField?.stringValue = heading.title
        // Hierarchy by ink and indent, not weight.
        cell.textField?.textColor = depth == 0 ? .labelColor : .secondaryLabelColor
        cell.indent.constant = 10 + CGFloat(min(depth, 5)) * 14
        cell.setAccessibilityLabel(String(format: L("Heading %d"), heading.level) + ", " + heading.title)
        return cell
    }
}

/// A borderless panel that still takes the keyboard, for the search field.
final class OutlineWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class OutlineCell: NSTableCellView {
    /// The label's leading inset: deeper headings sit further in.
    private(set) var indent: NSLayoutConstraint!

    init(_ id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        indent = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
        NSLayoutConstraint.activate([
            indent,
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The highlighted row: one step above the card, no accent bar.
private final class OutlineRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.055)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}

extension MarkdownTextView {
    @objc func goToHeading(_ sender: Any?) { OutlinePanel.shared.show(for: self) }
}
