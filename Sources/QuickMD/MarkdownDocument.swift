import AppKit
import UniformTypeIdentifiers

/// One markdown file. The text lives in the editor while a window is
/// open; `text` is the copy used before the window exists and for
/// saving.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var text = ""
    /// The encoding the file was read in, kept for writing it back.
    private var encoding: String.Encoding = .utf8
    /// The file's line breaks. The editor works in `\n` only; CRLF (and
    /// old Mac CR) files are written back the way they came.
    private var lineEnding = "\n"
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
        let output = lineEnding == "\n" ? text : text.replacingOccurrences(of: "\n", with: lineEnding)
        guard let data = output.data(using: encoding) ?? output.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    override func read(from data: Data, ofType typeName: String) throws {
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
            encoding = .utf8
        } else {
            var converted: NSString?
            var lossy = ObjCBool(false)
            let raw = NSString.stringEncoding(
                for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: &lossy
            )
            guard raw != 0, let converted else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            text = converted as String
            encoding = String.Encoding(rawValue: raw)
        }
        // A BOM is an encoding detail, not part of the note.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // By bytes: "\r\n" is one Character, so String's own search misses a lone "\r" in it.
        if text.utf8.contains(0x0D) {
            lineEnding = (text as NSString).range(of: "\r\n").location != NSNotFound ? "\r\n" : "\r"
            text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        } else {
            lineEnding = "\n"
        }
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
