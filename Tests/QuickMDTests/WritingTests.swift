import AppKit
import Testing
@testable import QuickMD

/// Writing font, line width, page colour, book paragraphs, sentence
/// focus, smart punctuation in code, counts and goals, Writing Aids.
@MainActor
struct WritingTests {
    func styled(_ text: String, look: TypographyLook) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler.restyle(storage, size: 16, theme: .light, look: look)
        return storage
    }

    func font(_ storage: NSTextStorage, at needle: String) -> NSFont {
        let at = (storage.string as NSString).range(of: needle).location
        return storage.attribute(.font, at: at, effectiveRange: nil) as! NSFont
    }

    func paragraph(_ storage: NSTextStorage, at needle: String) -> NSParagraphStyle {
        let at = (storage.string as NSString).range(of: needle).location
        return storage.attribute(.paragraphStyle, at: at, effectiveRange: nil) as! NSParagraphStyle
    }

    // MARK: Look

    @Test func everyPageKeepsTextReadable() {
        for page in LightPage.allCases {
            let p = Palette.for(.light, light: page)
            #expect(Typography.contrast(p.text, p.background) >= 4.5)
            #expect(Typography.contrast(p.link, p.background) >= 4.5)
        }
        for page in DarkPage.allCases {
            let p = Palette.for(.dark, dark: page)
            #expect(Typography.contrast(p.text, p.background) >= 4.5)
        }
        #expect(cssHex(Palette.for(.light, light: .paper).background) == "#F8F7F4")
        #expect(cssHex(Palette.for(.light, light: .white).background) == "#FFFFFF")
        #expect(cssHex(Palette.for(.dark, dark: .black).background) == "#0B0B0A")
    }

    @Test func familiesPickTheirFaces() {
        #expect(WritingFont.mono.body(size: 16).isFixedPitch)
        #expect(!WritingFont.sans.body(size: 16).isFixedPitch)
        #expect(!WritingFont.serif.body(size: 16).isFixedPitch)
        #expect(WritingFont.serif.body(size: 16).familyName != WritingFont.sans.body(size: 16).familyName)
        #expect(WritingFont.duo.body(size: 16).isFixedPitch)
        #expect(!WritingFont.duo.heading(size: 20).isFixedPitch)
    }

    @Test func columnFollowsFontAndWidth() {
        let zero = ("0" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)]).width
        #expect(Design.columnWidth(size: 16, font: .mono, width: .normal) == (zero * 64).rounded())
        let narrow = Design.columnWidth(size: 16, font: .sans, width: .narrow)
        let normal = Design.columnWidth(size: 16, font: .sans, width: .normal)
        let wide = Design.columnWidth(size: 16, font: .sans, width: .wide)
        #expect(narrow < normal && normal < wide)
        // About 66 average characters of 16pt sans: well under the mono column.
        #expect(normal > 400 && normal < Design.columnWidth(size: 16, font: .mono, width: .normal))
    }

    @Test func codeStaysMonospacedInProportionalFonts() {
        let s = styled("# Title\n\nPlain `code` here.\n\n```\nlet x = 1\n```\n", look: TypographyLook(font: .serif, bookParagraphs: false))
        #expect(!font(s, at: "Plain").isFixedPitch)
        #expect(!font(s, at: "Title").isFixedPitch)
        #expect(font(s, at: "code").isFixedPitch)
        #expect(font(s, at: "let x").isFixedPitch)
        let duo = styled("# Title\n\nPlain text.\n", look: TypographyLook(font: .duo, bookParagraphs: false))
        #expect(!font(duo, at: "Title").isFixedPitch)
        #expect(font(duo, at: "Plain").isFixedPitch)
    }

    @Test func bookParagraphsIndentAndFoldOnlyBetweenProse() {
        let text = "One para.\n\nTwo para.\n\n# Head\n\nThree para.\n\n- item\n\nFour para.\n"
        let s = styled(text, look: TypographyLook(font: .mono, bookParagraphs: true))
        #expect(paragraph(s, at: "Two").firstLineHeadIndent > 0)
        #expect(paragraph(s, at: "One").firstLineHeadIndent == 0)
        #expect(paragraph(s, at: "Three").firstLineHeadIndent == 0)  // after a heading
        #expect(paragraph(s, at: "Four").firstLineHeadIndent == 0)   // after a list
        let ns = text as NSString
        let foldedBlank = ns.range(of: "One para.\n").length
        #expect((s.attribute(.paragraphStyle, at: foldedBlank, effectiveRange: nil) as! NSParagraphStyle).maximumLineHeight == 1)
        let blankBeforeHead = NSMaxRange(ns.range(of: "Two para.\n"))
        #expect((s.attribute(.paragraphStyle, at: blankBeforeHead, effectiveRange: nil) as! NSParagraphStyle).maximumLineHeight == 0)
        // Display only: the text itself is untouched.
        #expect(s.string == text)
        let off = styled(text, look: TypographyLook(font: .mono, bookParagraphs: false))
        #expect(paragraph(off, at: "Two").firstLineHeadIndent == 0)
    }

    // MARK: Focus and punctuation

    @Test func sentenceFocusFindsTheCaretsSentence() {
        let ns = "First one here. Second one is longer. Third." as NSString
        let block = NSRange(location: 0, length: ns.length)
        let at = ns.range(of: "is longer").location
        #expect(ns.substring(with: Typography.sentence(in: ns, block: block, at: at)).hasPrefix("Second one is longer."))
        #expect(ns.substring(with: Typography.sentence(in: ns, block: block, at: 0)).hasPrefix("First one here."))
        #expect(ns.substring(with: Typography.sentence(in: ns, block: block, at: ns.length)) == "Third.")
    }

    @Test func smartPunctuationKnowsCode() {
        let line = "Say `it" as NSString
        #expect(Typography.isInCode(line, storage: nil, at: line.length))
        let closed = "Say `it` now" as NSString
        #expect(!Typography.isInCode(closed, storage: nil, at: closed.length))
        let fence = "```swift" as NSString
        #expect(Typography.isInCode(fence, storage: nil, at: fence.length))
        let block = styled("Text\n\n```\nlet a = \"b\"\n```\n", look: .current)
        let inside = (block.string as NSString).range(of: "let a").location + 3
        #expect(Typography.isInCode(block.string as NSString, storage: block, at: inside))
    }

    // MARK: Counts and goals

    @Test func subtitleCountsWordsCharactersLinesAndGoal() {
        let words = Array(repeating: "word", count: 320).joined(separator: " ")
        #expect(WritingStats.subtitle(text: words, goal: 500) == "320 / 500 words · 2 min read")
        #expect(WritingStats.subtitle(text: words, goal: 300) == "✓ 320 / 300 words · 2 min read")
        #expect(WritingStats.subtitle(text: words) == "320 words · 2 min read")
        #expect(WritingStats.subtitle(text: words, wordsPerMinute: 100) == "320 words · 4 min read")
        #expect(WritingStats.subtitle(text: "ab cd\nef", style: .characters) == "7 characters · 1 min read")
        #expect(WritingStats.subtitle(text: "a\nb\n\nc\n", style: .lines) == "4 lines · 1 min read")
        #expect(WritingStats.subtitle(text: words, style: .lines, goal: 500) == "1 lines · 320 / 500 words")
        // A selection is counted on its own, without the goal.
        #expect(WritingStats.subtitle(text: words, selection: "word word", goal: 500) == "2 words · 1 min read")
        #expect(WritingStats.lines("") == 0)
        #expect(WritingStats.lines("one") == 1)
    }

    @Test func goalsAreKeptOutsideTheFile() {
        let document = NSDocument()
        #expect(WritingGoals.goal(for: document) == nil)
        WritingGoals.setGoal(750, for: document)
        #expect(WritingGoals.goal(for: document) == 750)
        WritingGoals.setGoal(nil, for: document)
        #expect(WritingGoals.goal(for: document) == nil)
    }

    // MARK: Writing Aids

    func kinds(_ text: String, _ only: Set<WritingAids.Kind> = Set(WritingAids.Kind.allCases)) -> [WritingAids.Kind] {
        WritingAids.findings(in: text, kinds: only).map(\.kind)
    }

    @Test func longSentencesAreTintedByLength() {
        let words = (1...25).map { _ in "word" }.joined(separator: " ") + "."
        let long = WritingAids.findings(in: words, kinds: [.longSentence])
        #expect(long.count == 1 && long[0].strong == false)
        let longer = (1...35).map { _ in "word" }.joined(separator: " ") + "."
        #expect(WritingAids.findings(in: longer, kinds: [.longSentence]).first?.strong == true)
        #expect(WritingAids.findings(in: "A short one. Another short one.", kinds: [.longSentence]).isEmpty)
    }

    @Test func aidsFindRepeatsFillersAdverbsAndPassives() {
        #expect(kinds("We went to the the shop.", [.repeatedWord]) == [.repeatedWord])
        #expect(kinds("We went to the shop. The end.", [.repeatedWord]).isEmpty)
        let filler = WritingAids.findings(in: "This is really good and I think so.", kinds: [.filler])
        #expect(filler.count == 2)
        #expect(kinds("Bu aslında çok güzel bir gün.", [.filler]).count == 2)
        #expect(kinds("Justice matters.", [.filler]).isEmpty)  // not "just"
        #expect(kinds("She quickly closed the heavy wooden door behind her.", [.adverb]) == [.adverb])
        #expect(kinds("The letter was written by the old man in the morning.", [.passive]) == [.passive])
        #expect(kinds("The report is finished and was reviewed twice by our team.", [.passive]).count == 2)
        // English-only aids stay quiet on Turkish.
        #expect(kinds("Mektup sabah erkenden yaşlı adam tarafından yazıldı ve gönderildi.", [.adverb, .passive]).isEmpty)
    }

    @Test func aidsSkipCodeLinksAndFrontMatter() {
        let text = "---\ntitle: very\n---\n\nUse `very` and [very](https://x.io) here.\n\n```\nvery very\n```\n"
        let s = styled(text, look: .current)
        let prose = WritingAids.prose(s, range: NSRange(location: 0, length: (text as NSString).length))
        #expect((prose as NSString).length == (text as NSString).length)
        #expect(!prose.contains("very"))
        #expect(prose.contains("here"))
        #expect(WritingAids.findings(in: prose, kinds: [.filler, .repeatedWord]).isEmpty)
    }

    @Test func settingsHasFourPanesThatFit() throws {
        let tabs = try #require(SettingsWindowController.shared.window?.contentViewController as? NSTabViewController)
        #expect(tabs.tabViewItems.count == 4)
        for (index, item) in tabs.tabViewItems.enumerated() {
            let view = try #require(item.viewController?.view)
            let size = view.fittingSize
            #expect(size.width == 520 && size.height > 120)
            // QM_SNAPSHOT=folder: a PNG of each pane for a visual check.
            if let folder = ProcessInfo.processInfo.environment["QM_SNAPSHOT"] {
                view.frame.size = size
                view.layoutSubtreeIfNeeded()
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: folder).appendingPathComponent("settings-\(index).png"))
                }
            }
        }
    }

    @Test func exportFollowsTheWritingFont() {
        let page = MarkdownHTML.page(body: "<p>x</p>", title: "t", theme: .light, fontSize: 16, baseURL: nil)
        #expect(page.contains(WritingFont.stored.cssBody))
        #expect(page.contains("code { font: inherit; font-family: \(WritingFont.cssMono)"))
    }
}
