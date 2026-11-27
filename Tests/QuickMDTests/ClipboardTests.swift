import AppKit
import Testing
@testable import QuickMD

/// Copy As, Paste as Markdown / Table, rich export and Check Links.
struct ClipboardTests {
    // MARK: HTML → Markdown

    @Test func headingsEmphasisCodeLinks() {
        let md = HTMLToMarkdown.convert("""
        <h1>Title</h1><p>Some <b>bold</b>, <em>italic</em>, <code>x*y</code> and <a href="https://a.com/p">a link</a>.</p>
        <h3>Sub</h3><p><del>gone</del></p>
        """)
        #expect(md == "# Title\n\nSome **bold**, *italic*, `x*y` and [a link](https://a.com/p).\n\n### Sub\n\n~~gone~~")
    }

    @Test func nestedListsAndTasks() {
        let md = HTMLToMarkdown.convert("""
        <ul><li>One<ul><li>Nested</li></ul></li><li>Two</li></ul>
        <ol start="3"><li>Three</li><li><input type="checkbox" checked> Done</li></ol>
        """)
        #expect(md == "- One\n  - Nested\n- Two\n\n3. Three\n4. [x] Done")
    }

    @Test func quoteRuleImageAndCode() {
        let md = HTMLToMarkdown.convert("""
        <blockquote><p>Quoted</p></blockquote><hr><p><img src="pic.png" alt="A pic"></p>
        <pre><code class="language-swift">let a = 1
        </code></pre>
        """)
        #expect(md == "> Quoted\n\n---\n\n![A pic](pic.png)\n\n```swift\nlet a = 1\n```")
    }

    @Test func tablesEscapePipes() {
        let md = HTMLToMarkdown.convert("<table><tr><th>A</th><th>B</th></tr><tr><td>1|2</td><td>3</td></tr></table>")
        #expect(md == "| A    | B   |\n| ---- | --- |\n| 1\\|2 | 3   |")
    }

    @Test func scriptsStylesAndUnknownTagsDropped() {
        let md = HTMLToMarkdown.convert("""
        <style>p{color:red}</style><script>alert(1)</script><p>Keep <blink>this</blink><iframe src="https://x"></iframe></p>
        <p><a href="javascript:alert(1)">bad</a> <img src="data:image/png;base64,AAAA" alt="inline"></p>
        """)
        #expect(md == "Keep this\n\nbad inline")
    }

