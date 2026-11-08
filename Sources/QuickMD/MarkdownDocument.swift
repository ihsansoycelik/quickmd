import AppKit
import UniformTypeIdentifiers

/// One markdown file. The text lives in the editor while a window is
/// open; `text` is the copy used before the window exists and for
/// saving.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var text = ""
    /// How the file was stored (encoding, mark, line breaks), kept for
    /// writing it back the same way. The editor works in `\n` only.
    private var format = TextFile(text: "")
    weak var editor: EditorViewController?
    /// Set while reloading a change another app wrote, so it plays in live.
    private var reloadingLive = false

    override class var autosavesInPlace: Bool { true }

    override class var readableTypes: [String] {
        ["net.daringfireball.markdown", "public.plain-text", "public.text"]
    }

    override class var writableTypes: [String] { ["net.daringfireball.markdown", "public.plain-text"] }

    override class func isNativeType(_ type: String) -> Bool { writableTypes.contains(type) }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    /// With "Open documents in tabs" on, a new window joins the front
    /// document window as a tab, and an untouched blank document it
    /// replaces closes.
    override func showWindows() {
        guard Settings.opensInTabs,
              let window = windowControllers.first?.window,
              window.tabbedWindows == nil || window.tabbedWindows?.count == 1,
              !window.isVisible else {
            super.showWindows()
            return
        }
        let others = NSDocumentController.shared.documents.filter { $0 !== self }
        let host = (NSApp.mainWindow ?? NSApp.keyWindow).flatMap { main in
            others.contains { $0.windowControllers.contains { $0.window === main } } ? main : nil
        } ?? others.lazy.compactMap { $0.windowControllers.first?.window }.first { $0.isVisible }
        if let host {
            host.addTabbedWindow(window, ordered: .above)
        }
        super.showWindows()
        window.makeKeyAndOrderFront(nil)

        // Opening a file into a fresh app closes the empty Untitled tab.
        if fileURL != nil {
            for case let blank as MarkdownDocument in others
            where blank.fileURL == nil && !blank.isDocumentEdited && blank.currentText.isEmpty {
                blank.close()
            }
        }
    }

    private var currentText: String { editor?.currentText ?? text }

    override func data(ofType typeName: String) throws -> Data {
        if let editor { text = editor.currentText }
        return try format.encode(text)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        format = try TextFile.decode(data)
        text = format.text
        format.text = ""  // one copy of a big note is enough
        if reloadingLive { editor?.play(text) } else { editor?.load(text) }
    }

    /// A file changed on disk by another app (an agent writing a
    /// report, a sync) reloads quietly when there's nothing unsaved
    /// here to lose. With live writing on, the change types itself in
    /// and the window comes forward, without taking the keyboard.
    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDocumentEdited, let url = self.fileURL,
                  let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate,
                  let known = self.fileModificationDate, modified > known else { return }
            self.reloadingLive = Settings.liveWriting && self.editor != nil
            defer { self.reloadingLive = false }
            try? self.revert(toContentsOf: url, ofType: self.fileType ?? "net.daringfireball.markdown")
            if self.reloadingLive, let window = self.windowControllers.first?.window {
                window.tabGroup?.selectedWindow = window
                window.orderFrontRegardless()
            }
        }
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let view = editor?.textView else { throw CocoaError(.featureUnsupported) }
        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.jobTitle = displayName
        return operation
    }
}
