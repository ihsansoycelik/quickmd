import AppKit

/// QuickMD › Settings… (⌘,): General and Appearance panes. Every
/// control writes straight to `Settings`, so open windows restyle as
/// you change things; the panes also follow changes made from menus.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let general = NSTabViewItem(viewController: GeneralSettingsViewController())
        general.label = "General"
        general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        let appearance = NSTabViewItem(viewController: AppearanceSettingsViewController())
        appearance.label = "Appearance"
        appearance.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        tabs.addTabViewItem(general)
        tabs.addTabViewItem(appearance)
        tabs.selectedTabViewItemIndex = 1

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        window.setFrameAutosaveName("QuickMDSettings")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Shared layout helpers for the panes.
@MainActor
private class SettingsPane: NSViewController {
    private var observer: Any?
    let grid = NSGridView()

    override func loadView() {
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            root.widthAnchor.constraint(equalToConstant: 520),
        ])
        view = root
        build()
        if grid.numberOfColumns > 0 {
            grid.column(at: 0).xPlacement = .trailing
        }
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: .editorSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func build() {}
    func refresh() {}

    func row(_ title: String, _ views: NSView...) {
        let label = NSTextField(labelWithString: title.isEmpty ? "" : title + ":")
        let content: NSView
        if views.count == 1 {
            content = views[0]
        } else {
            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.spacing = 8
            content = stack
        }
        let row = grid.addRow(with: [label, content])
        row.yPlacement = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
    }

    func spacer() {
        let row = grid.addRow(with: [NSView(), NSView()])
        row.height = 4
    }

    func note(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 340
        grid.addRow(with: [NSView(), label])
    }

    func checkbox(_ title: String, _ action: Selector) -> NSButton {
        NSButton(checkboxWithTitle: title, target: self, action: action)
    }

    func popup(_ action: Selector) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = self
        button.action = action
        return button
    }

    /// Fills a font popup: curated faces drawn in their own type, then
    /// every other installed family under "More Fonts".
    func fillFonts(_ button: NSPopUpButton, defaultTitle: String?) {
        let menu = NSMenu()
        if let defaultTitle {
            let item = NSMenuItem(title: defaultTitle, action: nil, keyEquivalent: "")
            item.representedObject = ""
            menu.addItem(item)
            menu.addItem(.separator())
        }
        for face in FontFace.curated {
            menu.addItem(fontItem(face))
        }
        menu.addItem(.separator())
        let more = NSMenu(title: "More Fonts")
        for face in FontFace.otherInstalled {
            let item = NSMenuItem(title: face.displayName, action: button.action, keyEquivalent: "")
            item.target = self
            item.representedObject = face.rawValue
            more.addItem(item)
        }
        let moreItem = NSMenuItem(title: "More Fonts", action: nil, keyEquivalent: "")
        moreItem.submenu = more
        menu.addItem(moreItem)
        button.menu = menu
    }

    func fontItem(_ face: FontFace) -> NSMenuItem {
        let item = NSMenuItem(title: face.displayName, action: nil, keyEquivalent: "")
        item.representedObject = face.rawValue
        if let font = face.font(size: 13) {
            item.attributedTitle = NSAttributedString(string: face.displayName, attributes: [.font: font])
        }
        return item
    }

    /// Selects `id` in a font popup, adding it if it came from "More Fonts".
    func select(_ id: String, in button: NSPopUpButton) {
        if let item = button.menu?.items.first(where: { ($0.representedObject as? String) == id && $0.submenu == nil }) {
            button.select(item)
            return
        }
        // A face from the More Fonts submenu: show it as a top-level item.
        let item = fontItem(FontFace(rawValue: id))
        item.tag = 99
        button.menu?.items.filter { $0.tag == 99 }.forEach { button.menu?.removeItem($0) }
        // After removing the last pick, so the index isn't stale.
        let index = (button.menu?.items.lastIndex { $0.isSeparatorItem }) ?? button.numberOfItems
        button.menu?.insertItem(item, at: index)
        button.select(item)
    }

    /// The id chosen from a font popup, whether from the top level or More Fonts.
    func chosenID(_ sender: Any?, _ button: NSPopUpButton) -> String {
        if let item = sender as? NSMenuItem, let id = item.representedObject as? String { return id }
        return button.selectedItem?.representedObject as? String ?? ""
    }
}

