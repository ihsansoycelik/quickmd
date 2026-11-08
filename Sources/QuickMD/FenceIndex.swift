import Foundation

/// Code- and math-fence line starts kept across keystrokes, so an edit
/// restyles from an updated index instead of rescanning a large note
/// line by line. An edit can only create or destroy fence lines at or
/// after the edited line and before the next fence line that survives
/// it, so that span is rescanned and everything past it just shifts.
@MainActor
final class FenceIndex {
    private var length = -1
    private var code: [Int] = []
    /// Raw `$$` candidates, unfiltered by code parity: a fence that goes
    /// away above them can turn them back into math, so the filter runs
    /// over the whole list each update and must see everyone.
    private var mathCandidates: [Int] = []

    /// Discards the cache and scans the whole note.
    @discardableResult
    func reset(ns: NSString) -> (code: [Int], math: [Int]) {
        let scanned = MarkdownStyler.scanFenceLineStarts(in: ns, range: NSRange(location: 0, length: ns.length))
        code = scanned.code
        mathCandidates = scanned.mathCandidates
        length = ns.length
        let math = mathCandidates.filter { !MarkdownStyler.isInsideBlock($0, fences: code) }
        return (code, math)
    }

    /// Fence starts after `edited` (post-edit coordinates), updated
    /// incrementally. A tangle — anything whose coordinates don't line
    /// up — costs a full scan, never a wrong one.
    func update(ns: NSString, edited: NSRange) -> (code: [Int], math: [Int]) {
        guard length >= 0 else { return reset(ns: ns) }
        let delta = ns.length - length
        length = ns.length
        guard edited.location >= 0, NSMaxRange(edited) <= ns.length,
              delta >= -ns.length, delta <= ns.length else { return reset(ns: ns) }
        // The edited span in old coordinates; entries at or past its end
        // survive the edit and move by `delta`.
        let oldEnd = NSMaxRange(edited) - delta
        guard oldEnd >= 0 else { return reset(ns: ns) }
        let firstLine = ns.lineRange(for: NSRange(location: edited.location, length: 0)).location

        // Entries before the edited line keep their coordinates; entries
        // inside the span are dropped and rescanned; entries past it shift.
        let keptCode = code.filter { $0 < firstLine }
        let keptCandidates = mathCandidates.filter { $0 < firstLine }
        var survivingCode = code.firstIndex { $0 >= oldEnd }.map { code[$0...].map { $0 + delta } } ?? []
        var survivingCandidates = mathCandidates.firstIndex { $0 >= oldEnd }.map { mathCandidates[$0...].map { $0 + delta } } ?? []
        // The first survivor can't be trusted as-is: a deletion can pull
        // its line's start into the middle of a merged line, so its fence
        // no longer opens a block; an insertion can grow text ahead of it
        // on the same line. Its whole line is rescanned and it is
        // re-derived there; later survivors' lines are untouched.
        let firstSurvivor = [survivingCode.first, survivingCandidates.first].compactMap { $0 }.min()
        let scanEnd: Int
        if let firstSurvivor {
            scanEnd = NSMaxRange(ns.lineRange(for: NSRange(location: firstSurvivor, length: 0)))
            survivingCode = survivingCode.filter { $0 >= scanEnd }
            survivingCandidates = survivingCandidates.filter { $0 >= scanEnd }
        } else {
            scanEnd = ns.length
        }
        guard scanEnd >= firstLine, scanEnd <= ns.length else { return reset(ns: ns) }
        let scanned = MarkdownStyler.scanFenceLineStarts(
            in: ns, range: NSRange(location: firstLine, length: scanEnd - firstLine))
        let newCode = keptCode + scanned.code + survivingCode
        // Parity against the new code fences, over every candidate: an
        // edit above a `$$` block can move it into or out of code. Entries
        // before the edit keep their parity by construction; re-filtering
        // them is free.
        let candidates = keptCandidates + scanned.mathCandidates + survivingCandidates
        let newMath = candidates.filter { !MarkdownStyler.isInsideBlock($0, fences: newCode) }
        code = newCode
        mathCandidates = candidates
        return (newCode, newMath)
    }
}
