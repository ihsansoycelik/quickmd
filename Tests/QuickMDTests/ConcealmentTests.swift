import AppKit
import Testing
@testable import QuickMD

/// Writing with hidden marks: nothing reappears on the caret line, the
/// caret steps over hidden marks, and typing helps with markers and pairs.
@MainActor
struct ConcealmentTests {
    nonisolated(unsafe) static var key = 0
    nonisolated(unsafe) static var windowKey = 0

    /// A reading-mode editor in a window, holding `text`, caret at `‸` (else the end).
    func editor(_ text: String) -> MarkdownTextView {
        let controller = EditorViewController()
        _ = controller.view
        controller.isReading = true
        let caret = (text as NSString).range(of: "‸")
        let plain = text.replacingOccurrences(of: "‸", with: "")
        controller.load(plain)
        let view = controller.textView
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.view
        window.layoutIfNeeded()
        view.frame.size.width = 600
        objc_setAssociatedObject(view, &Self.key, controller, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(view, &Self.windowKey, window, .OBJC_ASSOCIATION_RETAIN)
        let at = caret.location != NSNotFound ? caret.location : (plain as NSString).length
        view.setSelectedRange(NSRange(location: at, length: 0))
        return view
    }

    func type(_ view: MarkdownTextView, _ keys: [String]) {
        for key in keys {
            switch key {
            case "↩": view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            case "⌫": view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            case "←": view.doCommand(by: #selector(NSResponder.moveLeft(_:)))
            case "→": view.doCommand(by: #selector(NSResponder.moveRight(_:)))
            default: view.insertText(key, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
    }

    func caret(_ view: NSTextView) -> Int { view.selectedRange().location }

    func isNullGlyph(_ view: NSTextView, at index: Int) -> Bool {
        guard let layout = view.layoutManager else { return false }
        let glyph = layout.glyphIndexForCharacter(at: index)
        return layout.propertyForGlyph(at: glyph).contains(.null)
    }

    // MARK: Styling

    @Test func blockPrefixesAndCompleteSpansAreConcealed() {
        let view = editor("## Title\n\n> quote\n\na **bold** and `code` and [link](https://x.io) and **open")
        let s = view.textStorage!, ns = view.string as NSString
        #expect(s.attribute(.qmConceal, at: 0, effectiveRange: nil) != nil)
        #expect(s.attribute(.qmConceal, at: 2, effectiveRange: nil) != nil)
        #expect(s.attribute(.qmConceal, at: 3, effectiveRange: nil) == nil)
        #expect(s.attribute(.qmConceal, at: ns.range(of: "> ").location, effectiveRange: nil) != nil)
        let bold = ns.range(of: "**bold**")
        #expect(s.attribute(.qmConceal, at: bold.location, effectiveRange: nil) != nil)
        #expect(s.attribute(.qmConceal, at: NSMaxRange(bold) - 1, effectiveRange: nil) != nil)
        #expect(s.attribute(.qmConceal, at: ns.range(of: "`code`").location, effectiveRange: nil) != nil)
        #expect(s.attribute(.qmConceal, at: ns.range(of: "](https").location + 3, effectiveRange: nil) != nil)
        // Being typed: not a span yet, so it stays visible.
        #expect(s.attribute(.qmConceal, at: ns.range(of: "**open").location, effectiveRange: nil) == nil)
    }

    @Test func imageSourceIsNotConcealed() {
        let view = editor("![alt](pic.png)\n")
        #expect(view.textStorage!.attribute(.qmConceal, at: 0, effectiveRange: nil) == nil)
    }

    /// The caret on a heading or a bold word: its marks stay hidden.
    @Test func caretLineKeepsMarksHidden() {
        let view = editor("## Title\n\nSome **bold** text\n")
        view.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(isNullGlyph(view, at: 0))
        #expect(isNullGlyph(view, at: 2))
        #expect(!isNullGlyph(view, at: 3))
        let bold = (view.string as NSString).range(of: "**bold**")
        view.setSelectedRange(NSRange(location: bold.location + 4, length: 0))
        #expect(isNullGlyph(view, at: bold.location))
        #expect(isNullGlyph(view, at: NSMaxRange(bold) - 1))
    }

    /// A list line draws the same bullet glyph with or without the caret.
    @Test func bulletStaysABulletOnTheCaretLine() {
        let view = editor("- item\n\nother\n")
        let layout = view.layoutManager!
        view.setSelectedRange(NSRange(location: 10, length: 0))
        let away = layout.glyph(at: layout.glyphIndexForCharacter(at: 0))
        view.setSelectedRange(NSRange(location: 4, length: 0))
        let here = layout.glyph(at: layout.glyphIndexForCharacter(at: 0))
        #expect(away == here)
    }

    @Test func showMarkdownSyntaxShowsEverything() {
        let view = editor("## Title\n")
        let controller = objc_getAssociatedObject(view, &Self.key) as! EditorViewController
        controller.isReading = false
        #expect(!view.concealsMarkup)
        #expect(!isNullGlyph(view, at: 0))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(caret(view) == 0)
    }

    // MARK: Caret

    @Test func caretLeavesBlockPrefixes() {
        let view = editor("## Title")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(caret(view) == 3)
        view.setSelectedRange(NSRange(location: 1, length: 0))
        #expect(caret(view) == 3)
        let list = editor("- [ ] task")
        list.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(caret(list) == 6)
        let quote = editor("> quoted")
        quote.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(caret(quote) == 2)
    }

    @Test func leftFromContentStartGoesToTheLineBefore() {
        let view = editor("x\n## T‸")
        view.setSelectedRange(NSRange(location: 5, length: 0))
        type(view, ["←"])
        #expect(caret(view) == 1)
        type(view, ["→"])
        #expect(caret(view) == 5)
    }

    @Test func arrowsStepOverHiddenMarks() {
        // "a **bold** c": the opening `**` is 2..<4, the closing 8..<10.
        let view = editor("a ‸**bold** c")
        type(view, ["→"])
        #expect(caret(view) == 5)  // after "b", not stuck at the same spot
        type(view, ["←"])
        #expect(caret(view) == 4)
        type(view, ["←"])
        #expect(caret(view) == 1)  // before the space
        view.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(caret(view) == 10 || caret(view) == 8)
    }

    @Test func shiftArrowsSelectOverHiddenMarks() {
        let view = editor("a ‸**bold** c")
        view.moveRightAndModifySelection(nil)
        #expect(view.selectedRange() == NSRange(location: 2, length: 3))
        view.moveLeftAndModifySelection(nil)
        #expect(view.selectedRange().length == 0)
    }

    @Test func lineStartIsTheContentStart() {
        let view = editor("x\n## Head‸")
        view.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
        #expect(caret(view) == 5)
    }

    @Test func returnAtHeadingStartKeepsTheHeading() {
        let view = editor("## ‸Title")
        type(view, ["↩"])
        #expect(view.string == "\n## Title")
        #expect(caret(view) == 4)
    }

    // MARK: Backspace

    @Test func backspaceAtContentStartRemovesTheMarker() {
        for (text, result) in [("## ‸Title", "Title"), ("- ‸item", "item"), ("- [ ] ‸task", "task"), ("> ‸quote", "quote"), ("1. ‸one", "one")] {
            let view = editor(text)
            type(view, ["⌫"])
            #expect(view.string == result, "\(text)")
            #expect(caret(view) == 0)
        }
    }

    @Test func backspaceInEmptyContinuedItemRemovesTheMarker() {
        let view = editor("- a")
        type(view, ["↩"])
        #expect(view.string == "- a\n- ")
        type(view, ["⌫"])
        #expect(view.string == "- a\n")
    }

    // MARK: Markers typed into a fresh item

    @Test func blockMarkerReplacesFreshListMarker() {
        func typed(_ keys: [String]) -> String {
            let view = editor("- item")
            type(view, ["↩"] + keys)
            return view.string
        }
        #expect(typed(["-", " ", "[", " ", "]", " ", "t"]) == "- item\n- [ ] t")
        #expect(typed(["[", " ", "]", " ", "t"]) == "- item\n- [ ] t")
        #expect(typed([">", " ", "q"]) == "- item\n> q")
        #expect(typed(["#", "#", " ", "h"]) == "- item\n## h")
        #expect(typed(["1", ".", " ", "n"]) == "- item\n1. n")
        #expect(typed(["w", "o", "r", "d", " "]) == "- item\n- word ")
    }

    // MARK: Auto-pairs

    @Test func boldPairsAndStepsOver() {
        let view = editor("a ")
        type(view, ["*", "*"])
        #expect(view.string == "a ****")
        #expect(caret(view) == 4)
        type(view, ["b", "*", "*", " "])
        #expect(view.string == "a **b** ")
    }

    @Test func codeAndStrikePair() {
        let view = editor("")
        type(view, ["`", "x", "`", " ", "~", "~", "y", "~", "~"])
        #expect(view.string == "`x` ~~y~~")
        #expect(caret(view) == (view.string as NSString).length)
    }

    @Test func fenceStillTypes() {
        let view = editor("")
        type(view, ["`", "`", "`"])
        #expect(view.string == "```")
    }

    @Test func backspaceRemovesEmptyPair() {
        let view = editor("a ")
        type(view, ["*", "*", "⌫"])
        #expect(view.string == "a ")
    }

    @Test func noPairMidWordOrInCode() {
        let view = editor("word‸")
        type(view, ["*", "*"])
        #expect(view.string == "word**")
        let code = editor("```\n‸\n```")
        type(code, ["`"])
        #expect(code.string == "```\n`\n```")
    }

    // MARK: Insert and Format

    @Test func footnoteTakesTheNextNumber() {
        #expect(MarkdownTextView.nextFootnote(in: "a[^1] b[^3]\n\n[^1]: x") == 4)
        let view = editor("Text")
        view.insertFootnote(nil)
        #expect(view.string == "Text[^1]\n\n[^1]: ")
        #expect(caret(view) == (view.string as NSString).length)
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.insertFootnote(nil)
        #expect(view.string == "Text[^2][^1]\n\n[^1]: \n[^2]: ")
    }

    @Test func todaysDateIsISO() {
        let view = editor("")
        view.insertTodaysDate(nil)
        #expect(view.string.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
    }

    @Test func clearFormattingStripsMarks() {
        #expect(MarkdownTextView.plainLine("## **Bold** [link](https://x.io) `c`") == "Bold link c")
        #expect(MarkdownTextView.plainLine("- [ ] task ~~gone~~ ==hi==") == "task gone hi")
        #expect(MarkdownTextView.plainLine("> *quoted*") == "quoted")
        #expect(MarkdownTextView.plainLine("snake_case_name") == "snake_case_name")
    }

    // MARK: Focus and count

    @Test func focusBlockStopsAtBlankLines() {
        let ns = "one\n\ntwo\nlines\n\nthree" as NSString
        let block = EditorViewController.focusBlock(in: ns, at: 6)
        #expect(ns.substring(with: block) == "two\nlines\n")
    }

    @Test func countLineReadsWordsAndMinutes() {
        #expect(DocumentWindowController.wordCount("Hello there, world.") == 3)
        #expect(DocumentWindowController.countLine(words: 106) == "106 words · 1 min read")
        #expect(DocumentWindowController.countLine(words: 461) == "461 words · 3 min read")
        #expect(DocumentWindowController.countLine(words: 0) == "0 words · 0 min read")
    }
}
