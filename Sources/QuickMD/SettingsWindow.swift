import AppKit

/// QuickMD › Settings… (⌘,): four panes in a toolbar, as Mac settings
/// windows go: Appearance, Writing, Writing Aids, General. Every control
/// writes straight to `Settings`; the panes follow changes made from the
/// menus too.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = SettingsTabsController()
        tabs.tabStyle = .toolbar
        for pane in SettingsPane.allCases {
            let controller = SettingsPaneController(pane)
            // The tab controller copies the pane's title into the window's;
            // without one the window reads "Untitled".
            controller.title = pane.title
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.title = L("Settings")
        window.appearance = NSAppearance(named: Settings.theme.appearanceName)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        tabs.fitWindow(animated: false)
        window.center()
        window.setFrameAutosaveName("QuickMDSettings")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // The default app may have changed in another app while closed.
        NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Sizes the window to each pane as it's chosen, keeping its top edge.
@MainActor
private final class SettingsTabsController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func fitWindow(animated: Bool) {
        guard let window = view.window,
              let pane = tabViewItems[safe: selectedTabViewItemIndex]?.viewController else { return }
        let size = pane.view.fittingSize
        window.title = tabViewItems[selectedTabViewItemIndex].label
        let content = window.contentRect(forFrameRect: window.frame)
        var frame = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.maxY - size.height, width: size.width, height: size.height))
        frame.origin.y = window.frame.maxY - frame.height
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private enum SettingsPane: CaseIterable {
    case appearance, writing, aids, general

    var title: String {
        switch self {
        case .appearance: return L("Appearance")
        case .writing: return L("Writing")
        case .aids: return L("Writing Aids")
        case .general: return L("General")
        }
    }

    var symbol: String {
        switch self {
        case .appearance: return "textformat"
        case .writing: return "pencil.line"
        case .aids: return "text.badge.checkmark"
        case .general: return "gearshape"
        }
    }
}

/// One pane: a two-column form, labels right-aligned, each switch with
/// one line of secondary text under it.
@MainActor
private final class SettingsPaneController: NSViewController {
    private let pane: SettingsPane
    private var observer: Any?
    private let grid = NSGridView()
    /// Re-reads every control from `Settings`.
    private var refreshers: [() -> Void] = []

