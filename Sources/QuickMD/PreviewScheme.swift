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
            let candidate = URL(fileURLWithPath: path).standardizedFileURL
            // Only from folders the user has let the app read.
            if FolderAccess.canRead(candidate.deletingLastPathComponent()) { file = candidate }
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
