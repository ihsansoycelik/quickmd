import AppKit
import Testing
@testable import QuickMD

/// Editing commands on a live text view, line endings, and the outline.
@MainActor
struct EditorTests {
    /// An editor holding `text`, styled, with the caret at `‸` if given.
    func editor(_ text: String) -> MarkdownTextView {
        let controller = EditorViewController()
        _ = controller.view
        controller.isReading = false
        let caret = (text as NSString).range(of: "‸")
        controller.load(text.replacingOccurrences(of: "‸", with: ""))
        let view = controller.textView
        objc_setAssociatedObject(view, &EditorTests.key, controller, .OBJC_ASSOCIATION_RETAIN)
        if caret.location != NSNotFound { view.setSelectedRange(NSRange(location: caret.location, length: 0)) }
        return view
    }
    nonisolated(unsafe) static var key = 0

    // MARK: Preview checkbox → line

    @Test func toggleTaskByLine() {
        let view = editor("Code\n\n    - [ ] example\n\n- [ ] real task\n> - [x] quoted")
        view.toggleTask(line: 4)
        #expect(view.string == "Code\n\n    - [ ] example\n\n- [x] real task\n> - [x] quoted")
        view.toggleTask(line: 5)
        #expect(view.string.hasSuffix("> - [ ] quoted"))
        view.toggleTask(line: 0)  // not a task: nothing
        #expect(view.string.hasPrefix("Code\n"))
    }

    @Test func previewAndEditorAgreeOnTaskLines() {
        let note = "- [x]\n- [ ] a\n\n```\n- [ ] code\n```\n1. [ ] numbered\n"
        let lines = MarkdownHTML.render(note, interactive: true).matches(of: /data-task="(\d+)"/).map { Int($0.1)! }
        let view = editor(note)
        for line in lines { view.toggleTask(line: line) }
        #expect(view.string == "- [ ]\n- [x] a\n\n```\n- [ ] code\n```\n1. [x] numbered\n")
    }

    // MARK: Return

    @Test func returnMidMarkerSplitsTheItem() {
        let view = editor("- ‸foo")
        view.insertNewline(nil)
        #expect(view.string == "- \n- foo")
    }

    @Test func returnOnEmptyItemEndsTheList() {
        let view = editor("- a\n- ‸")
        view.insertNewline(nil)
        #expect(view.string == "- a\n")
    }

    @Test func returnInCodeKeepsIndentOnly() {
        let view = editor("```yaml\n  - item‸\n```")
        view.insertNewline(nil)
        #expect(view.string == "```yaml\n  - item\n  \n```")
    }

    // MARK: Tables

    @Test func tabSkipsTheDelimiterRow() {
        let view = editor("| a‸ | b|\n| --- | --- |\n| c | d |\n")
        view.insertTab(nil)  // a → b
        view.insertTab(nil)  // b → c, not the --- row
        let selected = (view.string as NSString).substring(with: view.selectedRange())
        #expect(selected == "c")
        view.insertBacktab(nil)  // c → b
        #expect((view.string as NSString).substring(with: view.selectedRange()) == "b")
    }

    @Test func tabInCodeDoesNotReformatPipes() {
        let view = editor("```\n|a|b|\n```")
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.insertTab(nil)
        #expect(view.string == "```\n|\ta|b|\n```")
    }

    // MARK: Format commands

    @Test func listCommandsWorkOnAnEmptyLine() {
        let view = editor("")
        view.toggleBulletList(nil)
        #expect(view.string == "- ")
        let numbered = editor("a\n‸\nb")
        numbered.toggleNumberedList(nil)
        #expect(numbered.string == "a\n1. \nb")
    }

    @Test func quoteKeepsTheListMarker() {
        let view = editor("- [x] ‸task")
        view.toggleQuote(nil)
        #expect(view.string == "> - [x] task")
    }

    @Test func taskToggleOnBareBox() {
        let view = editor("- [ ]‸")
        view.toggleTaskList(nil)
        #expect(view.string == "")
    }

    @Test func headingCommandTouchesOneLine() {
        let view = editor("intro\nhe‸llo\noutro")
        let item = NSMenuItem()
        item.tag = 1
        view.setHeading(item)
        #expect(view.string == "intro\n# hello\noutro")
    }