    init(_ pane: SettingsPane) {
        self.pane = pane
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func loadView() {
        grid.rowSpacing = 0
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -32),
            root.widthAnchor.constraint(equalToConstant: 520),
        ])
        view = root

        switch pane {
        case .appearance: buildAppearance()
        case .writing: buildWriting()
        case .aids: buildAids()
        case .general: buildGeneral()
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: .editorSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        view.frame.size = view.fittingSize
    }

    private func refresh() {
        refreshers.forEach { $0() }
        // The pane uses the same forced appearance as the editor.
        view.window?.appearance = NSAppearance(named: Settings.theme.appearanceName)
    }

    // MARK: Panes

    private func buildAppearance() {
        let theme = segmented(ThemePreference.allCases.map(\.displayName),
                              get: { ThemePreference.allCases.firstIndex(of: Settings.themePreference) ?? 0 },
                              set: { Settings.themePreference = ThemePreference.allCases[$0] })
        row(L("Appearance"), theme)
        row(L("Light page"), popUp(LightPage.allCases, \.displayName, get: { Settings.lightPage }, set: { Settings.lightPage = $0 }))
        row(L("Dark page"), popUp(DarkPage.allCases, \.displayName, get: { Settings.darkPage }, set: { Settings.darkPage = $0 }))
        gap()
        row(L("Writing font"), popUp(WritingFont.allCases, \.displayName, get: { Settings.writingFont }, set: { Settings.writingFont = $0 }))
        note(L("Duo keeps the body monospaced with proportional headings. Code is always monospaced."))

        let size = NSStepper()
        size.minValue = Double(Settings.sizeRange.lowerBound)
        size.maxValue = Double(Settings.sizeRange.upperBound)
        size.increment = 1
        size.setAccessibilityLabel(L("Text size"))
        let sizeLabel = NSTextField(labelWithString: "")
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        bind(size) { Settings.fontSize = CGFloat(($0 as! NSStepper).doubleValue) }
        refreshers.append {
            size.doubleValue = Double(Settings.fontSize)
            sizeLabel.stringValue = String(format: L("%d pt"), Int(Settings.fontSize))
        }
        let sizeRow = NSStackView(views: [sizeLabel, size])
        sizeRow.spacing = 6
        row(L("Text size"), sizeRow)

        let width = segmented(LineWidth.allCases.map(\.displayName),
                              get: { LineWidth.allCases.firstIndex(of: Settings.lineWidth) ?? 1 },
                              set: { Settings.lineWidth = LineWidth.allCases[$0] })
        row(L("Line width"), width)
    }

    private func buildWriting() {
        row(L("Focus"), popUp(FocusScope.allCases, \.displayName, get: { Settings.focusScope }, set: { Settings.focusScope = $0 }))
        note(L("What View › Focus keeps bright."))
        toggle(L("Typewriter"), L("Keep the caret’s line in the middle of the window."),
               get: { Settings.typewriterMode }, set: { Settings.typewriterMode = $0 })
        toggle(L("Fade window controls while typing"), L("The title bar and tabs come back when the mouse moves."),
               get: { Settings.fadesChrome }, set: { Settings.fadesChrome = $0 })
        toggle(L("Smart quotes and dashes"), L("Curly quotes and en and em dashes as you type, never in code."),
               get: { Settings.smartPunctuation }, set: { Settings.smartPunctuation = $0 })
        toggle(L("Book paragraphs"), L("Indent first lines and close the gap between paragraphs. The file is unchanged."),
               get: { Settings.bookParagraphs }, set: { Settings.bookParagraphs = $0 })
        toggle(L("Show Markdown syntax"), L("Show every mark, dimmed, instead of hiding them."),
               get: { Settings.showsSyntax }, set: { Settings.showsSyntax = $0 })
        gap()
        row(L("Count"), popUp(CountStyle.allCases, \.displayName, get: { Settings.countStyle }, set: { Settings.countStyle = $0 }))
        toggle(L("Show count in the title bar"), L("Under the note’s name, for the selection when there is one."),
               get: { Settings.showsWordCount }, set: { Settings.showsWordCount = $0 })

        let speed = NSStepper()
        speed.minValue = Double(Settings.readingSpeedRange.lowerBound)
        speed.maxValue = Double(Settings.readingSpeedRange.upperBound)
        speed.increment = 10
        speed.setAccessibilityLabel(L("Reading speed"))
        let speedLabel = NSTextField(labelWithString: "")
        speedLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        bind(speed) { Settings.readingSpeed = Int(($0 as! NSStepper).doubleValue) }
        refreshers.append {
            speed.integerValue = Settings.readingSpeed
            speedLabel.stringValue = String(format: L("%d words a minute"), Settings.readingSpeed)
        }
        let speedRow = NSStackView(views: [speedLabel, speed])
        speedRow.spacing = 6
        row(L("Reading speed"), speedRow)
    }

    private func buildAids() {
        toggle(L("Show writing aids"), L("Dotted underlines, on this Mac only. Also in View › Show Writing Aids."),
               get: { Settings.showsWritingAids }, set: { Settings.showsWritingAids = $0 })
        gap()
        for kind in WritingAids.Kind.allCases {
            let box = toggle(kind.displayName, kind.explanation, get: { Settings.writingAids.contains(kind) }, set: { on in
                var aids = Settings.writingAids
                if on { aids.insert(kind) } else { aids.remove(kind) }
                Settings.writingAids = aids
            })
            refreshers.append { box.isEnabled = Settings.showsWritingAids }
        }
    }

    private func buildGeneral() {
        toggle(L("Open documents in tabs"), L("Another file opens as a tab in the front window."),
               get: { Settings.opensInTabs }, set: { Settings.opensInTabs = $0 })
        toggle(L("Watch agents write live"), L("Changes another app writes into an open note type themselves in."),
               get: { Settings.liveWriting }, set: { Settings.liveWriting = $0 })
        gap()
        let starter = popUp(Starter.allCases, \.displayName, get: { Settings.newDocumentStarter }, set: { Settings.newDocumentStarter = $0 })
        starter.setAccessibilityLabel(L("New document"))
        row(L("New document"), starter)
        let defaultApp = NSButton(
            title: L("Make Default for .md"), target: NSApp.delegate, action: #selector(AppDelegate.makeDefault(_:))
        )
        refreshers.append {
            defaultApp.title = AppDelegate.isDefaultApp ? L("Default for .md") : L("Make Default for .md")
            defaultApp.isEnabled = !AppDelegate.isDefaultApp
        }
        row(L("Default app"), defaultApp)
    }

    // MARK: Building blocks

    private func row(_ title: String, _ content: NSView) {
        let label = NSTextField(labelWithString: title + ":")
        let row = grid.addRow(with: [label, content])
        row.yPlacement = .center
        row.topPadding = grid.numberOfRows > 1 ? 12 : 0
    }

    /// A switch, its one-line description under it.
    @discardableResult
    private func toggle(_ title: String, _ detail: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        bind(box) { set(($0 as! NSButton).state == .on) }
        refreshers.append { box.state = get() ? .on : .off }
        let row = grid.addRow(with: [NSGridCell.emptyContentView, box])
        row.topPadding = grid.numberOfRows > 1 ? 12 : 0
        note(detail, indent: true)
        return box
    }

    private func note(_ text: String, indent: Bool = false) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 320
        label.isSelectable = false
        let content: NSView
        if indent {
            // In line with the switch's title, past its box.
            let holder = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                label.topAnchor.constraint(equalTo: holder.topAnchor),
                label.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            ])
            content = holder
        } else {
            content = label
        }
        let row = grid.addRow(with: [NSGridCell.emptyContentView, content])
        row.topPadding = 2
    }

    /// Extra air between groups of rows.
    private func gap() {
        guard grid.numberOfRows > 0 else { return }
        grid.row(at: grid.numberOfRows - 1).bottomPadding = 12
    }

    private func segmented(_ labels: [String], get: @escaping () -> Int, set: @escaping (Int) -> Void) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
        bind(control) { set(($0 as! NSSegmentedControl).selectedSegment) }
        refreshers.append { control.selectedSegment = get() }
        return control
    }

    private func popUp<T: RawRepresentable>(
        _ cases: [T], _ name: KeyPath<T, String>, get: @escaping () -> T, set: @escaping (T) -> Void
    ) -> NSPopUpButton where T.RawValue == String {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        for value in cases {
            button.addItem(withTitle: value[keyPath: name])
            button.lastItem?.representedObject = value.rawValue
        }
        bind(button) { sender in
            if let raw = (sender as! NSPopUpButton).selectedItem?.representedObject as? String, let value = T(rawValue: raw) { set(value) }
        }
        refreshers.append {
            let current = get().rawValue
            if let item = button.itemArray.first(where: { $0.representedObject as? String == current }) { button.select(item) }
        }
        return button
    }

    // MARK: Actions

    private var actions: [ObjectIdentifier: (NSControl) -> Void] = [:]

    private func bind(_ control: NSControl, _ action: @escaping (NSControl) -> Void) {
        actions[ObjectIdentifier(control)] = action
        control.target = self
        control.action = #selector(controlChanged(_:))
    }

    @objc private func controlChanged(_ sender: NSControl) {
        actions[ObjectIdentifier(sender)]?(sender)
    }
}
