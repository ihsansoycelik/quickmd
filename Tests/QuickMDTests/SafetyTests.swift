import Foundation
import Testing
@testable import QuickMD

@MainActor
struct SafetyTests {
    @Test func linksNeverRunPrograms() throws {
        #expect(NoteLinks.canRun(URL(fileURLWithPath: "/Applications/Calculator.app")))
        #expect(NoteLinks.canRun(URL(fileURLWithPath: "/tmp/x/evil.command")))
        #expect(NoteLinks.canRun(URL(fileURLWithPath: "/tmp/x/run.sh")))
        #expect(NoteLinks.canRun(URL(fileURLWithPath: "/bin/ls")))
        #expect(!NoteLinks.canRun(URL(fileURLWithPath: "/tmp/x/photo.png")))
        #expect(!NoteLinks.canRun(URL(fileURLWithPath: "/tmp/x/report.pdf")))
    }

    @Test func wordCount() {
        let c = DocumentWindowController.counts("# Title\n\nTwo words, *three* here.\n")
        #expect(c.words == 5)
        #expect(c.characters == 31)
        #expect(DocumentWindowController.counts("").words == 0)
    }

    @Test func englishIsTheFallback() {
        #expect(L("Some key that has no translation") == "Some key that has no translation")
    }
}