    @Test func typingOverASelectionWraps() {
        let view = editor("make bold")
        view.setSelectedRange(NSRange(location: 5, length: 4))
        view.insertText("*", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("*", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "make **bold**")
    }

    // MARK: Line endings

    @Test func crlfFilesEditInLFAndSaveAsCRLF() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("| a | b |\r\n| - | - |\r\nintro\r\n".utf8), ofType: "net.daringfireball.markdown")
        #expect(document.text == "| a | b |\n| - | - |\nintro\n")
        let saved = try document.data(ofType: "net.daringfireball.markdown")
        #expect(String(data: saved, encoding: .utf8) == "| a | b |\r\n| - | - |\r\nintro\r\n")
    }

    // MARK: Headings

    @Test func headingsMatchTheRenderer() {
        let note = "---\ntitle: x\n---\nTitle\n=====\n\n  ## Indented\n\n```\n~~~\n# not a heading\n```\n\nSub\n---\n"
        let titles = Headings.find(in: note).map(\.title)
        #expect(titles == ["Title", "Indented", "Sub"])
    }

    // MARK: Styling speed

    @Test func longQuoteStylesInLinearTime() {
        let quote = String(repeating: "> quoted line of text here\n", count: 2_000)
        let start = Date()
        _ = editor(quote)
        #expect(Date().timeIntervalSince(start) < 1.5)
    }

    // MARK: Slash menu

    @Test func slashMenuFiltersByTitleThenKeyword() {
        #expect(SlashCommand.matching("").count == SlashCommand.all.count)
        #expect(SlashCommand.matching("h1").map(\.title) == ["Heading 1"])
        #expect(SlashCommand.matching("head").map(\.title) == ["Heading 1", "Heading 2", "Heading 3"])
        #expect(SlashCommand.matching("todo").map(\.title) == ["Task List"])
        #expect(SlashCommand.matching("list").first?.title == "Bulleted List")
        #expect(SlashCommand.matching("tip").map(\.title) == ["Callout: Tip"])
        #expect(SlashCommand.matching("zzz").isEmpty)
    }

    /// Types `keys` into an editor that sits in a window, as the keyboard would.
    func typeInWindow(_ text: String, _ keys: [String]) -> MarkdownTextView {
        let view = editor(text)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view.enclosingScrollView
        window.orderFront(nil)
        objc_setAssociatedObject(view, &EditorTests.windowKey, window, .OBJC_ASSOCIATION_RETAIN)
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        for key in keys {
            switch key {
            case "↩": view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            case "↓": view.doCommand(by: #selector(NSResponder.moveDown(_:)))
            case "⎋": view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            default: view.insertText(key, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
        window.orderOut(nil)
        return view
    }
    nonisolated(unsafe) static var windowKey = 0

    @Test func slashCommandReplacesWhatWasTyped() {
        #expect(typeInWindow("Intro\n", ["/", "h", "2", "↩"]).string == "Intro\n## ")
        #expect(typeInWindow("", ["/", "t", "o", "d", "o", "↩"]).string == "- [ ] ")
        #expect(typeInWindow("", ["/", "h", "e", "a", "d", "↓", "↩"]).string == "## ")
        #expect(typeInWindow("", ["/", "t", "a", "b", "l", "e", "↩"]).string.hasPrefix("| Column | Column |"))
    }

    @Test func slashMenuStaysOutOfTheWay() {
        // Mid-word, in code, after Esc, or once the query has a space: plain typing.
        #expect(typeInWindow("and", ["/", "o", "r", "↩"]).string == "and/or\n")
        #expect(typeInWindow("```\n", ["/", "h", "1", "↩"]).string == "```\n/h1\n")
        #expect(typeInWindow("", ["/", "h", "1", "⎋", "↩"]).string == "/h1\n")
        #expect(typeInWindow("", ["/", "h", " ", "↩"]).string == "/h \n")
    }

    // MARK: Live writing

    /// An agent's change types in over the old text and ends exactly on the new one.
    @Test func liveChangePlaysIn() {
        let controller = EditorViewController()
        _ = controller.view
        controller.isReading = false
        controller.load("# Plan\n\nOld line.\n\nEnd 👋\n")
        let target = "# Plan\n\nNew ==key== line, with more words 🎯.\n\nEnd 👋\n"
        controller.play(target)
        #expect(controller.currentText == target)
        #expect(!controller.textView.isEditable)
        let deadline = Date().addingTimeInterval(5)
        while !controller.textView.isEditable, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        #expect(controller.textView.string == target)
        #expect(controller.textView.isEditable)
    }

    /// A second change mid-play finishes the first at once, then plays.
    @Test func liveChangeInterrupted() {
        let controller = EditorViewController()
        _ = controller.view
        controller.isReading = false
        controller.play(String(repeating: "word ", count: 400))
        controller.play("short")
        controller.load("done")
        #expect(controller.textView.string == "done")
        #expect(controller.textView.isEditable)
    }

    @Test func markIsHighlighted() {
        let view = editor("Read ==this== first")
        let color = view.textStorage?.attribute(.backgroundColor, at: 8, effectiveRange: nil)
        #expect(color != nil)
        #expect(view.textStorage?.attribute(.backgroundColor, at: 2, effectiveRange: nil) == nil)
    }

    /// A table's cell separators stay dimmed but visible in reading mode
    /// (like a list bullet, not like a `**`), so an unpadded table written
    /// by an agent still shows its columns. Only the delimiter row hides —
    /// its line collapses to a hairline anyway.
    @Test func tablePipesStayVisibleInReadingMode() {
        let controller = EditorViewController()
        _ = controller.view
        controller.load("| x | y |\n|---|---|\n| 1 | 2 |\n")
        let storage = controller.textView.textStorage!
        // Pipes in the header and the data row: "| x | y |" and "| 1 | 2 |".
        for at in [0, 4, 20, 24] {
            #expect(storage.attribute(.qmKeepSyntax, at: at, effectiveRange: nil) != nil, "pipe at \(at) should stay visible")
            #expect(storage.attribute(.qmSyntax, at: at, effectiveRange: nil) == nil, "pipe at \(at) should not hide")
        }
        // The delimiter row's pipes stay hideable.
        #expect(storage.attribute(.qmSyntax, at: 10, effectiveRange: nil) != nil)
        #expect(storage.attribute(.qmSyntax, at: 14, effectiveRange: nil) != nil)
    }
}

@MainActor
struct TableGridTests {
    @Test func headingMarkerKeepsEmojiWhole() {
        let controller = EditorViewController()
        _ = controller.view
        controller.load("intro\n\n## 🛒 List\n")
        let storage = controller.textView.textStorage!
        let at = (storage.string as NSString).range(of: "🛒").location
        #expect(storage.attribute(.qmSyntax, at: at, effectiveRange: nil) == nil)
    }

    @Test func cellRangesTrimAndSkipEscapedPipes() {
        let ns = "| a | b \\| c | `x|y` |" as NSString
        let cells = TableGrid.cellRanges(NSRange(location: 0, length: ns.length), in: ns).map { ns.substring(with: $0) }
        #expect(cells == ["a", "b \\| c", "`x|y`"])
    }

    @Test func tableIsAGridUntilTheCaretEntersIt() {
        let controller = EditorViewController()
        _ = controller.view
        controller.load("text\n\n| a | b |\n|---|---|\n| 1 | 2 |\n")
        let view = controller.textView
        let lm = view.layoutManager as! HorizontalRuleLayoutManager
        let table = (view.string as NSString).range(of: "| a")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(lm.renderedTable(at: table.location) != nil)
        view.setSelectedRange(NSRange(location: table.location + 2, length: 0))
        #expect(lm.renderedTable(at: table.location) == nil)
    }
}

@MainActor
struct ReadingLookTests {
    func storage(_ text: String) -> NSTextStorage {
        let controller = EditorViewController()
        _ = controller.view
        controller.load(text)
        objc_setAssociatedObject(controller.textView, &EditorTests.key, controller, .OBJC_ASSOCIATION_RETAIN)
        return controller.textView.textStorage!
    }

    @Test func imageOnlyLineIsTagged() {
        let s = storage("a\n\n![alt](pics/x.png)\n\ntext ![i](y.png) inline\n")
        let ns = s.string as NSString
        #expect(s.attribute(.qmImage, at: ns.range(of: "![alt]").location, effectiveRange: nil) as? String == "pics/x.png")
        #expect(s.attribute(.qmImage, at: ns.range(of: "![i]").location, effectiveRange: nil) == nil)
    }

    @Test func taskBulletFoldsAndFrontMatterKeysStay() {
        let s = storage("---\ntitle: X\n---\n\n- [ ] todo\n- plain\n")
        let ns = s.string as NSString
        #expect(s.attribute(.qmTaskBullet, at: ns.range(of: "- [ ]").location, effectiveRange: nil) != nil)
        #expect(s.attribute(.qmTaskBullet, at: ns.range(of: "- plain").location, effectiveRange: nil) == nil)
        #expect(s.attribute(.qmSyntax, at: ns.range(of: "title").location, effectiveRange: nil) == nil)
    }

    @Test func footnoteReferenceHidesItsBrackets() {
        let s = storage("Text.[^1]\n\n[^1]: Note.\n")
        let ns = s.string as NSString
        let ref = ns.range(of: "[^1]")
        #expect(s.attribute(.qmSyntax, at: ref.location, effectiveRange: nil) != nil)
        #expect(s.attribute(.qmSyntax, at: ref.location + 2, effectiveRange: nil) == nil)
        let def = ns.range(of: "[^1]:")
        #expect(s.attribute(.qmSyntax, at: def.location, effectiveRange: nil) == nil)
    }
}
