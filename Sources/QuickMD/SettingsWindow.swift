import AppKit

/// QuickMD › Settings… (⌘,): one short pane. The look is fixed, so
/// there is little to set: text size, light or dark, and how files open.
/// Every control writes straight to `Settings`; the pane follows changes
/// made from the menus too.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentViewController: SettingsViewController())
        window.styleMask = [.titled, .closable]
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        window.setFrameAutosaveName("QuickMDSettings")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

@MainActor
private final class SettingsViewController: NSViewController {
    private var observer: Any?
    private let grid = NSGridView()

    private lazy var size = NSStepper()
    private let sizeLabel = NSTextField(labelWithString: "")
    private lazy var theme = NSSegmentedControl(
        labels: ThemePreference.allCases.map(\.displayName), trackingMode: .selectOne,
        target: self, action: #selector(chooseTheme(_:))
    )
    private lazy var tabs = NSButton(checkboxWithTitle: "Open documents in tabs", target: self, action: #selector(toggleTabs(_:)))
    private lazy var live = NSButton(checkboxWithTitle: "Watch agents write live", target: self, action: #selector(toggleLive(_:)))
    private lazy var starter = NSPopUpButton(frame: .zero, pullsDown: false)
    private lazy var defaultApp = NSButton(
        title: "Make Default for .md", target: NSApp.delegate, action: #selector(AppDelegate.makeDefault(_:))
    )

    override func loadView() {
        grid.rowSpacing = 14
        grid.columnSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            root.widthAnchor.constraint(equalToConstant: 460),
        ])
        view = root

        size.minValue = Double(Settings.sizeRange.lowerBound)
        size.maxValue = Double(Settings.sizeRange.upperBound)
        size.increment = 1
        size.target = self
        size.action = #selector(changeSize(_:))
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let sizeRow = NSStackView(views: [sizeLabel, size])
        sizeRow.spacing = 6

        for s in Starter.allCases {
            starter.addItem(withTitle: s.displayName)
            starter.lastItem?.representedObject = s.rawValue
        }
        starter.target = self
        starter.action = #selector(chooseStarter(_:))

        row("Text size", sizeRow)
        row("Appearance", theme)
        row("Windows", tabs)
        row("New document", starter)
        row("Agents", live)
        row("Default app", defaultApp)
        grid.column(at: 0).xPlacement = .trailing

        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: .editorSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func row(_ title: String, _ content: NSView) {
        let label = NSTextField(labelWithString: title + ":")
        grid.addRow(with: [label, content]).yPlacement = .center
    }

    private func refresh() {
        size.doubleValue = Double(Settings.fontSize)
        sizeLabel.stringValue = "\(Int(Settings.fontSize)) pt"
        theme.selectedSegment = ThemePreference.allCases.firstIndex(of: Settings.themePreference) ?? 0
        tabs.state = Settings.opensInTabs ? .on : .off
        live.state = Settings.liveWriting ? .on : .off
        if let item = starter.itemArray.first(where: { $0.representedObject as? String == Settings.newDocumentStarter.rawValue }) {
            starter.select(item)
        }
    }

    @objc private func changeSize(_ sender: NSStepper) { Settings.fontSize = CGFloat(sender.doubleValue) }
    @objc private func chooseTheme(_ sender: NSSegmentedControl) {
        Settings.themePreference = ThemePreference.allCases[sender.selectedSegment]
    }
    @objc private func toggleTabs(_ sender: NSButton) { Settings.opensInTabs = sender.state == .on }
    @objc private func toggleLive(_ sender: NSButton) { Settings.liveWriting = sender.state == .on }
    @objc private func chooseStarter(_ sender: NSPopUpButton) {
        if let s = Starter(rawValue: sender.selectedItem?.representedObject as? String ?? "") { Settings.newDocumentStarter = s }
    }
}
