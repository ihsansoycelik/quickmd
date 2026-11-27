import Foundation

/// What the file sidebar lists, kept free of UI so it can be tested:
/// which files and folders show, their order and names, the filter
/// search, and the name of a new note.
enum FileTree {
    /// Files the sidebar shows (case-insensitive).
    static let noteExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]
    /// Folders never shown or searched, besides those starting with ".".
    static let ignoredFolders: Set<String> = ["node_modules", ".git", "build", ".build"]
    /// Extensions left off the shown name.
    static let hiddenExtensions: Set<String> = ["md", "markdown"]

    struct Entry: Hashable {
        let url: URL
        let isFolder: Bool
        var name: String { FileTree.displayName(of: url, isFolder: isFolder) }
    }

    static func isNote(_ url: URL) -> Bool {
        noteExtensions.contains(url.pathExtension.lowercased())
    }

    static func isIgnoredFolder(_ name: String) -> Bool {
        name.hasPrefix(".") || ignoredFolders.contains(name)
    }

    /// "Plan.md" reads "Plan"; "todo.txt" keeps its extension.
    static func displayName(of url: URL, isFolder: Bool) -> String {
        let name = url.lastPathComponent
        guard !isFolder, hiddenExtensions.contains(url.pathExtension.lowercased()) else { return name }
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? name : stem
    }

    /// One folder's shown contents: folders first, then notes, each in Finder's order.
    static func list(_ folder: URL, fileManager: FileManager = .default) -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: []) else {
            return []
        }
        var folders: [Entry] = []
        var files: [Entry] = []
        for url in urls {
            let name = url.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isHidden == true { continue }
            if values?.isDirectory == true && values?.isPackage != true {
                if !isIgnoredFolder(name) { folders.append(Entry(url: url, isFolder: true)) }
            } else if isNote(url) {
                files.append(Entry(url: url, isFolder: false))
            }
        }
        return sorted(folders) + sorted(files)
    }

    static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
    }

    /// Every note under `root`, at most `maxDepth` folders down and
    /// `maxFiles` notes in all, so a huge folder can't stall the filter.
    static func scan(_ root: URL, maxDepth: Int = 6, maxFiles: Int = 2000, fileManager: FileManager = .default) -> [Entry] {
        var found: [Entry] = []
        func walk(_ folder: URL, depth: Int) {
            for entry in list(folder, fileManager: fileManager) {
                guard found.count < maxFiles else { return }
                if entry.isFolder {
                    if depth < maxDepth { walk(entry.url, depth: depth + 1) }
                } else {
                    found.append(entry)
                }
            }
        }
        walk(root, depth: 0)
        return found
    }

    /// Case- and diacritic-insensitive: "cafe" finds "Café.md".
    static func matches(_ entry: Entry, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return entry.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func filter(_ entries: [Entry], query: String) -> [Entry] {
        sorted(entries.filter { matches($0, query: query) })
    }

    static func search(_ query: String, in root: URL, maxDepth: Int = 6, maxFiles: Int = 2000) -> [Entry] {
        filter(scan(root, maxDepth: maxDepth, maxFiles: maxFiles), query: query)
    }

    /// The folder a note sits in, relative to `root` ("" for the root itself).
    static func relativeFolder(of url: URL, root: URL) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL.pathComponents
        let base = root.standardizedFileURL.pathComponents
        guard folder.count >= base.count, Array(folder.prefix(base.count)) == base else {
            return url.deletingLastPathComponent().path
        }
        return folder.dropFirst(base.count).joined(separator: "/")
    }

    /// "Untitled.md", then "Untitled 2.md", "Untitled 3.md"… whichever is free.
    static func untitledName(in folder: URL, base: String = "Untitled", fileManager: FileManager = .default) -> String {
        var number = 1
        while true {
            let name = number == 1 ? "\(base).md" : "\(base) \(number).md"
            if !fileManager.fileExists(atPath: folder.appendingPathComponent(name).path) { return name }
            number += 1
        }
    }
}
