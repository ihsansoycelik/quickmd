import AppKit
import CoreServices

/// The window's content: the optional file sidebar beside the editor.
/// Shown or hidden for every window at once (Settings.showsSidebar),
/// from View › Show Sidebar, the title bar button or the divider.
final class SidebarSplitController: NSSplitViewController {
    let sidebar = SidebarViewController()
    private let editor: EditorViewController
    private lazy var sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
    let titlebarAccessory = NSTitlebarAccessoryViewController()
    private let toggleButton = NSButton()
    /// Set once the window is on screen, so restoring the split's saved
    /// state at load never writes back to the setting.
    private var ready = false
    private var applying = false
    private var collapseObservation: NSKeyValueObservation?
    private var resizeObserver: Any?

    init(editor: EditorViewController) {
        self.editor = editor
        super.init(nibName: nil, bundle: nil)
        sidebar.focusEditor = { [weak editor] in
            guard let editor else { return }
            editor.view.window?.makeFirstResponder(editor.textView)
        }
        makeAccessory()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 360
        sidebarItem.canCollapse = true
        let editorItem = NSSplitViewItem(viewController: editor)
        editorItem.minimumThickness = 420
        addSplitViewItem(sidebarItem)
        addSplitViewItem(editorItem)
        splitView.autosaveName = "QuickMDSidebar"
        sidebarItem.isCollapsed = !Settings.showsSidebar

        // Dragging the divider shut (or AppKit's own toggle) is the setting too.
        collapseObservation = sidebarItem.observe(\.isCollapsed) { [weak self] _, _ in
            DispatchQueue.main.async { self?.syncFromSplit() }
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: splitView, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.syncFromSplit() } }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if sidebarItem.isCollapsed == Settings.showsSidebar { sidebarItem.isCollapsed = !Settings.showsSidebar }
        sidebar.isActive = Settings.showsSidebar
        updateButton()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        ready = true
    }

    /// Follows Settings.showsSidebar; called when settings change.
    func applySettings() {
        updateButton()
        let show = Settings.showsSidebar
        guard isViewLoaded, sidebarItem.isCollapsed == show else { return }
        if !show { returnFocusIfNeeded() }
        applying = true
        let animate = ready && view.window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate {
            NSAnimationContext.runAnimationGroup({ _ in
                sidebarItem.animator().isCollapsed = !show
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.applying = false }
            })
        } else {
            sidebarItem.isCollapsed = !show
            applying = false
        }
        sidebar.isActive = show
    }

    private func syncFromSplit() {
        guard ready, !applying else { return }
        let shown = !sidebarItem.isCollapsed
        if !shown { returnFocusIfNeeded() }
        sidebar.isActive = shown
        if shown != Settings.showsSidebar { Settings.showsSidebar = shown }
    }

    /// Hiding the sidebar while it has the keyboard hands it back to the editor.
    private func returnFocusIfNeeded() {
        guard let window = view.window, let responder = window.firstResponder else { return }
        var owner = responder as? NSView
        if let text = responder as? NSText, text.isFieldEditor, let field = text.delegate as? NSView { owner = field }
        if let owner, owner.isDescendant(of: sidebar.view) { sidebar.focusEditor?() }
    }

    // MARK: Title bar button

    private func makeAccessory() {
        toggleButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
        toggleButton.imagePosition = .imageOnly
        toggleButton.isBordered = false
        toggleButton.contentTintColor = .secondaryLabelColor
        toggleButton.target = self
        toggleButton.action = #selector(toggleFromButton(_:))
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        container.addSubview(toggleButton)
        NSLayoutConstraint.activate([
            toggleButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            toggleButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: 24),
            toggleButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        titlebarAccessory.view = container
        titlebarAccessory.layoutAttribute = .leading
        updateButton()
    }

    private func updateButton() {
        let title = Settings.showsSidebar ? L("Hide Sidebar") : L("Show Sidebar")
        toggleButton.toolTip = title
        toggleButton.setAccessibilityLabel(title)
    }

    @objc private func toggleFromButton(_ sender: Any?) { Settings.showsSidebar.toggle() }
}

/// A file or folder row. Folders load their children on first expand.
final class FileNode: NSObject {
    let url: URL
    let isFolder: Bool
    let name: String
    /// In filter results: the folder the note is in, relative to the root.
    let detail: String
    var children: [FileNode]?

