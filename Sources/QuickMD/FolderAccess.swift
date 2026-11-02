import AppKit

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
        panel.prompt = "Allow Access"
        panel.message = "Allow QuickMD to show the images and open the notes this note links to in “\(folder.lastPathComponent)”."
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
        } else {
            NSWorkspace.shared.open(file)
        }
    }
}
