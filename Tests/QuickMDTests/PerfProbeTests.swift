import AppKit
import Testing
@testable import QuickMD

/// Temporary probe for the Tur 2 measurements. Not committed: wall-clock
/// numbers are machine-dependent (audit/04 flagged flaky perf tests).
@MainActor
struct PerfProbeTests {
    /// A realistic mix: headings, paragraphs, tables, fences, inline styles.
    static func sample(blocks: Int) -> String {
        var parts: [String] = []
        parts.reserveCapacity(blocks * 14)
        for i in 0..<blocks {
            parts.append("# Section \(i)\n")
            parts.append("Some **bold** and *italic* and `inline code` and a [link](https://example.com/x) plus ==marked== text.\n")
            parts.append("Second paragraph with more words to fill the line out a little, and ~~struck~~ text.\n\n")
            parts.append("| Komut \(i) | Ne yapar | Ek | Daha |\n|---|---|---|---|\n")
            parts.append("| `!switch` | Ön modeli sıradakine geçirir | bir | iki |\n")
            parts.append("| `!status` | Kuyruk, bütçe, model sağlığı | üç | dört |\n\n")
            parts.append("- **Ön model (front):** Seninle konuşan model. Varsayılanı Anthropic key ile **Haiku 5.5**.\n")
            parts.append("- **Beyin (brain):** z.ai'deki **GLM 5.3**. Görevleri planlar, alt ajanlara dağıtır.\n")
            parts.append("- **Alt ajanlar:** kodcu, araştırmacı, eleştirmen, sysadmin, board, memory, prover.\n\n")
            parts.append("```swift\nlet value = compute(input: \(i))\nprint(\"\\(value)\")\n```\n\n")
            parts.append("> [!TIP]\n> A callout with **bold** words and `code` inside it.\n\n")
            parts.append("1. Penceredeki öğeleri toplar (varsayılan 7 gün).\n2. Konu dışı ve gürültü olanları eler.\n\n")
            parts.append("---\n\n")
        }
        return parts.joined()
    }

    @Test func probe() {
        for megabytes in [0.02, 0.25, 1.0] {
            let text = Self.sample(blocks: max(2, Int(megabytes * 1_000_000 / 2800)))
            let size = (text as NSString).length
            let ns = text as NSString

            func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

            // Full restyle.
            let storage = NSTextStorage(string: text)
            var t = now()
            MarkdownStyler.restyle(storage, size: 15, theme: .dark)
            let full = (now() - t) * 1000

            // Keystrokes at three kinds of lines: plain, table, fence body.
            // Like the real editor: the edit is wrapped in
            // beginEditing/endEditing (attribute fixing happens there,
            // before the restyle runs), and a fence index is kept.
            func keystroke(at caret: Int, label: String) -> String {
                let paragraph = ns.paragraphRange(for: NSRange(location: caret, length: 0))
                let line = String(ns.substring(with: paragraph).replacingOccurrences(of: "\n", with: "").prefix(30))
                func timed(index: FenceIndex?) -> Double {
                    var fastest = Double.greatestFiniteMagnitude
                    for _ in 0..<5 {
                    let s2 = NSTextStorage(string: text)
                    let idx = index.map { _ in FenceIndex() }
                    MarkdownStyler.restyle(s2, size: 15, theme: .dark, fenceIndex: idx)
                    s2.beginEditing()
                    s2.replaceCharacters(in: NSRange(location: paragraph.location, length: 1), with: "X")
                    s2.endEditing()
                    _ = s2.attribute(.font, at: paragraph.location, effectiveRange: nil)  // pay any fixing here
                    let start = now()
                        MarkdownStyler.restyle(s2, size: 15, theme: .dark, edited: paragraph, fenceIndex: idx)
                        fastest = min(fastest, (now() - start) * 1000)
                    }
                    return fastest
                }
                let without = timed(index: nil)
                let with = timed(index: FenceIndex())
                return String(format: "   %@ [%@]: %.2f ms scanless-index | %.2f ms full-scan", label, line, with, without)
            }

            // Find a plain body line, a table row and a fence body near the middle.
            var plain = -1, table = -1, fence = -1
            var lineStart = size / 4
            while lineStart < size * 3 / 4 {
                let line = ns.lineRange(for: NSRange(location: lineStart, length: 0))
                let body = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
                if plain < 0, body.hasPrefix("Some **bold**") { plain = line.location }
                if table < 0, body.hasPrefix("|") { table = line.location }
                if fence < 0, body.hasPrefix("let value") { fence = line.location }
                lineStart = NSMaxRange(line)
            }

            t = now()
            _ = MarkdownStyler.blockFenceLineStarts(in: ns)
            let fenceScan = (now() - t) * 1000

            // A mutable-backed NSString, as the editor's storage really bridges.
            // The result is consumed so release mode can't discard the work.
            let mutable = NSMutableString(string: text)
            t = now()
            let copied = mutable as String
            let copy = (now() - t) * 1000 + Double(copied.utf16.count > 0 ? 0 : 1)

            print(String(format: "PROBE %.2f MB (utf16 %d): full restyle %.0f ms | fence scan %.2f ms | mutable-String copy %.2f ms",
                         megabytes, size, full, fenceScan, copy))
            print(keystroke(at: plain >= 0 ? plain : size / 2, label: "plain   "))
            print(keystroke(at: table >= 0 ? table : size / 2, label: "table   "))
            print(keystroke(at: fence >= 0 ? fence : size / 2, label: "fence   "))
            #expect(true)
        }
    }
}
