import AppKit
import UniformTypeIdentifiers

/// Under the App Sandbox a note's own file is readable but its folder
/// isn't, so images beside it and the notes it links to need the
/// folder granted once, through an Open panel. Grants are kept as
/// security-scoped bookmarks and resumed at launch. Outside the
/// sandbox everything here is a no-op.
@MainActor
enum FolderAccess {
    private static let key = "FolderBookmarks"
    private static var granted: [URL] = []

    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// Starts access to the folders granted in earlier sessions.
    static func restore() {
        guard isSandboxed else { return }
        var kept: [Data] = []
        for data in UserDefaults.standard.array(forKey: key) as? [Data] ?? [] {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            granted.append(url)
            kept.append(stale ? (try? url.bookmarkData(options: .withSecurityScope)) ?? data : data)
        }
        UserDefaults.standard.set(kept, forKey: key)
    }

    static func canRead(_ folder: URL) -> Bool {
        guard isSandboxed else { return true }
        let path = folder.standardizedFileURL.path + "/"
        return granted.contains { path.hasPrefix($0.standardizedFileURL.path + "/") }
    }

    /// Asks for `folder` (or one above it) in an Open panel.
    static func request(_ folder: URL, for window: NSWindow?, then done: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = L("Allow Access")
        panel.message = String(format: L("Allow QuickMD to show the images and open the notes this note links to in “%@”."), folder.lastPathComponent)
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url,
                  let data = try? url.bookmarkData(options: .withSecurityScope) else { return done(false) }
            var all = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
            all.append(data)
            UserDefaults.standard.set(all, forKey: key)
            if url.startAccessingSecurityScopedResource() { granted.append(url) }
            done(canRead(folder))
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { finish(panel.runModal()) }
    }
}

/// Opening what a note links to: notes in QuickMD, other files in
/// their own app, asking for the folder first when the sandbox needs it.
@MainActor
enum NoteLinks {
    static let noteExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdwn", "txt"]

    static func open(_ file: URL, from window: NSWindow?) {
        let folder = file.deletingLastPathComponent()
        guard FolderAccess.canRead(folder) else {
            FolderAccess.request(folder, for: window) { granted in
                if granted { open(file, from: window) }
            }
            return
        }
        if noteExtensions.contains(file.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        } else if canRun(file) {
            // A note must never start a program: apps and scripts are shown in Finder instead.
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            NSWorkspace.shared.open(file)
        }
    }

    /// A ⌘-clicked link. Web and mail links open; a file link opens like
    /// a relative one; any other scheme (which may launch an app) asks first.
    static func open(link url: URL, from window: NSWindow?) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" || scheme == "mailto" {
            NSWorkspace.shared.open(url)
        } else if url.isFileURL {
            open(url.standardizedFileURL, from: window)
        } else {
            let alert = NSAlert()
            alert.messageText = L("Open this link in another app?")
            alert.informativeText = url.absoluteString.count > 200 ? String(url.absoluteString.prefix(200)) + "…" : url.absoluteString
            alert.addButton(withTitle: L("Open"))
            alert.addButton(withTitle: L("Cancel"))
            let run: (NSApplication.ModalResponse) -> Void = { if $0 == .alertFirstButtonReturn { NSWorkspace.shared.open(url) } }
            if let window { alert.beginSheetModal(for: window, completionHandler: run) } else { run(alert.runModal()) }
        }
    }

    private static let runnableExtensions: Set<String> = [
        "app", "command", "tool", "sh", "bash", "zsh", "csh", "ksh", "fish", "terminal", "pkg", "mpkg",
        "scpt", "scptd", "applescript", "workflow", "action", "prefpane", "jar", "osax", "kext", "plugin",
        "webloc", "inetloc", "fileloc", "py", "rb", "pl", "php", "js", "exe", "bat", "dylib", "dmg", "iso",
    ]

    /// Would opening `file` run something?
    static func canRun(_ file: URL) -> Bool {
        let ext = file.pathExtension.lowercased()
        if runnableExtensions.contains(ext) { return true }
        if let type = UTType(filenameExtension: ext),
           [UTType.application, .executable, .script, .bundle, .package].contains(where: type.conforms(to:)) { return true }
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder) {
            if isFolder.boolValue { return NSWorkspace.shared.isFilePackage(atPath: file.path) }
            return FileManager.default.isExecutableFile(atPath: file.path)
        }
        return false
    }
}
