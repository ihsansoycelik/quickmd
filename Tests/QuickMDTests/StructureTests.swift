import AppKit
import Testing
@testable import QuickMD

/// Outline, folding, heading levels, line moves, tasks, tables, contents.
@MainActor
struct StructureTests {
    func editor(_ text: String, reading: Bool = false) -> (MarkdownTextView, EditorViewController) {
        let controller = EditorViewController()
        controller.view.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        controller.isReading = reading
        let caret = (text as NSString).range(of: "‸")
        controller.load(text.replacingOccurrences(of: "‸", with: ""))
        let view = controller.textView
        if caret.location != NSNotFound { view.setSelectedRange(NSRange(location: caret.location, length: 0)) }
        return (view, controller)
    }

    func caret(_ text: String) -> (String, NSRange) {
        let r = (text as NSString).range(of: "‸")
        return (text.replacingOccurrences(of: "‸", with: ""), NSRange(location: r.location, length: 0))
    }

    func applied(_ edit: BlockEditing.Edit?, to text: String) -> String? {
        guard let edit else { return nil }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    // MARK: Moving and deleting lines

    @Test func moveLineSwapsWithNeighbour() {
        let (text, sel) = caret("a\nb‸\nc")
        let up = BlockEditing.moveLines(in: text, selection: sel, up: true)
        #expect(applied(up, to: text) == "b\na\nc")
        #expect(up?.selection.location == 1)
        let down = BlockEditing.moveLines(in: text, selection: sel, up: false)
        #expect(applied(down, to: text) == "a\nc\nb")
        #expect(down?.selection.location == 5)
        #expect(BlockEditing.moveLines(in: text, selection: NSRange(location: 0, length: 0), up: true) == nil)
    }

    @Test func moveListItemTakesItsChildren() {
        let (text, sel) = caret("- one\n- two‸\n    - child\n- three\n")
        let up = BlockEditing.moveLines(in: text, selection: sel, up: true)
        #expect(applied(up, to: text) == "- two\n    - child\n- one\n- three\n")
        let down = BlockEditing.moveLines(in: text, selection: sel, up: false)
        #expect(applied(down, to: text) == "- one\n- three\n- two\n    - child\n")
        // Up past a sibling with children: over the whole sibling.
        let (t2, s2) = caret("- one\n    - kid\n- two‸\n")
        #expect(applied(BlockEditing.moveLines(in: t2, selection: s2, up: true), to: t2) == "- two\n- one\n    - kid\n")
    }

    @Test func deleteLineRemovesWholeLines() {
        let (text, sel) = caret("a\nb‸b\nc")
        let edit = BlockEditing.deleteLines(in: text, selection: sel)
        #expect(applied(edit, to: text) == "a\nc")
        #expect(edit?.selection.location == 2)
        let (last, s2) = caret("a\nb‸")
        #expect(applied(BlockEditing.deleteLines(in: last, selection: s2), to: last) == "a")
    }

    @Test func moveLineIsOneUndoStep() {
        let (view, controller) = editor("a\nb‸\nc")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = controller.view
        let undo = view.undoManager!
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        view.moveLineUp(nil)
        undo.endUndoGrouping()
        #expect(view.string == "b\na\nc")
        undo.undo()
        #expect(view.string == "a\nb\nc")
    }

    // MARK: Headings

    @Test func promoteAndDemote() {
        #expect(BlockEditing.shiftHeading("### Title", by: -1) == "## Title")
        #expect(BlockEditing.shiftHeading("# Title", by: -1) == "# Title")
        #expect(BlockEditing.shiftHeading("###### Title", by: 1) == "###### Title")
        #expect(BlockEditing.shiftHeading("## Title", by: 1) == "### Title")
        #expect(BlockEditing.shiftHeading("Body", by: 1) == "Body")
        #expect(BlockEditing.shiftHeading("#hashtag", by: 1) == "#hashtag")
        let (view, _) = editor("## A‸\n", reading: true)
        view.promoteHeading(nil)
        #expect(view.string == "# A\n")
    }

    @Test func tableOfContentsNestsAndMatchesAnchors() {
        let text = "# Intro\n\n### Deep [one]\n\n## Setup\n\n## Setup\n"
        #expect(BlockEditing.tableOfContents(text) ==
            "- [Intro](#intro)\n    - [Deep \\[one\\]](#deep-one)\n    - [Setup](#setup)\n    - [Setup](#setup-1)\n")
        #expect(BlockEditing.tableOfContents("no headings") == nil)
    }