// MARK: - General

@MainActor
private final class GeneralSettingsViewController: SettingsPane {
    private lazy var tabs = checkbox("Open documents in tabs", #selector(toggleTabs(_:)))
    private lazy var starter = popup(#selector(chooseStarter(_:)))
    private lazy var outline = checkbox("Show outline in new windows", #selector(toggleOutline(_:)))
    private lazy var live = checkbox("Watch agents write live", #selector(toggleLive(_:)))
    private lazy var defaultApp = NSButton(title: "Make Default for .md", target: NSApp.delegate, action: #selector(AppDelegate.makeDefault(_:)))

    override func build() {
        row("Windows", tabs)
        note("Opening another Markdown file adds a tab to the front window instead of a new window.")
        spacer()
        for s in Starter.allCases {
            starter.addItem(withTitle: s.displayName)
            starter.lastItem?.representedObject = s.rawValue
            starter.lastItem?.image = NSImage(systemSymbolName: s.symbol, accessibilityDescription: nil)
        }
        row("New document", starter)
        note("File › New from Template offers all of them.")
        spacer()
        row("Sidebar", outline)
        spacer()
        row("Agents", live)
        note("When an agent or another app writes an open note, watch it type: the window comes forward, follows the new text and marks what arrived. ==Highlights== stand out.")
        spacer()
        row("Default app", defaultApp)
    }

    override func refresh() {
        live.state = Settings.liveWriting ? .on : .off
        tabs.state = Settings.opensInTabs ? .on : .off
        outline.state = Settings.showsOutline ? .on : .off
        if let item = starter.itemArray.first(where: { $0.representedObject as? String == Settings.newDocumentStarter.rawValue }) {
            starter.select(item)
        }
    }

    @objc func toggleTabs(_ sender: NSButton) { Settings.opensInTabs = sender.state == .on }
    @objc func toggleOutline(_ sender: NSButton) { Settings.showsOutline = sender.state == .on }
    @objc func toggleLive(_ sender: NSButton) { Settings.liveWriting = sender.state == .on }
    @objc func chooseStarter(_ sender: NSPopUpButton) {
        if let s = Starter(rawValue: sender.selectedItem?.representedObject as? String ?? "") { Settings.newDocumentStarter = s }
    }
}

// MARK: - Appearance

@MainActor
private final class AppearanceSettingsViewController: SettingsPane {
    private lazy var style = popup(#selector(chooseStyle(_:)))
    private lazy var bodyFont = popup(#selector(chooseBodyFont(_:)))
    private lazy var headingFont = popup(#selector(chooseHeadingFont(_:)))
    private lazy var size = NSSlider(value: 17, minValue: Double(Settings.sizeRange.lowerBound),
                                     maxValue: Double(Settings.sizeRange.upperBound), target: self, action: #selector(changeSize(_:)))
    private lazy var stepper = NSStepper()
    private let sizeLabel = NSTextField(labelWithString: "")
    private lazy var resetSize = NSButton(title: "Reset", target: self, action: #selector(resetSize(_:)))
    private lazy var theme = NSSegmentedControl(labels: ThemePreference.allCases.map(\.displayName), trackingMode: .selectOne,
                                                target: self, action: #selector(chooseTheme(_:)))
    private lazy var glass = NSSegmentedControl(labels: Transparency.allCases.map(\.displayName), trackingMode: .selectOne,
                                                target: self, action: #selector(chooseGlass(_:)))
    private lazy var readable = checkbox("Readable line width", #selector(toggleReadable(_:)))
    private lazy var footer = checkbox("Word count footer", #selector(toggleFooter(_:)))
    private let sample = NSTextView()

    override func build() {
        for template in Template.allCases {
            style.addItem(withTitle: template.displayName)
            style.lastItem?.representedObject = template.rawValue
        }
        row("Style", style)
        spacer()
        fillFonts(bodyFont, defaultTitle: nil)
        row("Body font", bodyFont)
        fillFonts(headingFont, defaultTitle: "Style Default")
        row("Heading font", headingFont)

        size.numberOfTickMarks = 0
        size.widthAnchor.constraint(equalToConstant: 180).isActive = true
        stepper.minValue = size.minValue
        stepper.maxValue = size.maxValue
        stepper.increment = 1
        stepper.target = self
        stepper.action = #selector(changeSize(_:))
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        sizeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        resetSize.bezelStyle = .rounded
        resetSize.controlSize = .small
        row("Text size", size, stepper, sizeLabel, resetSize)
        note("⌘+ and ⌘− change it from any window.")

        sample.isEditable = false
        sample.isSelectable = false
        sample.drawsBackground = true
        sample.textContainerInset = NSSize(width: 14, height: 12)
        sample.wantsLayer = true
        sample.layer?.cornerRadius = 8
        sample.layer?.borderWidth = 1
        sample.layer?.borderColor = NSColor.separatorColor.cgColor
        sample.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sample.widthAnchor.constraint(equalToConstant: 340),
            sample.heightAnchor.constraint(equalToConstant: 128),
        ])
        row("", sample)
        spacer()
        row("Appearance", theme)
        row("Transparency", glass)
        spacer()
        row("Layout", readable)
        row("", footer)
    }

    override func refresh() {
        if let item = style.itemArray.first(where: { $0.representedObject as? String == Settings.template.rawValue }) {
            style.select(item)
        }
        select(Settings.fontFace.rawValue, in: bodyFont)
        select(Settings.headingFace?.rawValue ?? "", in: headingFont)
        if let first = headingFont.itemArray.first {
            first.title = "Style Default (\(Settings.template == .invisible ? "Myeongjo" : "Bold Body"))"
        }
        let value = Double(Settings.fontSize)
        size.doubleValue = value
        stepper.doubleValue = value
        sizeLabel.stringValue = "\(Int(value)) pt"
        resetSize.isEnabled = Settings.fontSize != Settings.template.defaultSize
        theme.selectedSegment = ThemePreference.allCases.firstIndex(of: Settings.themePreference) ?? 0
        glass.selectedSegment = Transparency.allCases.firstIndex(of: Settings.transparency) ?? 0
        readable.state = Settings.readableWidth ? .on : .off
        footer.state = Settings.showsStatusBar ? .on : .off
        updateSample()
    }

    /// A heading and a paragraph styled as the editor styles them, with
    /// the Markdown marks left out as reading mode does.
    private func updateSample() {
        let text = "## Heading\nThe quick brown fox jumps over the lazy dog. **Bold**, *italic* and `code`.\n"
        let styled = NSTextStorage(string: text)
        MarkdownStyler.restyle(styled, face: Settings.fontFace, size: Settings.fontSize, theme: Settings.theme,
                               template: Settings.template, headingFace: Settings.headingFace)
        let storage = NSMutableAttributedString()
        styled.enumerateAttribute(.qmSyntax, in: NSRange(location: 0, length: styled.length)) { value, run, _ in
            if value == nil { storage.append(styled.attributedSubstring(from: run)) }
        }
        sample.textStorage?.setAttributedString(storage)
        sample.appearance = NSAppearance(named: Settings.theme.appearanceName)
        sample.backgroundColor = Settings.theme == .dark ? NSColor(white: 0.13, alpha: 1) : .white
    }

    @objc func chooseStyle(_ sender: NSPopUpButton) {
        if let t = Template(rawValue: sender.selectedItem?.representedObject as? String ?? "") { Settings.template = t }
    }
    @objc func chooseBodyFont(_ sender: Any?) {
        let id = chosenID(sender, bodyFont)
        if !id.isEmpty { Settings.fontFace = FontFace(rawValue: id) }
    }
    @objc func chooseHeadingFont(_ sender: Any?) {
        let id = chosenID(sender, headingFont)
        Settings.headingFace = id.isEmpty ? nil : FontFace(rawValue: id)
    }
    @objc func changeSize(_ sender: NSControl) { Settings.fontSize = CGFloat(sender.doubleValue.rounded()) }
    @objc func resetSize(_ sender: Any?) { Settings.fontSize = Settings.template.defaultSize }
    @objc func chooseTheme(_ sender: NSSegmentedControl) { Settings.themePreference = ThemePreference.allCases[sender.selectedSegment] }
    @objc func chooseGlass(_ sender: NSSegmentedControl) { Settings.transparency = Transparency.allCases[sender.selectedSegment] }
    @objc func toggleReadable(_ sender: NSButton) { Settings.readableWidth = sender.state == .on }
    @objc func toggleFooter(_ sender: NSButton) { Settings.showsStatusBar = sender.state == .on }
}
