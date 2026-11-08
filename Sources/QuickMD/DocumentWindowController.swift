import AppKit
import UniformTypeIdentifiers
import WebKit

/// One window per document holding the one view: a live-styled text
/// view that reads like the page and edits like markdown, its marks
/// showing only on the caret's line. No sidebar, no toolbar.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let editor = EditorViewController()
    private var settingsObserver: Any?

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    init(document: MarkdownDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 420, height: 300)
        // MarkdownDocument.showWindows does the tabbing itself, so it
        // follows the setting and not System Settings' "Prefer tabs".
        window.tabbingMode = Settings.opensInTabs ? .preferred : .disallowed
        window.tabbingIdentifier = "QuickMDDocument"
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
        windowFrameAutosaveName = "QuickMDDocument"
        window.contentViewController = editor
        if window.frame.width < 600 { window.setContentSize(NSSize(width: 860, height: 720)) }
        if !window.setFrameUsingName("QuickMDDocument") { window.center() }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .editorSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.applyTheme() }

        document.editor = editor
        editor.textView.baseURL = document.fileURL?.deletingLastPathComponent()
        // A note an agent wrote a moment ago (opened right after it was
        // written) plays in from empty, as if it were still being typed.
        if Settings.liveWriting, let written = document.fileModificationDate, -written.timeIntervalSinceNow < 3 {
            editor.play(document.text)
        } else {
            editor.load(document.text)
        }
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
        window?.appearance = NSAppearance(named: theme.appearanceName)
        window?.backgroundColor = Palette.for(theme).background
    }

    // MARK: Export

    private var documentTitle: String {
        ((markdownDocument?.displayName ?? "Untitled") as NSString).deletingPathExtension
    }

    /// The note as a light, standalone page in the current style.
    private func renderedPage(assets: MarkdownHTML.Assets) -> String {
        MarkdownHTML.page(
            body: MarkdownHTML.render(editor.currentText),
            title: documentTitle, theme: .light, fontSize: Settings.fontSize, baseURL: nil, assets: assets
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
