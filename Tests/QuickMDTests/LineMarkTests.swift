import Foundation
import Testing
@testable import QuickMD

/// `data-line` marks: what the live preview scrolls by.
struct LineMarkTests {
    func marked(_ markdown: String) -> String { MarkdownHTML.render(markdown, interactive: true, lineMarks: true) }

    func lines(_ html: String) -> [Int] {
        html.matches(of: /data-line="(\d+)"/).map { Int($0.1)! }
    }

    @Test func topLevelBlocksCarryTheirFirstLine() {
        let source = """
        # Title

        First paragraph
        still first.

        - a
        - b

        ```swift
        let x = 1
        ```

        | a | b |
        | - | - |
        | 1 | 2 |

        > quote
        > - [ ] nested task

        ---
        """
        let html = marked(source)
        #expect(lines(html) == [0, 2, 5, 8, 12, 16, 19])
        #expect(html.contains("<h1 data-line=\"0\""))
        #expect(html.contains("<p data-line=\"2\">"))
        #expect(html.contains("<hr data-line=\"19\">"))
    }

    @Test func frontMatterKeepsRealLineNumbers() {
        #expect(lines(marked("---\ntitle: x\n---\n\nHello")) == [0, 4])
    }

    @Test func withoutMarksOutputIsUnchanged() {
        let source = "# A\n\ntext\n\n- item"
        #expect(!MarkdownHTML.render(source).contains("data-line"))
        #expect(marked(source).replacingOccurrences(of: #" data-line="\d+""#, with: "", options: .regularExpression)
            == MarkdownHTML.render(source, interactive: true))
    }

    @Test func notesCannotForgeLineMarks() {
        // Raw HTML is sanitised; a note's own data-line can't steer the preview.
        let html = marked("<div data-line=\"99\">x</div>")
        #expect(lines(html).allSatisfy { $0 == 0 })
    }

    @Test func lineMarksStayCheap() {
        let block = "## Section\n\nSome *text* with `code` and a [link](x.md).\n\n- one\n- two\n\n"
        let source = String(repeating: block, count: 1000)  // ~75 KB
        let clock = ContinuousClock()
        let plain = clock.measure { _ = MarkdownHTML.render(source) }
        let marked = clock.measure { _ = self.marked(source) }
        #expect(marked < plain * 2 + .milliseconds(200))
    }
}
