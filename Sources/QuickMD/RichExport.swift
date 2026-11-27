import AppKit
import UniformTypeIdentifiers

/// File › Export as Word and Export as Rich Text: the rendered note as
/// an attributed string, written as .docx or .rtf. Built with images
/// and media taken out (see RichText.offlineHTML), so nothing is fetched.
extension DocumentWindowController {
    @objc func exportWord(_ sender: Any?) {
        exportRich(type: UTType(filenameExtension: "docx") ?? .data, fileExtension: "docx",
                   documentType: .officeOpenXML)
    }

    @objc func exportRichText(_ sender: Any?) {
        exportRich(type: .rtf, fileExtension: "rtf", documentType: .rtf)
    }

    private func exportRich(type: UTType, fileExtension: String, documentType: NSAttributedString.DocumentType) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = documentTitle + "." + fileExtension
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try Self.richData(self.editor.currentText, title: self.documentTitle, documentType: documentType).write(to: url, options: .atomic)
            } catch {
                self.presentError(error)
            }
        }
    }

    static func richData(_ markdown: String, title: String, documentType: NSAttributedString.DocumentType) throws -> Data {
        guard let text = RichText.attributed(markdown, title: title, properties: true) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: documentType]
        if !title.isEmpty { attributes[.title] = title }
        return try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attributes)
    }
}
