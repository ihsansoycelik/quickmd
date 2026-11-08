import Foundation
import Testing
@testable import QuickMD

/// The incremental fence index must always agree with a full scan, under
/// random edits — an off-by-one here would style the wrong lines.
@MainActor
struct FenceIndexTests {
    /// Fences, math fences, tables and plain text mixed, so edits land on
    /// every kind of line.
    private static let document = """
    # Title

    ```swift
    let a = 1
    let b = 2
    ```

    $$x + y$$

    - a list item
    - another item

    ```
    unclosed block stays code
    to the end of its paragraph

    $$sqrt(x)$$ inside code is not math
    ```

    | a | b |
    |---|---|
    | 1 | 2 |

    $$
    y = mx + b
    $$

    Plain text after everything.

    ```swift
    let c = 3
    ```
    """

    @Test func incrementalMatchesFullScanUnderRandomEdits() {
        let seed = 20261106
        var state = UInt64(seed)
        func random(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return bound <= 0 ? 0 : Int((state >> 33) % UInt64(bound))
        }

        var text = Self.document
        var lastText = text
        var expectedBefore: (code: [Int], math: [Int]) = ([], [])
        let index = FenceIndex()
        let ns = text as NSString
        var expected = MarkdownStyler.blockFenceLineStarts(in: ns)
        index.reset(ns: ns)
        // Longer strings exercise more survivor shifting; 300 edits is
        // plenty and keeps the test quick. `edited` mirrors what
        // NSTextStorage reports: the post-edit range of the change.
        for step in 0..<300 {
            let length = (text as NSString).length
            let at = random(length)
            let edited: NSRange
            switch random(4) {
            case 0, 1:  // insert
                let insertions = ["`", "$", "\n", "x", "\n```\n", "\n$$\n", "|", " ", "```", "$$"]
                let what = insertions[random(insertions.count)]
                text = (text as NSString).replacingCharacters(in: NSRange(location: at, length: 0), with: what)
                edited = NSRange(location: at, length: (what as NSString).length)
            case 2:  // delete
                let count = min(random(6) + 1, length - at)
                text = (text as NSString).replacingCharacters(in: NSRange(location: at, length: count), with: "")
                edited = NSRange(location: at, length: 0)
            default:  // replace a small run
                let count = min(random(4) + 1, length - at)
                text = (text as NSString).replacingCharacters(in: NSRange(location: at, length: count), with: "-")
                edited = NSRange(location: at, length: 1)
            }
            let string = text as NSString
            expectedBefore = expected
            let actual = index.update(ns: string, edited: edited)
            expected = MarkdownStyler.blockFenceLineStarts(in: string)
            if actual.code != expected.code, ProcessInfo.processInfo.environment["FENCE_DEBUG"] != nil {
                let nsOld = lastText as NSString
                let nsNew = string
                let around = { (ns: NSString, at: Int, span: Int) -> String in
                    let lo = max(0, at - span), hi = min(ns.length, at + span)
                    return ns.substring(with: NSRange(location: lo, length: hi - lo)).replacingOccurrences(of: "\n", with: "⏎")
                }
                print("DIVERGED step=\(step) at=\(at) edited=\(edited) oldArrays=\(expectedBefore) aroundOld=\(around(nsOld, at, 24)) aroundNew=\(around(nsNew, at, 24))")
            }
            lastText = text
            #expect(actual.code == expected.code, "step \(step): code fences diverged at \(at)")
            #expect(actual.math == expected.math, "step \(step): math fences diverged at \(at)")
            if actual.code != expected.code || actual.math != expected.math { return }
        }
    }

    /// A pure insertion and a pure deletion at one spot — the two cases
    /// the coordinate shifting exists for.
    @Test func shiftSurvivorsOnInsertAndDelete() {
        let index = FenceIndex()
        let first = "a\n```\ncode\n```\nb\n$$\nmath\n$$\nc" as NSString
        // Fences at 2 and 11; the `$$` lines come after the closing
        // fence, so they are math.
        index.reset(ns: first)

        // Insert "xy\n\n" at the top: every entry shifts by 4.
        let grown = "xy\n\n" + (first as String) as NSString
        let inserted = index.update(ns: grown, edited: NSRange(location: 0, length: 4))
        #expect(inserted.code == [6, 15])
        #expect(inserted.math == [21, 29])

        // Delete it again: entries come back to where they were.
        let shrunk = index.update(ns: first, edited: NSRange(location: 0, length: 4))
        #expect(shrunk.code == [2, 11])
        #expect(shrunk.math == [17, 25])

        // Editing inside the code block changes nothing structurally.
        let edited = index.update(ns: first, edited: NSRange(location: 6, length: 4))
        #expect(edited.code == [2, 11])
        #expect(edited.math == [17, 25])

        /// A deletion that merges the closing fence's line into the line
        /// above stops it being a fence: the block stays open, and the
        /// `$$` lines after it become code, not math.
        var merged = (first as String)
        merged = merged.replacingOccurrences(of: "e\n```\nb\n", with: "e b\n")
        let closed = index.update(ns: merged as NSString, edited: NSRange(location: 10, length: 0))
        #expect(closed.code == [2])
        #expect(closed.math == [])
    }
}
