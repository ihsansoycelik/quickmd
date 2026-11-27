import Foundation
import Testing
@testable import QuickMD

/// What the file sidebar lists, in which order, and how the filter finds notes.
struct FileTreeTests {
    /// A scratch folder with the given files ("a/b.md") and folders ("a/").
    func folder(_ paths: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("filetree-\(UUID())")
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for path in paths {
            let url = root.appendingPathComponent(path)
            if path.hasSuffix("/") {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("x".utf8).write(to: url)
            }
        }
        return root
    }

    func names(_ entries: [FileTree.Entry]) -> [String] { entries.map(\.name) }

    @Test func hiddenAndIgnoredFoldersAreSkipped() throws {
        let root = try folder([".hidden/a.md", ".git/b.md", "node_modules/c.md", "build/d.md", ".build/e.md", "notes/f.md", ".dot.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(names(FileTree.list(root)) == ["notes"])
        #expect(names(FileTree.scan(root)) == ["f"])
    }

    @Test func onlyNoteExtensionsShow() throws {
        let root = try folder(["a.md", "b.MARKDOWN", "c.mdown", "d.mkd", "e.txt", "f.png", "g.pdf", "h"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(Set(FileTree.list(root).map(\.url.lastPathComponent)) == ["a.md", "b.MARKDOWN", "c.mdown", "d.mkd", "e.txt"])
    }

    @Test func foldersFirstThenNaturalOrder() throws {
        let root = try folder(["note 10.md", "note 2.md", "Zeta/", "alpha/", "Beta.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = FileTree.list(root)
        #expect(names(entries) == ["alpha", "Zeta", "Beta", "note 2", "note 10"])
        #expect(entries.map(\.isFolder) == [true, true, false, false, false])
    }

    @Test func displayNameStripsMarkdownExtensionOnly() {
        #expect(FileTree.displayName(of: URL(fileURLWithPath: "/x/Plan.md"), isFolder: false) == "Plan")
        #expect(FileTree.displayName(of: URL(fileURLWithPath: "/x/Plan.Markdown"), isFolder: false) == "Plan")
        #expect(FileTree.displayName(of: URL(fileURLWithPath: "/x/todo.txt"), isFolder: false) == "todo.txt")
        #expect(FileTree.displayName(of: URL(fileURLWithPath: "/x/v1.md"), isFolder: true) == "v1.md")
    }

    @Test func searchIsCaseAndDiacriticInsensitive() throws {
        let root = try folder(["Café.md", "deep/er/CAFETERIA.txt", "other.md", "md.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(names(FileTree.search("cafe", in: root)) == ["Café", "CAFETERIA.txt"])
        #expect(names(FileTree.search("CAFÉ", in: root)) == ["Café", "CAFETERIA.txt"])
        #expect(names(FileTree.search("md", in: root)) == ["md"])  // the hidden extension is not matched
        #expect(FileTree.relativeFolder(of: root.appendingPathComponent("deep/er/CAFETERIA.txt"), root: root) == "deep/er")
        #expect(FileTree.relativeFolder(of: root.appendingPathComponent("other.md"), root: root) == "")
    }

    @Test func searchRespectsCaps() throws {
        let root = try folder(["1.md", "a/2.md", "a/b/3.md", "a/b/c/4.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(names(FileTree.search("", in: root, maxDepth: 1)) == ["1", "2"])
        #expect(FileTree.scan(root, maxFiles: 2).count == 2)
        #expect(FileTree.scan(root).count == 4)
    }

    @Test func untitledNamesCountUp() throws {
        let root = try folder([])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(FileTree.untitledName(in: root) == "Untitled.md")
        try Data().write(to: root.appendingPathComponent("Untitled.md"))
        #expect(FileTree.untitledName(in: root) == "Untitled 2.md")
        try Data().write(to: root.appendingPathComponent("Untitled 2.md"))
        #expect(FileTree.untitledName(in: root, base: "Başlıksız") == "Başlıksız.md")
        #expect(FileTree.untitledName(in: root) == "Untitled 3.md")
    }
}
