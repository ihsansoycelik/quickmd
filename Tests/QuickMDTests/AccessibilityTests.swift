import AppKit
import Testing
@testable import QuickMD

@MainActor
struct AccessibilityTests {
    func controller(_ text: String) -> EditorViewController {
        let controller = EditorViewController()
        _ = controller.view
        controller.load(text)
        return controller
    }

    @Test func drawnBlocksAreListed() {
        let c = controller("- [ ] milk\n- [x] eggs\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n![A cat](cat.png)\n")
        let storage = c.textView.textStorage!
        let items = DrawnBlocks.items(in: storage, range: NSRange(location: 0, length: storage.length))
        let kinds = items.map(\.kind)
        #expect(kinds.contains(.checkbox(checked: false, label: "milk")))
        #expect(kinds.contains(.checkbox(checked: true, label: "eggs")))
        #expect(kinds.contains(.table(rows: 2, columns: 2, summary: "a, b. 1, 2")))
        #expect(kinds.contains(.image(label: "A cat")))
    }

    @Test func imageLabelFallsBackToFileName() {
        #expect(DrawnBlocks.imageLabel("![](pics/My%20Shot.png)", target: "pics/My%20Shot.png") == "My Shot.png")
        #expect(DrawnBlocks.imageLabel("![ Logo ](x.png)", target: "x.png") == "Logo")
    }

    @Test func pressingTheBoxTicksTheTask() {
        let c = controller("- [ ] milk\n")
        let view = c.textView
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = c.view
        c.view.layoutSubtreeIfNeeded()
        view.setSelectedRange(NSRange(location: view.string.count, length: 0))
        let box = view.drawnBlockElements().compactMap { $0 as? TaskBoxElement }.first
        #expect(box?.accessibilityLabel() == "milk")
        #expect(box?.accessibilityPerformPress() == true)
        #expect(view.string == "- [x] milk\n")
    }
}
