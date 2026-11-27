import Foundation
import Testing
@testable import QuickMD

/// The preview/export renderer: crashes, sanitising, task numbering,
/// block edge cases and the inputs that used to take seconds.
struct RendererTests {
    func html(_ markdown: String, interactive: Bool = false) -> String {
        MarkdownHTML.render(markdown, interactive: interactive)
    }

    // MARK: Placeholder characters

    @Test func privateUseSentinelDoesNotCrash() {
        #expect(html("a \u{E000}0\u{E001} b").contains("&#xe000;0&#xe001;"))
    }

    @Test func loneSentinelTerminates() {
        #expect(html("x \u{E000} y").contains("&#xe000;"))
        #expect(html("`\u{E000}0\u{E001}`").contains("<code>&#xe000;0&#xe001;</code>"))
        #expect(!html("a\u{E002}b").contains("<br>"))
    }

    // MARK: Math

    @Test func latexDelimitersBecomeMath() {
        #expect(html(#"inline \(a^2\) here"#).contains(#"<span class="math">a^2</span>"#))
        #expect(html("\\[\n\\frac{1}{2}\n\\]").contains(#"<div class="math math-display">\frac{1}{2}</div>"#))
        #expect(html("so $$a\nb$$ in text").contains(#"<span class="math math-display">a"#))
    }

    @Test func escapedBracketsStayText() {
        #expect(html(#"a \[draft\] b"#).contains("<p>a [draft] b</p>"))
        #expect(html("\\[draft] text\nmore").contains("<p>[draft] text\nmore</p>"))
    }

    // MARK: Sanitising

    @Test func fileAndEntityHiddenSchemesAreBlocked() {
        let out = html("[a](file:///etc/passwd) [b](jav&#x61;script:1) <a href=\"FILE:///x\">c</a>")
        #expect(!out.lowercased().contains("file:"))
        #expect(!out.contains("script:"))
    }

    @Test func srcsetCandidatesAreChecked() {
        let out = html("<img srcset=\"a.png 1x, file:///etc/passwd 2x\"> <img srcset='jav&#x61;script:1'> <img srcset=\"a.png&#44;file:///x 2x\">")
        #expect(!out.lowercased().contains("file:"))
        #expect(!out.contains("script:"))
        #expect(html("<img srcset=\"a.png 1x, b.png 2x\">").contains("b.png 2x"))
    }

    @Test func characterReferencesSurvive() {
        #expect(html("AT&amp;T &copy; &#233;").contains("AT&amp;T &copy; &#233;"))
        #expect(html("`&amp;`").contains("<code>&amp;amp;</code>"))
        #expect(html("&nope and & alone").contains("&amp;nope and &amp; alone"))
    }

    @Test func controlCharactersAreDropped() {
        #expect(html("nul:\u{0}:end\u{7}").contains("nul::end"))
    }

    @Test func scriptsAndHandlersAreRemoved() {
        let out = html("<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n\n<img/onerror=alert(1) src=y>\n\nok")
        #expect(!out.lowercased().contains("<script"))
        #expect(!out.contains("onerror"))
        #expect(out.contains("<img src=x >"))
        #expect(out.contains("<p>ok</p>"))
    }

    @Test func quotedAngleBracketCannotSmuggleAHandler() {
        let out = html("hi <img alt=\">\" onerror=alert(1)> there")
        #expect(!out.contains("<img alt=\">\" onerror"))
        #expect(!html("<div title='a\"' onclick=x>t</div>").contains("onclick"))
    }

    @Test func scriptURLsAreNeutralised() {
        #expect(html("[x](javascript:alert(1))").contains("href=\"#\""))
        #expect(html("<a href=\"jav&#x61;script:alert(1)\">x</a>").contains("href=\"#\""))
        #expect(html("<a href=' javascript:x'>x</a>").contains("href=\"#\""))
        #expect(html("![p](data:image/png;base64,AAAA)").contains("src=\"data:image/png"))
        #expect(html("<iframe src=\"file:///etc/hosts\"></iframe>") .contains("iframe") == false)
    }

    @Test func pageForbidsInlineScript() {
        let page = MarkdownHTML.page(body: "", title: "t", theme: .light, fontSize: 16, baseURL: nil)
        #expect(page.contains("Content-Security-Policy"))
        #expect(page.contains("script-src 'nonce-"))
        #expect(page.contains("connect-src 'none'"))
    }

    // MARK: Tasks carry their source line

    func taskLines(_ markdown: String) -> [Int] {
        let out = html(markdown, interactive: true)
        return out.matches(of: /data-task="(\d+)"/).map { Int($0.1)! }
    }

    @Test func tasksSkipCodeAndHTML() {
        #expect(taskLines("Code\n\n    - [ ] example\n\n- [ ] real task") == [4])
        #expect(taskLines("<div>\n- [ ] inside\n</div>\n\n- [ ] real") == [4])
        #expect(taskLines("> ```\n> - [ ] in code\n> ```\n- [ ] real") == [3])
    }