    @Test func headingLinkOnHeadingLineOnly() {
        let text = "# Hello World\n\ntext\n\nSetext\n---\n"
        #expect(BlockEditing.headingLink(in: text, at: 3) == "[Hello World](#hello-world)")
        #expect(BlockEditing.headingLink(in: text, at: 16) == nil)
        #expect(BlockEditing.headingLink(in: text, at: 22) == "[Setext](#setext)")
        #expect(BlockEditing.headingLink(in: text, at: 29) == "[Setext](#setext)")
    }

    @Test func frontMatterOnlyOnce() {
        let date = Date(timeIntervalSince1970: 0)
        let block = BlockEditing.frontMatter(title: "My: note", date: date)
        #expect(block.hasPrefix("---\ntitle: \"My: note\"\ndate: 19"))
        #expect(block.hasSuffix("\n---\n\n"))
        #expect(BlockEditing.hasFrontMatter(block + "# Hi"))
        #expect(!BlockEditing.hasFrontMatter("# Hi"))
        #expect(BlockEditing.yamlValue("Plain title") == "Plain title")
    }

    // MARK: Tasks

    @Test func checkAndUncheckSelected() {
        #expect(Checkbox.setting("- [ ] a", checked: true) == "- [x] a")
        #expect(Checkbox.setting("- [x] a", checked: true) == "- [x] a")
        #expect(Checkbox.setting("- [X] a", checked: false) == "- [ ] a")
        #expect(Checkbox.setting("plain", checked: true) == nil)
        let (view, _) = editor("- [ ] a\n- [x] b\ntext\n")
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        view.checkSelectedTasks(nil)
        #expect(view.string == "- [x] a\n- [x] b\ntext\n")
        view.uncheckSelectedTasks(nil)
        #expect(view.string == "- [ ] a\n- [ ] b\ntext\n")
    }

    // MARK: Tables

    let table = "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n"

    func run(_ command: TableCommand, at needle: String) -> String? {
        let offset = (table as NSString).range(of: needle).location
        return TableEditing.apply(command, to: table, caret: offset)?.text
    }

    @Test func tableRowsAndColumns() {
        #expect(run(.addRowBelow, at: "1") == "| A   | B   |\n| --- | --- |\n| 1   | 2   |\n|     |     |\n| 3   | 4   |\n")
        #expect(run(.addRowAbove, at: "A") == nil)
        #expect(run(.addRowBelow, at: "A") == "| A   | B   |\n| --- | --- |\n|     |     |\n| 1   | 2   |\n| 3   | 4   |\n")
        #expect(run(.deleteRow, at: "3") == "| A   | B   |\n| --- | --- |\n| 1   | 2   |\n")
        #expect(run(.deleteColumn, at: "2") == "| A   |\n| --- |\n| 1   |\n| 3   |\n")
        #expect(run(.addColumnBefore, at: "B") == "| A   |     | B   |\n| --- | --- | --- |\n| 1   |     | 2   |\n| 3   |     | 4   |\n")
        #expect(run(.moveRowDown, at: "1") == "| A   | B   |\n| --- | --- |\n| 3   | 4   |\n| 1   | 2   |\n")
        #expect(run(.moveRowUp, at: "1") == nil)
        #expect(run(.moveColumnRight, at: "A") == "| B   | A   |\n| --- | --- |\n| 2   | 1   |\n| 4   | 3   |\n")
    }

    @Test func tableAlignment() {
        #expect(run(.alignCenter, at: "2") == "| A   | B   |\n| --- | :-: |\n| 1   | 2   |\n| 3   | 4   |\n")
        #expect(run(.alignRight, at: "A") == "| A   | B   |\n| --: | --- |\n| 1   | 2   |\n| 3   | 4   |\n")
        #expect(run(.alignLeft, at: "A") == "| A   | B   |\n| :-- | --- |\n| 1   | 2   |\n| 3   | 4   |\n")
    }

    @Test func tableCommandFromTheEditor() {
        let (view, _) = editor("x\n\n| A | B |\n|---|---|\n| 1‸ | 2 |")
        let item = NSMenuItem()
        item.tag = TableCommand.tidy.rawValue
        #expect(view.validateMenuItem({ let m = NSMenuItem(title: "", action: #selector(MarkdownTextView.tableCommand(_:)), keyEquivalent: ""); return m }()))
        view.tableCommand(item)
        #expect(view.string == "x\n\n| A   | B   |\n| --- | --- |\n| 1   | 2   |")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(!view.validateMenuItem(NSMenuItem(title: "", action: #selector(MarkdownTextView.tableCommand(_:)), keyEquivalent: "")))
    }

    // MARK: Highlight

    @Test func highlightWrapsAndRenders() {
        let (view, _) = editor("word")
        view.setSelectedRange(NSRange(location: 0, length: 4))
        view.toggleHighlight(nil)
        #expect(view.string == "==word==")
        #expect(MarkdownHTML.render("==word==").contains("<mark>word</mark>"))
    }

