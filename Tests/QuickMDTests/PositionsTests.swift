import Foundation
import Testing
@testable import QuickMD

/// Reopening a note where it was left.
@MainActor @Suite(.serialized) struct PositionsTests {
    @Test func remembersAndCaps() {
        let suite = "QuickMDPositionsTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let saved = Positions.defaults
        Positions.defaults = defaults
        defer { Positions.defaults = saved; defaults.removePersistentDomain(forName: suite) }

        let note = URL(fileURLWithPath: "/tmp/a/../a/note.md")
        Positions.save(.init(caret: 42, top: 7), for: note)
        #expect(Positions.position(for: URL(fileURLWithPath: "/tmp/a/note.md")) == .init(caret: 42, top: 7))
        #expect(Positions.position(for: URL(fileURLWithPath: "/tmp/other.md")) == nil)

        for i in 0..<310 { Positions.save(.init(caret: i, top: 0), for: URL(fileURLWithPath: "/tmp/n\(i).md")) }
        #expect((defaults.dictionary(forKey: "NotePositions")?.count ?? 0) == 300)
    }

    @Test func windowSavesAndRestoresThePlace() {
        let suite = "QuickMDPositionWindowTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let saved = Positions.defaults
        Positions.defaults = defaults
        defer { Positions.defaults = saved; defaults.removePersistentDomain(forName: suite) }

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("positions-\(UUID()).md")
        let text = (0..<2000).map { "Line \($0) lorem ipsum" }.joined(separator: "\n")
        func open() -> DocumentWindowController {
            let doc = MarkdownDocument()
            doc.text = text
            doc.fileURL = url
            let controller = DocumentWindowController(document: doc)
            doc.addWindowController(controller)
            controller.window?.orderFront(nil)
            return controller
        }
        func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

        let first = open()
        spin(0.2)
        let caret = (text as NSString).range(of: "Line 1500").location
        first.editorForTests.textView.setSelectedRange(NSRange(location: caret, length: 0))
        first.editorForTests.textView.scrollRangeToVisible(NSRange(location: caret, length: 0))
        spin(1.4)
        let stored = Positions.position(for: url)
        #expect(stored?.caret == caret)
        #expect((stored?.top ?? 0) > 0)
        first.window?.orderOut(nil)

        let second = open()
        spin(0.3)
        #expect(second.editorForTests.textView.selectedRange().location == caret)
        #expect(abs(second.editorForTests.position.top - (stored?.top ?? 0)) < 200)
        second.window?.orderOut(nil)
    }
}