    @Test func tasksWithoutTrailingSpace() {
        #expect(taskLines("- [x]\n- [ ] real\n- [X]\tdone") == [0, 1, 2])
        #expect(html("- [x]").contains("checked"))
    }

    @Test func nestedAndQuotedTasksKeepTheirLine() {
        #expect(taskLines("---\ntitle: x\n---\n\n- a\n  - [ ] nested\n\n> - [x] quoted") == [5, 7])
    }

    // MARK: Blocks

    @Test func pipeTextOverDashesIsAHeadingNotATable() {
        let out = html("a | b\n---")
        #expect(!out.contains("<table>"))
        #expect(out.contains("<h2 id=\"a-b\">a | b</h2>"))
        #expect(!html("| a | b |\n| --- |").contains("<table>"))
        #expect(html("| a | b |\n| --- | --- |\n| 1 | 2 |").contains("<td>2</td>"))
    }

    @Test func fenceClosesOnlyOnAMatchingFence() {
        let out = html("````markdown\n```swift\nlet x = 1\n```\n````\n\nafter")
        #expect(out.components(separatedBy: "<pre>").count == 2)
        let text = out.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        #expect(text.contains("```swift\nlet x = 1\n```"))
        #expect(out.contains("class=\"language-markdown\""))
        #expect(out.contains("<p>after</p>"))
        #expect(html("```\n```swift\nx\n```").components(separatedBy: "<pre>").count == 2)
    }

    @Test func frontMatterIsNotRendered() {
        let out = html("---\ntitle: Post\ndate: 2026-01-01\n---\n\n# Post")
        #expect(!out.contains("<hr>"))
        #expect(!out.contains("title:"))
        #expect(out.contains("<div class=\"properties\">"))
        #expect(out.contains("<span class=\"prop-value\">Post</span>"))
        #expect(out.contains("<h1"))
        // A rule at the top without key: lines is still a rule.
        #expect(html("---\n\ntext").contains("<hr>"))
    }

    @Test func emojiShortcodesAndCodeBars() {
        #expect(html("Done :tada: and :nope: at 10:30:45").contains("Done 🎉 and :nope: at 10:30:45"))
        #expect(html("`:tada:`").contains("<code>:tada:</code>"))
        let code = html("```swift\nlet x = 1\n```")
        #expect(code.contains("<span class=\"codelang\">swift</span>"))
        #expect(code.contains("class=\"copy\""))
    }

    @Test func obsidianCallouts() {
        let titled = html("> [!tip] Read this first\n> Body.")
        #expect(titled.contains("</svg>Read this first</p>"))
        #expect(titled.contains("<p>Body.</p>"))
        let folded = html("> [!NOTE]-\n> Hidden.")
        #expect(folded.contains("<details class=\"callout callout-note\">"))
        #expect(!folded.contains(" open>"))
        #expect(html("> [!faq]+ Why?\n> Because.").contains("<details class=\"callout callout-warning\" open>"))
        #expect(html("> [!info]\n> x").contains("</svg>Info</p>"))
        #expect(html("> [!nonsense]\n> x").contains("<blockquote>"))
    }

    @Test func footnotes() {
        let out = html("A[^b] and B[^a].\n\n[^a]: First.\n[^b]: Second\n    continued.\n\n`[^a]` stays.")
        #expect(out.contains("A<sup class=\"fnref\"><a href=\"#fn-b\" id=\"fnref-b\">1</a></sup>"))
        #expect(out.contains("<a href=\"#fn-a\" id=\"fnref-a\">2</a>"))
        #expect(out.contains("<code>[^a]</code>"))
        #expect(out.contains("<li id=\"fn-b\">\n<p>Second\ncontinued. <a href=\"#fnref-b\""))
        #expect(!out.contains("[^b]:"))
        #expect(html("No note [^x] here.").contains("[^x]"))
        #expect(html("```\n[^a]: in code\n```\n[^a]").contains("<pre><code>[^a]:"))
    }

    @Test func autolinksAndWikiLinks() {
        #expect(html("<me@x.io>").contains("<a href=\"mailto:me@x.io\">me@x.io</a>"))
        #expect(html("write me@x.io now").contains("<a href=\"mailto:me@x.io\">"))
        #expect(html("see www.apple.com.").contains("<a href=\"https://www.apple.com\">www.apple.com</a>."))
        #expect(html("[[My Note]]").contains("<a class=\"wikilink\" href=\"My%20Note.md\">My Note</a>"))
        #expect(html("[[My Note#Part Two|there]]").contains("href=\"My%20Note.md#part-two\">there</a>"))
        #expect(html("![[pic.png]]").contains("<img src=\"pic.png\""))
        #expect(html("`[[x]]`").contains("<code>[[x]]</code>"))
    }

    @Test func richProperties() {
        let out = html("---\ntags:\n  - a\n  - b\ndone: true\nauthor:\n  name: Ada\nurl: https://x.io\n---\n")
        #expect(out.contains("<span class=\"chip\">a</span><span class=\"chip\">b</span>"))
        #expect(out.contains("<input type=\"checkbox\" disabled checked>"))
        #expect(out.contains("<span class=\"prop-sub\">name</span> Ada"))
        #expect(out.contains("<a href=\"https://x.io\">https://x.io</a>"))
    }