    // MARK: Outline

    @Test func outlineFilter() {
        let headings = Headings.find(in: "# Café\n## Setup\n### Install")
        #expect(OutlinePanel.filter(headings, "cafe").map(\.title) == ["Café"])
        #expect(OutlinePanel.filter(headings, "").count == 3)
        #expect(OutlinePanel.filter(headings, "st").map(\.title) == ["Install"])
    }

    // MARK: Folding

    @Test func sectionBodyStopsAtSameOrHigherLevel() {
        let text = "# A\nintro\n## B\nb text\n### C\nc\n## D\nd\n"
        let ns = text as NSString
        let b = ns.range(of: "## B").location
        let body = Folding.sectionBody(in: text, heading: b)!
        #expect(ns.substring(with: body) == "b text\n### C\nc\n")
        #expect(ns.substring(with: Folding.sectionBody(in: text, heading: 0)!) == "intro\n## B\nb text\n### C\nc\n## D\nd\n")
        #expect(Folding.sectionBody(in: "# A\n\n# B\n", heading: 0) == nil)
    }

    @Test func foldsFollowEdits() {
        let fold = Folding.Fold(heading: 10, body: NSRange(location: 15, length: 10))
        let before = Folding.adjust([fold], replacing: NSRange(location: 2, length: 0), delta: 3)
        #expect(before.kept == [Folding.Fold(heading: 13, body: NSRange(location: 18, length: 10))])
        #expect(Folding.adjust([fold], replacing: NSRange(location: 30, length: 1), delta: -1).kept == [fold])
        #expect(Folding.adjust([fold], replacing: NSRange(location: 25, length: 0), delta: 1).kept == [fold])
        #expect(Folding.adjust([fold], replacing: NSRange(location: 17, length: 1), delta: 0).dropped == [fold])
    }

    @Test(arguments: [false, true]) func foldHidesWithoutChangingText(reading: Bool) {
        let note = "# A\nintro\n## B‸\nhidden **text**\n\n- [ ] task\n## C\nafter\n"
        let (view, controller) = editor(note, reading: reading)
        let text = view.string
        view.foldSection(nil)
        #expect(view.string == text)
        #expect(controller.currentText == text)
        let ns = text as NSString
        let hidden = ns.range(of: "hidden")
        let after = ns.range(of: "after")
        let lm = view.layoutManager!
        lm.ensureLayout(for: view.textContainer!)
        func rect(_ i: Int) -> NSRect { lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: i), effectiveRange: nil) }
        #expect(lm.propertyForGlyph(at: lm.glyphIndexForCharacter(at: hidden.location)) == .null)
        #expect(lm.propertyForGlyph(at: lm.glyphIndexForCharacter(at: after.location)) != .null)
        #expect(rect(after.location).height > 0)
        // The next heading sits right under the folded one: the body takes no room.
        let b = ns.range(of: "## B").location + 3, c = ns.range(of: "## C").location + 3
        #expect(rect(c).minY == rect(b).maxY)
        #expect(rect(ns.range(of: "task").location).height == 0)
        // The caret waits on the heading, outside the fold.
        #expect(view.selectedRange().location == ns.range(of: "## B").location + 4)
        #expect(controller.folding.hasFolds)
        // The caret going in opens it.
        view.setSelectedRange(NSRange(location: hidden.location + 2, length: 0))
        #expect(!controller.folding.hasFolds)
        lm.ensureLayout(for: view.textContainer!)
        #expect(rect(c).minY > rect(b).maxY + 20)
    }

    @Test func editingInsideAFoldOpensIt() {
        let (view, controller) = editor("# A‸\none\ntwo\n# B\n")
        view.foldSection(nil)
        #expect(controller.folding.hasFolds)
        // An edit before the heading keeps it folded and shifted.
        view.replace(NSRange(location: 0, length: 0), with: "x\n", keepSelection: true)
        #expect(controller.folding.folds.first?.heading == 2)
        // An edit in the body opens it.
        let one = (view.string as NSString).range(of: "one")
        view.replace(NSRange(location: one.location, length: 0), with: "Z", keepSelection: true)
        #expect(!controller.folding.hasFolds)
        #expect(view.string == "x\n# A\nZone\ntwo\n# B\n")
    }

    @Test func unfoldSectionAndAll() {
        let (view, controller) = editor("# A‸\none\n# B\ntwo\n")
        view.foldSection(nil)
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "# B").location + 2, length: 0))
        view.foldSection(nil)
        #expect(controller.folding.folds.count == 2)
        view.unfoldSection(nil)
        #expect(controller.folding.folds.count == 1)
        view.unfoldAll(nil)
        #expect(!controller.folding.hasFolds)
    }
}
