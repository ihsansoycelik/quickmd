import AppKit
import UniformTypeIdentifiers
import WebKit

/// The preview's URL scheme: `quickmd://local/<path>`. The app's own
/// fonts and scripts live under `/.quickmd-app/`; any other path is a
/// file on disk, served only when it's something a page displays
/// (images, audio, video) — so a note can show the pictures beside it
/// but can't read anything else.
final class PreviewScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "quickmd"
    static let grantAction = "quickmd://local/.quickmd-action/grant"
    private static let appPrefix = "/.quickmd-app/"
    private static let media: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "bmp", "tif", "tiff", "ico", "heic", "heif",
        "mp4", "m4v", "mov", "webm", "mp3", "m4a", "aac", "wav", "ogg", "oga", "flac",
    ]
    private var stopped: Set<ObjectIdentifier> = []

    /// The page's base: the note's folder, so relative paths resolve.
    static func baseURL(for folder: URL?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "local"
        let path = folder?.standardizedFileURL.path ?? ""
        components.path = path.hasSuffix("/") ? path : path + "/"
        return components.url ?? URL(string: "quickmd://local/")!
    }

    static func appURL(_ resource: String) -> String { "quickmd://local" + appPrefix + resource }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        let path = url.path
        var file: URL?
        if path.hasPrefix(Self.appPrefix) {
            let resource = String(path.dropFirst(Self.appPrefix.count))
            if !resource.split(separator: "/").contains("..") { file = AppResources.url(resource) }
        } else if Self.media.contains(url.pathExtension.lowercased()) {
            file = URL(fileURLWithPath: path)
        }
        let id = ObjectIdentifier(task)
        DispatchQueue.global(qos: .userInitiated).async {
            let data = file.flatMap { try? Data(contentsOf: $0) }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped.contains(id) else { self?.stopped.remove(id); return }
                guard let file, let data else {
                    task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!)
                    task.didFinish()
                    return
                }
                let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                let headers = ["Content-Type": mime, "Content-Length": "\(data.count)", "Access-Control-Allow-Origin": "*"]
                task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
                task.didReceive(data)
                task.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        stopped.insert(ObjectIdentifier(task))
    }
}

/// Headings of the note; click one to jump to it.
final class OutlineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private var headings: [Outline.Heading] = []
    private var isUpdatingSelection = false
    var onSelect: ((Int) -> Void)?

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let column = NSTableColumn(identifier: .init("heading"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        // One column as wide as the sidebar, so long headings use it.
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowSizeStyle = .default
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        scroll.documentView = tableView
        view = scroll
        view.setFrameSize(NSSize(width: 220, height: 400))
    }

    func update(text: String) {
        let next = Outline.headings(in: text)
        guard next != headings else { return }
        headings = next
        tableView.reloadData()
    }

    /// Highlights the section the caret is in.
    func highlight(location: Int) {
        guard let index = headings.lastIndex(where: { $0.location <= location }) else {
            tableView.deselectAll(nil)
            return
        }
        guard tableView.selectedRow != index else { return }
        isUpdatingSelection = true
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        isUpdatingSelection = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { headings.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let heading = headings[row]
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: heading.title)
        label.lineBreakMode = .byTruncatingTail
        label.font = heading.level <= 2
            ? .systemFont(ofSize: 13, weight: heading.level == 1 ? .semibold : .medium)
            : .systemFont(ofSize: 12)
        label.textColor = heading.level <= 2 ? .labelColor : .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: CGFloat(heading.level - 1) * 12 + 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection, tableView.selectedRow >= 0 else { return }
        onSelect?(headings[tableView.selectedRow].location)
    }
}
