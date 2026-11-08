import AppKit
import UniformTypeIdentifiers
import WebKit

/// One window per document: the outline sidebar beside the one view —
/// a live-styled text view that reads like the page and edits like
/// markdown, its tokens showing only on the caret's line.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation,
    NSToolbarDelegate, NSSharingServicePickerToolbarItemDelegate {
    private let split = NSSplitViewController()
    private let editor = EditorViewController()
    private let outline = OutlineViewController()
    private var outlineItem: NSSplitViewItem!
    private var editorItem: NSSplitViewItem!
    private var settingsObserver: Any?
    /// Glass chrome: blur behind the window, a tint over it, content on top.
    private let glass = NSVisualEffectView()
    private let tint = NSView()

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    init(document: MarkdownDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.minSize = NSSize(width: 420, height: 300)
        // MarkdownDocument.showWindows does the tabbing itself, so it
        // follows the setting and not System Settings' "Prefer tabs".
        window.tabbingMode = Settings.opensInTabs ? .preferred : .disallowed
        window.tabbingIdentifier = "QuickMDDocument"
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
        windowFrameAutosaveName = "QuickMDDocument"

        outlineItem = NSSplitViewItem(sidebarWithViewController: outline)
        outlineItem.minimumThickness = 160
        outlineItem.maximumThickness = 360
        outlineItem.isCollapsed = !Settings.showsOutline
        outlineItem.canCollapse = true
        editorItem = NSSplitViewItem(viewController: editor)
        editorItem.minimumThickness = 280
        editorItem.canCollapse = true
        split.addSplitViewItem(outlineItem)
        split.addSplitViewItem(editorItem)

        let container = NSViewController()
        let root = NSView()
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.material = .fullScreenUI
        tint.wantsLayer = true
        for layer in [glass, tint, split.view] as [NSView] {
            layer.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(layer)
            NSLayoutConstraint.activate([
                layer.topAnchor.constraint(equalTo: root.topAnchor),
                layer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                layer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                layer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ])
        }
        container.view = root
        container.addChild(split)
        window.contentViewController = container
        installToolbar(in: window)
        if window.frame.width < 600 { window.setContentSize(NSSize(width: 900, height: 700)) }
        if !window.setFrameUsingName("QuickMDDocument") { window.center() }

        editor.onTextChange = { [weak self] text in self?.outline.update(text: text) }
        editor.onCaretMove = { [weak self] location in self?.outline.highlight(location: location) }
        outline.onSelect = { [weak self] location in self?.editor.reveal(location: location) }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .editorSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.applyTheme() }

        document.editor = editor
        _ = editor.view
        editor.textView.baseURL = document.fileURL?.deletingLastPathComponent()
        // A note an agent wrote a moment ago (opened right after it was
        // written) plays in from empty, as if it were still being typed.
        if Settings.liveWriting, let written = document.fileModificationDate, -written.timeIntervalSinceNow < 3 {
            editor.play(document.text)
        } else {
            editor.load(document.text)
        }
        outline.update(text: document.text)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    override var document: AnyObject? {
        didSet {
            editor.textView.baseURL = markdownDocument?.fileURL?.deletingLastPathComponent()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window, window.firstResponder === window || window.firstResponder == nil else { return }
        window.makeFirstResponder(editor.textView)
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        // A renamed or newly saved file moves the base for relative links.
        // Title text only, no proxy icon.
        window?.standardWindowButton(.documentIconButton)?.isHidden = true
        editor.textView.baseURL = markdownDocument?.fileURL?.deletingLastPathComponent()
    }

    private func applyTheme() {
        let theme = Settings.theme
        let chrome = Chrome.for(theme, transparency: Settings.transparency, template: Settings.template)
        window?.appearance = NSAppearance(named: chrome.appearance)
        window?.isOpaque = !chrome.usesVisualEffect
        window?.backgroundColor = chrome.usesVisualEffect ? .clear : chrome.tintColor
        glass.isHidden = !chrome.usesVisualEffect
        glass.material = chrome.material
        tint.layer?.backgroundColor = chrome.tintColor.cgColor
    }

    // MARK: Sidebar

    @objc func toggleOutline(_ sender: Any?) {
        outlineItem.animator().isCollapsed.toggle()
        Settings.showsOutline = !outlineItem.isCollapsed
    }

    // MARK: Toolbar

    private enum ToolbarID {
        static let toolbar = NSToolbar.Identifier("QuickMDToolbar3")
        static let outline = NSToolbarItem.Identifier("outline")
        static let separator = NSToolbarItem.Identifier("outlineSeparator")
        static let format = NSToolbarItem.Identifier("format")
        static let share = NSToolbarItem.Identifier("share")
    }

    /// A unified toolbar, as in Notes or Pages: the outline toggle sits
    /// over the sidebar, the title follows the sidebar's edge, and the
    /// few actions a writer reaches for live on the right.
    private func installToolbar(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: ToolbarID.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.outline, ToolbarID.separator, .flexibleSpace, ToolbarID.format, ToolbarID.share]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func button(_ label: String, _ symbol: String, _ action: Selector, tip: String) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = label
            item.paletteLabel = label
            item.toolTip = tip
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.isBordered = true
            item.target = self
            item.action = action
            return item
        }
        switch id {
        case ToolbarID.outline:
            return button("Outline", "sidebar.left", #selector(toggleOutline(_:)), tip: "Show or hide the outline (⌃⌘S)")
        case ToolbarID.separator:
            return NSTrackingSeparatorToolbarItem(identifier: id, splitView: split.splitView, dividerIndex: 0)
        case ToolbarID.format:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Format"
            item.paletteLabel = "Format"
            item.toolTip = "Headings, lists and blocks"
            item.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Format")
            item.showsIndicator = true
            item.menu = Self.formatMenu()
            return item
        case ToolbarID.share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: id)
            item.label = "Share"
            item.paletteLabel = "Share"
            item.toolTip = "Share this note"
            item.delegate = self
            return item
        default:
            return nil
        }
    }

    /// The Format menu's everyday half, sent down the responder chain
    /// to the text view like the menu bar's items.
    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        func add(_ title: String, _ symbol: String?, _ action: Selector, tag: Int = 0) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.tag = tag
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(item)
        }
        add("Heading 1", nil, #selector(MarkdownTextView.setHeading(_:)), tag: 1)
        add("Heading 2", nil, #selector(MarkdownTextView.setHeading(_:)), tag: 2)
        add("Heading 3", nil, #selector(MarkdownTextView.setHeading(_:)), tag: 3)
        add("Body Text", nil, #selector(MarkdownTextView.setHeading(_:)), tag: 0)
        menu.addItem(.separator())
        add("Bold", "bold", #selector(MarkdownTextView.toggleBold(_:)))
        add("Italic", "italic", #selector(MarkdownTextView.toggleItalic(_:)))
        add("Strikethrough", "strikethrough", #selector(MarkdownTextView.toggleStrikethrough(_:)))
        add("Inline Code", "chevron.left.forwardslash.chevron.right", #selector(MarkdownTextView.toggleInlineCode(_:)))
        add("Link", "link", #selector(MarkdownTextView.insertLink(_:)))
        menu.addItem(.separator())
        add("Bulleted List", "list.bullet", #selector(MarkdownTextView.toggleBulletList(_:)))
        add("Numbered List", "list.number", #selector(MarkdownTextView.toggleNumberedList(_:)))
        add("Task List", "checklist", #selector(MarkdownTextView.toggleTaskList(_:)))
        add("Quote", "text.quote", #selector(MarkdownTextView.toggleQuote(_:)))
        menu.addItem(.separator())
        add("Code Block", "curlybraces", #selector(MarkdownTextView.insertCodeBlock(_:)))
        add("Table", "tablecells", #selector(MarkdownTextView.insertTable(_:)))
        add("Horizontal Rule", "minus", #selector(MarkdownTextView.insertHorizontalRule(_:)))
        return menu
    }

    /// The saved file when there is one, else the note's text.
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        if let url = markdownDocument?.fileURL, markdownDocument?.isDocumentEdited == false { return [url] }
        return [editor.currentText]
    }

    // MARK: Export

    private var documentTitle: String {
        ((markdownDocument?.displayName ?? "Untitled") as NSString).deletingPathExtension
    }

    /// The note as a light, standalone page in the current style.
    private func renderedPage(assets: MarkdownHTML.Assets) -> String {
        MarkdownHTML.page(
            body: MarkdownHTML.render(editor.currentText),
            title: documentTitle, theme: .light, template: Settings.template,
            fontFamily: Settings.fontFace.cssFamily, headingFamily: Settings.headingFace?.cssFamily,
            fontSize: Settings.fontSize, baseURL: nil, assets: assets
        )
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = documentTitle + ".html"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.renderedPage(assets: .embedded).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.presentError(error)
            }
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = documentTitle + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.printRendered(to: url)
        }
    }

    /// File › Print: the rendered note, as the preview shows it, not the markdown source.
    @objc func printRenderedDocument(_ sender: Any?) { printRendered(to: nil) }

    private var printer: RenderedPrinter?

    private func printRendered(to url: URL?) {
        guard let window else { return }
        let info = (markdownDocument?.printInfo ?? NSPrintInfo.shared).copy() as! NSPrintInfo
        printer = RenderedPrinter(
            html: renderedPage(assets: .preview), baseURL: markdownDocument?.fileURL?.deletingLastPathComponent(),
            printInfo: info, saveTo: url, window: window
        ) { [weak self] in self?.printer = nil }
    }

    @objc func copyAsHTML(_ sender: Any?) {
        let range = editor.textView.selectedRange()
        let source = range.length > 0 ? (editor.currentText as NSString).substring(with: range) : editor.currentText
        let html = MarkdownHTML.render(source)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(html, forType: .string)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleOutline(_:)):
            menuItem.title = outlineItem.isCollapsed ? "Show Sidebar" : "Hide Sidebar"
        case #selector(printRenderedDocument(_:)), #selector(exportPDF(_:)):
            return printer == nil
        default:
            break
        }
        return true
    }
}

/// Prints, or saves as PDF, a rendered page: loads it in a web view off
/// screen, waits for math and diagrams to typeset, then runs the print
/// operation. Lives until the operation ends.
final class RenderedPrinter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let printInfo: NSPrintInfo
    private let saveTo: URL?
    private weak var window: NSWindow?
    private let done: () -> Void

    init(html: String, baseURL: URL?, printInfo: NSPrintInfo, saveTo: URL?, window: NSWindow, done: @escaping () -> Void) {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(PreviewScheme(), forURLScheme: PreviewScheme.scheme)
        // Letter-ish width so the page lays out at print measure.
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 760, height: 1000), configuration: config)
        self.printInfo = printInfo
        self.saveTo = saveTo
        self.window = window
        self.done = done
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: PreviewScheme.baseURL(for: baseURL))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == PreviewScheme.scheme ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Mermaid lays out after fonts load; give the page a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.run() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }

    private func run() {
        guard let window else { return finish() }
        printInfo.topMargin = 54
        printInfo.bottomMargin = 54
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54
        printInfo.isHorizontallyCentered = false
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        if let saveTo {
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = saveTo
        }
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = saveTo == nil
        operation.showsProgressPanel = true
        // A web view's print view needs a real frame, or pages come out blank.
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: self, didRun: #selector(printDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finish()
    }

    private func finish() { done() }
}