    @Test func googleDocsSpans() {
        let md = HTMLToMarkdown.convert(#"<p><span style="font-weight:700">Bold</span> and <span style="font-style: italic">it</span></p>"#)
        #expect(md == "**Bold** and *it*")
    }

    @Test func textThatLooksLikeMarkdownIsEscaped() {
        #expect(HTMLToMarkdown.convert("<p>2*3 and [x]</p>") == "2\\*3 and \\[x\\]")
    }

    // MARK: Tables

    @Test func tabSeparatedSpreadsheetCells() {
        let rows = MarkdownTable.tabSeparatedRows("Name\tAge\nAda\t36\nAlan\t41\n")
        #expect(rows == [["Name", "Age"], ["Ada", "36"], ["Alan", "41"]])
        #expect(MarkdownTable.make(rows!) == "| Name | Age |\n| ---- | --- |\n| Ada  | 36  |\n| Alan | 41  |")
    }

    @Test func tabsThatAreNotATable() {
        #expect(MarkdownTable.tabSeparatedRows("one\ttwo") == nil)  // one line
        #expect(MarkdownTable.tabSeparatedRows("a\tb\nc\td\te") == nil)  // uneven
        #expect(MarkdownTable.tabSeparatedRows("\tfoo()\n\tbar()") == nil)  // indented code
        #expect(MarkdownTable.tabSeparatedRows("plain\ntext") == nil)
    }

    @Test func csvWithQuotes() {
        let rows = MarkdownTable.delimitedRows("a,b\n\"x, y\",\"say \"\"hi\"\"\"\n")
        #expect(rows == [["a", "b"], ["x, y", "say \"hi\""]])
        #expect(MarkdownTable.delimitedRows("a;b;c\n1;2;3") == [["a", "b", "c"], ["1", "2", "3"]])
        #expect(MarkdownTable.delimitedRows("just words") == nil)
    }

    @Test func pipesAndRaggedRows() {
        #expect(MarkdownTable.make([["a|b", "c"], ["1"]]) == "| a\\|b | c   |\n| ---- | --- |\n| 1    |     |")
        #expect(MarkdownTable.escapePipes("x\\|y|z") == "x\\|y\\|z")
    }

    // MARK: Plain text

    @Test func plainTextStripsMarks() {
        let md = """
        # Title ##

        Some **bold**, *it*, `code **kept**` and [a link](https://a.com) ![pic](p.png).

        - item
          - [ ] open
        - [x] done
        1. first

        > quoted

        ---

        | a | b |
        |---|---|
        | 1 | 2 |

        ```
        # not a heading
        ```
        """
        #expect(PlainText.from(md) == """
        Title

        Some bold, it, code **kept** and a link pic.

        • item
          ☐ open
        ☑ done
        1. first

        quoted

        ———

        a\tb
        1\t2

        # not a heading
        """)
    }

    // MARK: Rich text

    @Test func offlineHTMLLoadsNothing() {
        let html = RichText.offlineHTML(MarkdownHTML.render("![Remote](https://x.com/a.png) <video src=\"https://x/v.mp4\"></video>\n\n- [ ] a\n- [x] b"))
        #expect(!html.contains("https://"))
        #expect(!html.contains("<img"))
        #expect(html.contains("Remote"))
        #expect(html.contains("☐") && html.contains("☑"))
    }

    @MainActor @Test func richTextAndWordExport() throws {
        let text = try #require(RichText.attributed("# Hi\n\nSome **bold** text ![x](https://example.com/a.png)"))
        #expect(text.string.contains("Hi"))
        #expect(text.string.contains("bold"))
        let docx = try DocumentWindowController.richData("# Hi\n\nBody", title: "Note", documentType: .officeOpenXML)
        #expect(docx.starts(with: [0x50, 0x4B]))  // a zip
        let rtf = try DocumentWindowController.richData("# Hi", title: "Note", documentType: .rtf)
        #expect(String(decoding: rtf, as: UTF8.self).hasPrefix("{\\rtf"))
    }

    // MARK: Check Links

    @Test func localLinksChecked() {
        let folder = URL(fileURLWithPath: "/notes")
        let text = """
        # Intro

        See [intro](#intro), [gone](#missing), [doc](other.md#part), [lost](lost.md) and ![pic](img/a.png).
        Web: [site](https://example.com) <https://x.org> https://bare.net and `[code](nope.md)`.
        Note[^1] and[^2].

        [ref]: missing-ref.md
        [^1]: Defined.

        ```
        [fenced](nope.md)
        ```
        """
        let existing: Set<String> = ["/notes/other.md"]
        let report = LinkCheck.check(text, folder: folder) { existing.contains($0.path) }
        #expect(report.problems.map(\.kind) == [
            .missingAnchor("#missing"), .missingFile("lost.md"), .missingImage("img/a.png"),
            .missingFootnote("2"), .missingFile("missing-ref.md"),
        ])
        #expect(report.problems.map(\.line) == [3, 3, 3, 5, 7])
        #expect(report.webLinks == 3)
        let ns = text as NSString
        #expect(ns.substring(with: report.problems[1].range) == "[lost](lost.md)")
    }

    @Test func unsavedNoteLeavesFilesUnchecked() {
        let report = LinkCheck.check("[a](a.md) [b](#b)\n\n# B", folder: nil) { _ in false }
        #expect(report.problems.isEmpty)
        #expect(report.uncheckedFiles == 1)
    }
}
