import AppKit
import Testing
@testable import QuickMD

/// The formatting bar: the block style it reads off a line, its settings
/// and the caret line it follows.
@MainActor
struct FormattingBarTests {
    @Test func lineStyles() {
        #expect(LineStyle.of("plain text") == LineStyle())
        #expect(LineStyle.of("## Title").heading == 2)
        #expect(LineStyle.of("#### Four").heading == 4)
        #expect(LineStyle.of("#").heading == 1)
        #expect(LineStyle.of("#hashtag").heading == 0)
        #expect(LineStyle.of("    # indented code").heading == 0)
        #expect(LineStyle.of("- item").list == .bullet)
        #expect(LineStyle.of("  * nested").list == .bullet)
        #expect(LineStyle.of("12. step").list == .numbered)
        #expect(LineStyle.of("1) step").list == .numbered)
        #expect(LineStyle.of("- [ ] task").list == .task)
        #expect(LineStyle.of("- [x] done").list == .task)
        #expect(LineStyle.of("2019. It rained.").list == .numbered)
        #expect(LineStyle.of("-dash").list == nil)
        let quoted = LineStyle.of("> - [ ] quoted task")
        #expect(quoted.quote && quoted.list == .task)
        #expect(LineStyle.of("> > ## Deep").heading == 2)
        #expect(LineStyle.of(">quote").quote)
    }

    @Test func settingsDefaults() {
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: "ShowFormattingBar"), defaults.object(forKey: "PaperBackground"))
        defer {
            defaults.set(saved.0, forKey: "ShowFormattingBar")
            defaults.set(saved.1, forKey: "PaperBackground")
        }
        defaults.removeObject(forKey: "ShowFormattingBar")
        defaults.removeObject(forKey: "PaperBackground")
        #expect(Settings.showsFormattingBar)
        #expect(!Settings.paperBackground)
    }

    @Test func paperChangesOnlyTheGround() {
        for theme in Theme.allCases {
            #expect(Palette.editorBackground(theme, paper: false) == Palette.for(theme).background)
            #expect(Palette.editorBackground(theme, paper: true) != Palette.for(theme).background)
        }
    }

    @Test func styleFollowsCaret() {
        let controller = EditorViewController()
        _ = controller.view
        controller.load("# Title\n\nBody line\n\n### Third")
        controller.textView.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(controller.formattingBar.styleTitle == String(format: L("Heading %d"), 1))
        controller.textView.setSelectedRange(NSRange(location: 12, length: 0))
        #expect(controller.formattingBar.styleTitle == L("Body"))
        let end = (controller.textView.string as NSString).length
        controller.textView.setSelectedRange(NSRange(location: end, length: 0))
        #expect(controller.formattingBar.styleTitle == String(format: L("Heading %d"), 3))
    }
}