    @Test func diffLinesAreTinted() {
        let out = html("```diff\n@@ -1 +1 @@\n-old\n+new\n same\n```")
        #expect(out.contains("<span class=\"dl dl-hunk\">@@ -1 +1 @@</span><span class=\"dl dl-del\">-old</span><span class=\"dl dl-add\">+new</span>"))
    }

    @Test func frontMatterCloseIsNotASetextUnderline() {
        let ns = "---\ntitle: x\nupdated: 2026\n---\n\nText\n---\n" as NSString
        let close = ns.range(of: "---", options: [], range: NSRange(location: 4, length: ns.length - 4)).location
        #expect(HorizontalRuleLayoutManager.setextLevel(underline: ns.lineRange(for: NSRange(location: close, length: 0)), in: ns) == nil)
        let later = ns.range(of: "---", options: .backwards).location
        #expect(HorizontalRuleLayoutManager.setextLevel(underline: ns.lineRange(for: NSRange(location: later, length: 0)), in: ns) == 2)
    }

    @Test func headingIDsAreUnique() {
        let ids = html("# a\n# a-1\n# a").matches(of: /id="([^"]+)"/).map { String($0.1) }
        #expect(ids == ["a", "a-1", "a-2"])
    }

    @Test func atxClosingHashesNeedASpace() {
        #expect(html("# C#").contains(">C#</h1>"))
        #expect(html("## Title ##").contains(">Title</h2>"))
    }

    // MARK: Inline

    @Test func boldItalicNestsCorrectly() {
        #expect(html("***x***").contains("<em><strong>x</strong></em>"))
    }

    @Test func linkDestinationsKeepBalancedParentheses() {
        let out = html("[wiki](https://en.wikipedia.org/wiki/Foo_(bar)) next")
        #expect(out.contains("href=\"https://en.wikipedia.org/wiki/Foo_(bar)\""))
        #expect(out.contains("</a> next"))
        #expect(html("[a](b \"T\")").contains("title=\"T\""))
        #expect(html("![alt](i.png)").contains("<img src=\"i.png\" alt=\"alt\">"))
    }

    @Test func hardBreaks() {
        #expect(html("one  \ntwo").contains("one<br>\ntwo"))
        #expect(html("one\\\ntwo").contains("one<br>\ntwo"))
        #expect(!html("one\ntwo").contains("<br>"))
    }

    @Test func codeSpans() {
        #expect(html("a `b` c").contains("<code>b</code>"))
        #expect(html("``a ` b``").contains("<code>a ` b</code>"))
        #expect(html("`unclosed").contains("`unclosed"))
    }

    // MARK: Speed

    func time(_ body: () -> Void) -> Double {
        let start = Date()
        body()
        return Date().timeIntervalSince(start)
    }

    @Test func pathologicalLinesStayFast() {
        #expect(time { _ = html(String(repeating: "`", count: 20_000)) } < 1)
        #expect(time { _ = html(String(repeating: "[", count: 20_000)) } < 1)
        #expect(time { _ = html(String(repeating: "[a](", count: 5_000)) } < 3)  // loose: debug build, suites run in parallel
    }

    @Test func largeNoteRendersQuickly() {
        let block = "# Heading\n\nSome *text* with `code` and a [link](https://x.io).\n\n- item\n- [ ] task\n\n> quote\n\n"
        let note = String(repeating: block, count: 1_000)  // ~11,000 lines
        #expect(time { _ = html(note) } < 3)
    }

    // MARK: Review fixes

    @Test func commentCannotHideTags() {
        #expect(!html("<!--><img src=x onerror=alert(1)>-->").contains("<img"))
        #expect(!html("<!-- --!><link rel=stylesheet href=https://x/a.css> -->").contains("<link"))
    }

    @Test func imageAltCannotBreakOut() {
        let out = html("![<https://h/onerror=alert(1)//>](a.png)")
        #expect(!out.contains("onerror"))
        #expect(html("![$x$](a.png)").contains(#"<img src="a.png" alt="">"#))
    }

    @Test func paddedEntityDoesNotHideJavascript() {
        #expect(!html(#"<a href="&#x0000006a;avascript:alert(1)">x</a>"#).contains("avascript:alert"))
    }

    @Test func wikiLinkCannotBeJavascript() {
        #expect(!html("[[javascript:alert(1)//]]").contains("href=\"javascript"))
    }

    @Test func plaintextTagIsDropped() {
        #expect(!html("<plaintext>\nrest").contains("<plaintext"))
    }

    @Test func numberedLineDoesNotInterruptParagraph() {
        let out = html("We moved there in\n2019. It rained.")
        #expect(!out.contains("<ol"))
        #expect(html("Intro\n1. one\n2. two").contains("<ol>"))
    }
}