    init(url: URL, isFolder: Bool, detail: String = "") {
        self.url = url
        self.isFolder = isFolder
        self.name = FileTree.displayName(of: url, isFolder: isFolder)
        self.detail = detail
    }

    var key: String { url.standardizedFileURL.path }
    lazy var realPath: String = SidebarViewController.realPath(url)
}

/// Return opens the selected row, as a click does.
final class SidebarOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, let onReturn {
            onReturn()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The notes in the current document's folder, as a tree, with a
/// filter field above it. Nothing is read from disk while it is hidden.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate,
    NSSearchFieldDelegate, NSMenuDelegate {

    var focusEditor: (() -> Void)?

    /// The window's document; its folder is the tree's root.
    var documentURL: URL? {
        didSet {
            guard documentURL?.standardizedFileURL != oldValue?.standardizedFileURL else { return }
            let newRoot = documentURL?.deletingLastPathComponent().standardizedFileURL
            if newRoot != root {
                if let root { expandedByRoot[root.path] = expanded }
                root = newRoot
                expanded = newRoot.flatMap { expandedByRoot[$0.path] } ?? []
                scanCache = nil
                reload()
            } else if isActive, isViewLoaded {
                revealCurrent(scroll: true)
            }
        }
    }

    /// True while the sidebar is shown: it lists and watches only then.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive { reload() } else { watcher = nil }
        }
    }

    private var root: URL?
    private var rootNodes: [FileNode] = []
    /// Filter results; nil shows the tree.
    private var matches: [FileNode]?
    private var query = ""
    private var expanded: Set<String> = []
    private var expandedByRoot: [String: Set<String>] = [:]
    private var restoring = false
    private var scanCache: [FileTree.Entry]?
    private var scanGeneration = 0
    private var filterTimer: Timer?
    private var watcher: FolderWatcher?

    private let header = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let outline = SidebarOutlineView()
    private let scrollView = NSScrollView()
    private let emptyImage = NSImageView()
    private let emptyTitle = NSTextField(wrappingLabelWithString: "")
    private let emptyDetail = NSTextField(wrappingLabelWithString: "")
    private let accessButton = NSButton()
    private let emptyStack = NSStackView()

    // MARK: Views

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))

        header.font = .systemFont(ofSize: 13)
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingMiddle
        header.translatesAutoresizingMaskIntoConstraints = false
        header.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let headerMenu = NSMenu()
        headerMenu.addItem(NSMenuItem(title: L("Show in Finder"), action: #selector(showRootInFinder(_:)), keyEquivalent: ""))
        headerMenu.items.forEach { $0.target = self }
        header.menu = headerMenu

        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        searchField.placeholderString = L("Filter")
        searchField.setAccessibilityLabel(L("Filter notes"))
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowHeight = 24
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked(_:))
        outline.onReturn = { [weak self] in self?.openSelected() }
        outline.setAccessibilityLabel(L("Notes"))
        let rowMenu = NSMenu()
        rowMenu.delegate = self
        outline.menu = rowMenu

        scrollView.documentView = outline
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyImage.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        emptyImage.contentTintColor = .tertiaryLabelColor
        for label in [emptyTitle, emptyDetail] {
            label.font = .systemFont(ofSize: 13)
            label.alignment = .center
            label.isSelectable = false
        }
        emptyTitle.textColor = .secondaryLabelColor
        emptyDetail.textColor = .tertiaryLabelColor
        accessButton.title = L("Allow Access…")
        accessButton.bezelStyle = .rounded
        accessButton.controlSize = .small
        accessButton.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        accessButton.target = self
        accessButton.action = #selector(allowAccess(_:))
        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 4
        [emptyImage, emptyTitle, emptyDetail, accessButton].forEach(emptyStack.addArrangedSubview)
        emptyStack.setCustomSpacing(8, after: emptyImage)
        emptyStack.setCustomSpacing(12, after: emptyDetail)
        emptyStack.translatesAutoresizingMaskIntoConstraints = false

        [header, searchField, scrollView, emptyStack].forEach(root.addSubview)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            searchField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            emptyStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            emptyStack.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -32),
            emptyTitle.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -32),
            emptyDetail.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -32),
        ])
        view = root

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(itemDidExpand(_:)), name: NSOutlineView.itemDidExpandNotification, object: outline)
        center.addObserver(self, selector: #selector(itemDidCollapse(_:)), name: NSOutlineView.itemDidCollapseNotification, object: outline)
        updateState()
    }

    // MARK: Loading

    private enum State { case untitled, noAccess, tree }

    private var state: State {
        guard let root else { return .untitled }
        return FolderAccess.canRead(root) ? .tree : .noAccess
    }

    /// Lists the root again from disk and starts watching it.
    private func reload() {
        guard isViewLoaded, isActive else { return }
        watcher = nil
        guard let root, state == .tree else {
            rootNodes = []
            matches = nil
            outline.reloadData()
            updateState()
            return
        }
        header.stringValue = FileManager.default.displayName(atPath: root.path)
        header.toolTip = root.path
        rebuildTree()
        watcher = FolderWatcher(root) { [weak self] paths in
            MainActor.assumeIsolated { self?.foldersChanged(paths) }
        }
        if !query.isEmpty { applyQuery() }
        revealCurrent(scroll: true)
        updateState()
    }

    private func rebuildTree() {
        guard let root else { return }
        restoring = true
        rootNodes = Self.nodes(in: root)
        if matches == nil { outline.reloadData() }
        restoreExpansion(rootNodes)
        restoring = false
    }

    private static func nodes(in folder: URL) -> [FileNode] {
        FileTree.list(folder).map { FileNode(url: $0.url, isFolder: $0.isFolder) }
    }

    private func children(of item: Any?) -> [FileNode] {
        if let matches { return item == nil ? matches : [] }
        guard let node = item as? FileNode else { return rootNodes }
        guard node.isFolder else { return [] }
        if node.children == nil { node.children = Self.nodes(in: node.url) }
        return node.children ?? []
    }

    private func restoreExpansion(_ nodes: [FileNode]) {
        guard matches == nil else { return }
        for node in nodes where node.isFolder && expanded.contains(node.key) {
            outline.expandItem(node)
            restoreExpansion(node.children ?? [])
        }
    }

    @objc private func itemDidExpand(_ note: Notification) {
        guard !restoring, matches == nil, let node = note.userInfo?["NSObject"] as? FileNode else { return }
        expanded.insert(node.key)
    }

    @objc private func itemDidCollapse(_ note: Notification) {
        guard !restoring, matches == nil, let node = note.userInfo?["NSObject"] as? FileNode else { return }
        expanded.remove(node.key)
    }

    /// The current note selected, its folders open, scrolled into view.
    /// Selecting never opens anything.
    private func revealCurrent(scroll: Bool) {
        guard isViewLoaded else { return }
        guard let doc = documentURL?.standardizedFileURL else { outline.deselectAll(nil); return }
        var target: FileNode?
        if let matches {
            target = matches.first { $0.key == doc.path }
        } else if let root {
            let base = root.standardizedFileURL.pathComponents
            let parts = doc.pathComponents
            if parts.count > base.count, Array(parts.prefix(base.count)) == base {
                var level = rootNodes
                for part in parts.dropFirst(base.count) {
                    guard let node = level.first(where: { $0.url.lastPathComponent == part }) else { break }
                    if node.isFolder {
                        outline.expandItem(node)
                        level = node.children ?? []
                    } else {
                        target = node
                    }
                }
            }
        }
        let row = target.map { outline.row(forItem: $0) } ?? -1
        if row >= 0 {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if scroll { outline.scrollRowToVisible(row) }
        } else {
            outline.deselectAll(nil)
        }
    }

    private func updateState() {
        let current = state
        let tree = current == .tree
        header.isHidden = !tree
        searchField.isHidden = !tree
        scrollView.isHidden = !tree
        accessButton.isHidden = current != .noAccess
        var symbol: String?
        switch current {
        case .untitled:
            symbol = "doc"
            emptyTitle.stringValue = L("This note isn’t saved yet")
            emptyDetail.stringValue = L("Save it to see the notes beside it.")
        case .noAccess:
            symbol = "lock"
            emptyTitle.stringValue = L("QuickMD can’t see this folder")
            emptyDetail.stringValue = L("Allow access to list the notes in it.")
        case .tree:
            if let matches, matches.isEmpty {
                symbol = "magnifyingglass"
                emptyTitle.stringValue = String(format: L("No notes match “%@”"), query)
                emptyDetail.stringValue = L("Try another name.")
            } else if matches == nil && rootNodes.isEmpty {
                symbol = "doc.text"
                emptyTitle.stringValue = L("No notes in this folder")
                emptyDetail.stringValue = L("Notes saved here show up in this list.")
            }
        }
        emptyStack.isHidden = symbol == nil
        emptyImage.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    }

    // MARK: Live updates

    static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// FSEvents reported these folders; reload only if a listed one really changed.
    private func foldersChanged(_ paths: [String]) {
        guard isActive, let root else { return }
        scanCache = nil
        if matches != nil { applyQuery() }
        let rootPath = Self.realPath(root)
        var loaded: [String: FileNode] = [:]
        func collect(_ nodes: [FileNode]) {
            for node in nodes where node.isFolder && node.children != nil {
                loaded[node.realPath] = node
                collect(node.children ?? [])
            }
        }
        collect(rootNodes)
        var changed = false
        for raw in Set(paths) {
            let path = raw.hasSuffix("/") && raw.count > 1 ? String(raw.dropLast()) : raw
            let current: [FileNode]
            let folder: URL
            if path == rootPath {
                current = rootNodes; folder = root
            } else if let node = loaded[path] {
                current = node.children ?? []; folder = node.url
            } else { continue }
            let fresh = FileTree.list(folder)
            if fresh.map(\.url.lastPathComponent) != current.map(\.url.lastPathComponent)
                || fresh.map(\.isFolder) != current.map(\.isFolder) {
                changed = true
                break
            }
        }
        guard changed else { return }
        let selected = (outline.item(atRow: outline.selectedRow) as? FileNode)?.key
        let origin = scrollView.contentView.bounds.origin
        rebuildTree()
        if let selected, matches == nil {
            var target: FileNode?
            func find(_ nodes: [FileNode]) {
                for node in nodes where target == nil {
                    if node.key == selected { target = node } else if let kids = node.children { find(kids) }
                }
            }
            find(rootNodes)
            let row = target.map { outline.row(forItem: $0) } ?? -1
            if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) } else { revealCurrent(scroll: false) }
        }
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateState()
    }

    // MARK: Filter

    @objc private func searchChanged(_ sender: Any?) { scheduleFilter() }

    func controlTextDidChange(_ obj: Notification) { scheduleFilter() }

    private func scheduleFilter() {
        filterTimer?.invalidate()
        filterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.query = self.searchField.stringValue.trimmingCharacters(in: .whitespaces)
                self.applyQuery()
            }
        }
    }

    private func applyQuery() {
        guard let root else { return }
        if query.isEmpty {
            scanGeneration += 1
            guard matches != nil else { return }
            matches = nil
            outline.reloadData()
            restoring = true
            restoreExpansion(rootNodes)
            restoring = false
            revealCurrent(scroll: true)
            updateState()
            return
        }
        if let scanCache {
            show(FileTree.filter(scanCache, query: query), root: root)
            return
        }
        scanGeneration += 1
        let generation = scanGeneration
        // Scanning a big folder can take a moment: off the main thread, the tree stays until results arrive.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let all = FileTree.scan(root)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.scanGeneration, self.root == root, !self.query.isEmpty else { return }
                    self.scanCache = all
                    self.show(FileTree.filter(all, query: self.query), root: root)
                }
            }
        }
    }

    private func show(_ entries: [FileTree.Entry], root: URL) {
        matches = entries.map { FileNode(url: $0.url, isFolder: false, detail: FileTree.relativeFolder(of: $0.url, root: root)) }
        outline.reloadData()
        revealCurrent(scroll: false)
        updateState()
    }

    private func clearFilter() {
        searchField.stringValue = ""
        filterTimer?.invalidate()
        query = ""
        applyQuery()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchField else { return false }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            if searchField.stringValue.isEmpty { focusEditor?() } else { clearFilter() }
            return true
        case #selector(NSResponder.moveDown(_:)):
            view.window?.makeFirstResponder(outline)
            if outline.selectedRow < 0, outline.numberOfRows > 0 {
                outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if let matches, let first = matches.first { open(first.url) }
            return true
        default:
            return false
        }
    }

    // MARK: Data source and delegate

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        matches == nil && (item as? FileNode)?.isFolder == true
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("FileCell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? makeCell(id)
        cell.imageView?.image = NSImage(systemSymbolName: node.isFolder ? "folder" : "doc.text", accessibilityDescription: nil)
        if node.detail.isEmpty {
            cell.textField?.stringValue = node.name
        } else {
            let text = NSMutableAttributedString(string: node.name, attributes: [.foregroundColor: NSColor.labelColor])
            text.append(NSAttributedString(string: "  " + node.detail, attributes: [.foregroundColor: NSColor.tertiaryLabelColor]))
            cell.textField?.attributedStringValue = text
        }
        cell.setAccessibilityLabel(node.detail.isEmpty ? node.name : "\(node.name), \(node.detail)")
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let image = NSImageView()
        image.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        image.contentTintColor = .secondaryLabelColor
        image.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextField(labelWithString: "")
        text.font = .systemFont(ofSize: 13)
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.addSubview(image)
        cell.addSubview(text)
        cell.imageView = image
        cell.textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?,
                     item: Any, mouseLocation: NSPoint) -> String {
        guard let node = item as? FileNode else { return "" }
        return node.detail.isEmpty ? node.url.lastPathComponent : "\(node.detail)/\(node.url.lastPathComponent)"
    }

    // MARK: Opening

    @objc private func rowClicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? FileNode else { return }
        // A click on the disclosure triangle only opens or closes the folder.
        if let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown {
            let point = outline.convert(event.locationInWindow, from: nil)
            if outline.frameOfOutlineCell(atRow: row).contains(point) { return }
        }
        activate(node)
    }

    private func openSelected() {
        guard let node = outline.item(atRow: outline.selectedRow) as? FileNode else { return }
        activate(node)
    }

    private func activate(_ node: FileNode) {
        if node.isFolder {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else {
            open(node.url)
        }
    }

    private func open(_ url: URL, newWindow: Bool = false) {
        if url.standardizedFileURL == documentURL?.standardizedFileURL {
            focusEditor?()
            return
        }
        if let open = NSDocumentController.shared.document(for: url) {
            Self.bringForward(open)
        } else if newWindow {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { document, _, error in
                if let error { NSApp.presentError(error); return }
                guard let document else { return }
                if document.windowControllers.isEmpty { document.makeWindowControllers() }
                guard let window = document.windowControllers.first?.window else { return }
                if window.isVisible { return Self.bringForward(document) }
                // Its own window whatever the tabs setting says.
                window.tabbingMode = .disallowed
                if let key = NSApp.keyWindow {
                    window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: key.frame.minX, y: key.frame.maxY)))
                }
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        // This window keeps its own note highlighted.
        revealCurrent(scroll: false)
    }

    private static func bringForward(_ document: NSDocument) {
        guard let window = document.windowControllers.first?.window else { return document.showWindows() }
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outline.clickedRow
        let node = row >= 0 ? outline.item(atRow: row) as? FileNode : nil
        func add(_ title: String, _ action: Selector, _ url: URL) {
            let item = NSMenuItem(title: L(title), action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = url
            menu.addItem(item)
        }
        if let node {
            if !node.isFolder { add("Open in New Window", #selector(openInNewWindow(_:)), node.url) }
            add("Show in Finder", #selector(showInFinder(_:)), node.url)
            if node.isFolder { add("New Note Here", #selector(newNoteHere(_:)), node.url) }
        } else if let root, state == .tree {
            add("New Note Here", #selector(newNoteHere(_:)), root)
            add("Show in Finder", #selector(showInFinder(_:)), root)
        }
    }

    @objc private func openInNewWindow(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url, newWindow: true)
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func showRootInFinder(_ sender: Any?) {
        guard let root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    /// An empty "Untitled.md" (or "Untitled 2.md"…) in the folder, opened.
    @objc private func newNoteHere(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        let url = folder.appendingPathComponent(FileTree.untitledName(in: folder, base: L("Untitled")))
        do {
            try Data().write(to: url, options: .withoutOverwriting)
        } catch {
            if let window = view.window { presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil) } else { NSApp.presentError(error) }
            return
        }
        open(url)
    }

    @objc private func allowAccess(_ sender: Any?) {
        guard let root else { return }
        FolderAccess.request(root, for: view.window) { [weak self] granted in
            if granted { self?.reload() }
        }
    }
}

/// Watches a folder tree with FSEvents and reports the folders that
/// changed, a few times a second at most. Stops when released.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void

    init?(_ folder: URL, latency: TimeInterval = 0.3, handler: @escaping ([String]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            watcher.handler(Array(list.prefix(count)))
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
