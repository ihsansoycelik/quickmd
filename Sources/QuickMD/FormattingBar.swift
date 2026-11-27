import AppKit

/// The block a line belongs to, as the formatting bar shows it. Pure, no AppKit.
struct LineStyle: Equatable {
    enum List: Equatable { case bullet, numbered, task }

    /// 0 for body text, 1…6 for an ATX heading.
    var heading = 0
    var list: List?
    var quote = false

    private static let quotePrefix = try! NSRegularExpression(pattern: #"^[ \t]*>[ \t]?"#)
    private static let headingPrefix = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})(?:[ \t]|$)"#)
    private static let taskPrefix = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\[[ xX]\](?:[ \t]|$)"#)
    private static let bulletPrefix = try! NSRegularExpression(pattern: #"^[ \t]*[-*+][ \t]"#)
    private static let numberPrefix = try! NSRegularExpression(pattern: #"^[ \t]*\d{1,9}[.)][ \t]"#)

    /// The style of one line of Markdown (no newline). Quote marks come
    /// off first, so a list or heading inside a quote is seen too.
    static func of(_ line: String) -> LineStyle {
        var style = LineStyle()
        var rest = line as NSString
        while let match = quotePrefix.firstMatch(in: rest as String, range: NSRange(location: 0, length: rest.length)) {
            style.quote = true
            rest = rest.substring(from: match.range.length) as NSString
        }
        let all = NSRange(location: 0, length: rest.length)
        let text = rest as String
        if let match = headingPrefix.firstMatch(in: text, range: all) {
            style.heading = match.range(at: 1).length
        } else if taskPrefix.firstMatch(in: text, range: all) != nil {
            style.list = .task
        } else if bulletPrefix.firstMatch(in: text, range: all) != nil {
            style.list = .bullet
        } else if numberPrefix.firstMatch(in: text, range: all) != nil {
            style.list = .numbered
        }
        return style
    }
}

/// The optional bar under the text (View › Show Formatting Bar): the
/// Format menu's common commands as quiet icons, the block style of the
/// caret's line, an insert menu, the word count and the Paper toggle.
/// Its buttons never take focus; every command goes to the text view.
final class FormattingBar: NSView {
    weak var textView: MarkdownTextView?

    private let iconRow = NSStackView()
    private let metaRow = NSStackView()
    private let hairline = NSView()
    private let styleButton = BarButton()
    private let metaLabel = NSTextField(labelWithString: "")
    private let paperButton = BarButton()
    private var listButtons: [LineStyle.List: BarButton] = [:]
    private var quoteButton: BarButton?
    private var allButtons: [BarButton] = []

    static let iconRowHeight: CGFloat = 36
    static let metaRowHeight: CGFloat = 22

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(L("Formatting bar"))

        let inline: [(String, String, Selector, String)] = [
            ("bold", "Bold", #selector(MarkdownTextView.toggleBold(_:)), "⌘B"),
            ("italic", "Italic", #selector(MarkdownTextView.toggleItalic(_:)), "⌘I"),
            ("strikethrough", "Strikethrough", #selector(MarkdownTextView.toggleStrikethrough(_:)), "⇧⌘X"),
            ("chevron.left.forwardslash.chevron.right", "Inline Code", #selector(MarkdownTextView.toggleInlineCode(_:)), "⇧⌘C"),
            ("link", "Link", #selector(MarkdownTextView.insertLink(_:)), "⌘K"),
        ]
        let lists: [(String, String, Selector, String, LineStyle.List)] = [
            ("list.bullet", "Bulleted List", #selector(MarkdownTextView.toggleBulletList(_:)), "⇧⌘L", .bullet),
            ("list.number", "Numbered List", #selector(MarkdownTextView.toggleNumberedList(_:)), "⇧⌘O", .numbered),
            ("checklist", "Task List", #selector(MarkdownTextView.toggleTaskList(_:)), "⇧⌘T", .task),
        ]
        let blocks: [(String, String, Selector, String)] = [
            ("text.quote", "Quote", #selector(MarkdownTextView.toggleQuote(_:)), "⌘'"),
            ("curlybraces", "Code Block", #selector(MarkdownTextView.insertCodeBlock(_:)), "⌥⇧⌘C"),
            ("tablecells", "Table", #selector(MarkdownTextView.insertTable(_:)), "⌥⌘T"),
        ]

        func command(_ symbol: String, _ title: String, _ action: Selector, _ key: String) -> BarButton {
            let button = BarButton()
            button.symbol = symbol
            button.command = action
            let label = String(format: "%@ (%@)", L(title), key)
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.target = self
            button.action = #selector(sendCommand(_:))
            allButtons.append(button)
            return button
        }

        let inlineGroup = group(inline.map { command($0.0, $0.1, $0.2, $0.3) })

        styleButton.title = L("Body")
        styleButton.symbol = "chevron.down"
        styleButton.trailingSymbol = true
        styleButton.toolTip = L("Text Style")
        styleButton.setAccessibilityLabel(L("Text Style"))
        styleButton.target = self
        styleButton.action = #selector(showStyleMenu(_:))
        allButtons.append(styleButton)

        let listGroup = group(lists.map { item in
            let button = command(item.0, item.1, item.2, item.3)
            listButtons[item.4] = button
            return button
        })
        let blockButtons = blocks.map { command($0.0, $0.1, $0.2, $0.3) }
        quoteButton = blockButtons.first
        let blockGroup = group(blockButtons)

        let insert = BarButton()
        insert.symbol = "plus"
        insert.toolTip = L("Insert")
        insert.setAccessibilityLabel(L("Insert"))
        insert.target = self
        insert.action = #selector(showInsertMenu(_:))
        allButtons.append(insert)

        iconRow.orientation = .horizontal
        iconRow.spacing = 12
        iconRow.alignment = .centerY
        iconRow.detachesHiddenViews = true
        for (index, view) in [inlineGroup, styleButton, listGroup, blockGroup, insert].enumerated() {
            iconRow.addView(view, in: .leading)
            // A narrow window drops the last groups instead of squeezing them.
            iconRow.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: Float(1000 - index * 10)), for: view)
        }
        iconRow.setClippingResistancePriority(.defaultLow, for: .horizontal)

        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        paperButton.title = L("Paper")
        paperButton.symbol = "square"
        paperButton.isPill = true
        paperButton.toolTip = L("Paper background")
        paperButton.setAccessibilityLabel(L("Paper background"))
        paperButton.target = self
        paperButton.action = #selector(togglePaper(_:))
        allButtons.append(paperButton)

        metaRow.orientation = .horizontal
        metaRow.alignment = .centerY
        metaRow.addView(metaLabel, in: .leading)
        metaRow.addView(paperButton, in: .trailing)

        for view in [hairline, iconRow, metaRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        hairline.wantsLayer = true
        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
            iconRow.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            iconRow.heightAnchor.constraint(equalToConstant: Self.iconRowHeight - 4),
            iconRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            metaRow.topAnchor.constraint(equalTo: iconRow.bottomAnchor),
            metaRow.heightAnchor.constraint(equalToConstant: Self.metaRowHeight),
            metaRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            metaRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            metaRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func group(_ buttons: [BarButton]) -> NSStackView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 2
        return stack
    }

    // MARK: State

    /// "30 words · 1 min read", or empty when the count is off.
    var metaText: String {
        get { metaLabel.stringValue }
        set { if metaLabel.stringValue != newValue { metaLabel.stringValue = newValue } }
    }

    /// The style button's title, for tests.
    var styleTitle: String { styleButton.title }

    /// Shows the caret line's block style: its heading level, list and quote.
    func update(for style: LineStyle) {
        styleButton.title = style.heading == 0 ? L("Body") : String(format: L("Heading %d"), style.heading)
        for (kind, button) in listButtons { button.isActive = style.list == kind }
        quoteButton?.isActive = style.quote
        currentHeading = style.heading
    }

    private var currentHeading = 0

    func apply(_ palette: Palette, theme: Theme) {
        hairline.layer?.backgroundColor = palette.divider.cgColor
        metaLabel.textColor = palette.text.withAlphaComponent(0.7)
        paperButton.isActive = Settings.paperBackground
        paperButton.symbol = Settings.paperBackground ? "checkmark.square.fill" : "square"
        let colors = BarButton.Colors(
            ink: palette.text.withAlphaComponent(0.66), strong: palette.strong,
            hover: palette.text.withAlphaComponent(theme == .dark ? 0.09 : 0.06),
            pressed: palette.text.withAlphaComponent(theme == .dark ? 0.14 : 0.10),
            active: palette.text.withAlphaComponent(theme == .dark ? 0.12 : 0.08)
        )
        allButtons.forEach { $0.colors = colors }
    }

    // MARK: Actions

    @objc private func sendCommand(_ sender: BarButton) {
        guard let textView, let command = sender.command else { return }
        NSApp.sendAction(command, to: textView, from: sender)
        refocus()
    }

    @objc private func togglePaper(_ sender: Any?) {
        Settings.paperBackground.toggle()
        refocus()
    }

    @objc private func showStyleMenu(_ sender: BarButton) {
        guard let textView else { return }
        let menu = NSMenu()
        var current: NSMenuItem?
        for level in 0...4 {
            let title = level == 0 ? L("Body") : String(format: L("Heading %d"), level)
            let item = NSMenuItem(title: title, action: #selector(MarkdownTextView.setHeading(_:)),
                                  keyEquivalent: level == 0 ? "0" : "\(level)")
            item.keyEquivalentModifierMask = [.command, .option]
            item.tag = level
            item.target = textView
            menu.addItem(item)
            if level == currentHeading { current = item }
        }
        menu.popUp(positioning: current, at: NSPoint(x: 0, y: sender.bounds.height - 2), in: sender)
        sender.endHover()
        refocus()
    }

    @objc private func showInsertMenu(_ sender: BarButton) {
        guard let textView else { return }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, to target: NSMenu = menu) -> NSMenuItem {
            let item = NSMenuItem(title: L(title), action: action, keyEquivalent: "")
            item.target = textView
            target.addItem(item)
            return item
        }
        let callouts = NSMenu(title: L("Callout"))
        for kind in CalloutKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(MarkdownTextView.insertCallout(_:)), keyEquivalent: "")
            item.representedObject = kind.rawValue
            item.target = textView
            callouts.addItem(item)
        }
        let calloutItem = NSMenuItem(title: L("Callout"), action: nil, keyEquivalent: "")
        calloutItem.submenu = callouts
        menu.addItem(calloutItem)
        _ = add("Math Block", #selector(MarkdownTextView.insertMathBlock(_:)))
        _ = add("Mermaid Diagram", #selector(MarkdownTextView.insertDiagram(_:)))
        _ = add("Footnote", #selector(MarkdownTextView.insertFootnote(_:)))
        _ = add("Today’s Date", #selector(MarkdownTextView.insertTodaysDate(_:)))
        _ = add("Horizontal Rule", #selector(MarkdownTextView.insertHorizontalRule(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        sender.endHover()
        refocus()
    }

    private func refocus() {
        guard let textView, let window = textView.window, window.firstResponder !== textView else { return }
        window.makeFirstResponder(textView)
    }
}

/// A quiet bar button: an SF Symbol (and an optional title) in
/// secondary ink, a soft fill on hover, press and while active.
final class BarButton: NSControl {
    struct Colors {
        var ink: NSColor = .secondaryLabelColor
        var strong: NSColor = .labelColor
        var hover: NSColor = .quaternaryLabelColor
        var pressed: NSColor = .tertiaryLabelColor
        var active: NSColor = .quaternaryLabelColor
    }

    var colors = Colors() { didSet { refresh() } }
    var symbol: String? { didSet { rebuild() } }
    var title = "" { didSet { rebuild() } }
    /// The symbol after the title (a chevron), not before it.
    var trailingSymbol = false { didSet { rebuild() } }
    /// A small, fully round pill (the Paper toggle) instead of a 28px square.
    var isPill = false { didSet { rebuild() } }
    var isActive = false { didSet { if oldValue != isActive { refresh() } } }
    var command: Selector?

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var hovering = false { didSet { refresh() } }
    private var pressing = false { didSet { refresh() } }
    private var sizeConstraints: [NSLayoutConstraint] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        refusesFirstResponder = true
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func rebuild() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if let symbol {
            let small = !title.isEmpty
            let config = NSImage.SymbolConfiguration(pointSize: small ? 10 : 13, weight: .regular)
            imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        label.stringValue = title
        let views: [NSView] = [symbol == nil ? nil : imageView, title.isEmpty ? nil : label].compactMap { $0 }
        (trailingSymbol ? views.reversed() : views).forEach(stack.addArrangedSubview)
        NSLayoutConstraint.deactivate(sizeConstraints)
        let height: CGFloat = isPill ? 20 : 28
        sizeConstraints = [heightAnchor.constraint(equalToConstant: height)]
        if title.isEmpty {
            sizeConstraints.append(widthAnchor.constraint(equalToConstant: 28))
        } else {
            sizeConstraints.append(widthAnchor.constraint(equalTo: stack.widthAnchor, constant: isPill ? 16 : 20))
        }
        NSLayoutConstraint.activate(sizeConstraints)
        layer?.cornerRadius = isPill ? height / 2 : 6
        setAccessibilityTitle(title.isEmpty ? nil : title)
        refresh()
    }

    private func refresh() {
        let fill: NSColor? = pressing ? colors.pressed : hovering ? colors.hover : isActive ? colors.active : nil
        layer?.backgroundColor = fill?.cgColor
        let ink = isActive ? colors.strong : colors.ink
        imageView.contentTintColor = ink
        label.textColor = ink
        if isPill { setAccessibilityValue(isActive ? "1" : "0") }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    /// A menu opened from the button swallows the mouse-exited event.
    func endHover() { hovering = false }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressing = true
        // Track until the button is let go; it fires only if released inside.
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            if next.type == .leftMouseUp {
                pressing = false
                if inside { sendAction(action, to: target) }
                return
            }
            pressing = inside
        }
        pressing = false
    }

    override func accessibilityPerformPress() -> Bool {
        sendAction(action, to: target)
        return true
    }
}
