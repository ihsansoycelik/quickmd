import AppKit

/// Where the caret may stand while markdown marks are hidden. Hidden
/// characters have no width, so a caret inside them looks stuck: these
/// rules move it to the edge of the hidden run, and keep it out of a
/// block's prefix (`## `, `> `, `- `, `- [ ] `) altogether.
enum Concealment {
    /// A line's block prefix as styled: where its content starts, and
    /// the parts that make it up (absolute ranges).
    struct BlockPrefix: Equatable {
        var contentStart: Int
        var quote: NSRange?
        var heading: NSRange?
        /// Indent, marker, task box and the spaces after them.
        var list: NSRange?
    }

    private static let prefixPattern = try! NSRegularExpression(
        pattern: #"^([ \t]*(?:>[ \t]?)+)?(?:(#{1,6}[ \t]+)|([ \t]*(?:[-*+]|\d{1,9}[.)])(?:[ \t]+\[[ xX]\])?(?:[ \t]+|$)))?"#
    )

    /// The block prefix of the line at `lineRange`, when the styler
    /// treated it as one (a heading, quote or list item outside code).
    static func blockPrefix(lineRange: NSRange, in storage: NSAttributedString) -> BlockPrefix? {
        let ns = storage.string as NSString
        guard lineRange.location < ns.length else { return nil }
        var content = lineRange
        while content.length > 0, "\n\r\u{2028}\u{2029}".utf16.contains(ns.character(at: NSMaxRange(content) - 1)) {
            content.length -= 1
        }
        guard content.length > 0,
              storage.attribute(.qmCodeBlock, at: content.location, effectiveRange: nil) == nil,
              storage.attribute(.qmMathBlock, at: content.location, effectiveRange: nil) == nil,
              let match = prefixPattern.firstMatch(in: ns as String, range: content) else { return nil }
        var prefix = BlockPrefix(contentStart: content.location)
        let quote = match.range(at: 1), heading = match.range(at: 2), list = match.range(at: 3)
        if quote.location != NSNotFound {
            // The first `>` is the styler's: concealed.
            var gt = quote.location
            while gt < NSMaxRange(quote), ns.character(at: gt) != 0x3E { gt += 1 }
            guard storage.attribute(.qmConceal, at: gt, effectiveRange: nil) != nil else { return nil }
            prefix.quote = quote
            prefix.contentStart = NSMaxRange(quote)
        }
        if heading.location != NSNotFound, storage.attribute(.qmConceal, at: heading.location, effectiveRange: nil) != nil {
            prefix.heading = heading
            prefix.contentStart = NSMaxRange(heading)
        } else if list.location != NSNotFound {
            var bullet = list.location
            while bullet < NSMaxRange(list), ns.character(at: bullet) == 0x20 || ns.character(at: bullet) == 0x09 { bullet += 1 }
            if bullet < NSMaxRange(list), storage.attribute(.qmKeepSyntax, at: bullet, effectiveRange: nil) != nil {
                prefix.list = list
                prefix.contentStart = NSMaxRange(list)
            }
        }
        guard prefix.contentStart > content.location else { return nil }
        return prefix
    }

    /// The hidden inline run strictly around `location`, if any.
    static func concealedRun(around location: Int, in storage: NSAttributedString) -> NSRange? {
        guard location > 0, location < storage.length,
              storage.attribute(.qmConceal, at: location - 1, effectiveRange: nil) != nil else { return nil }
        let ns = storage.string as NSString
        let line = ns.lineRange(for: NSRange(location: location, length: 0))
        var run = NSRange()
        guard storage.attribute(.qmConceal, at: location, longestEffectiveRange: &run, in: line) != nil,
              run.location < location else { return nil }
        return run
    }

    /// One arrow step from `location`: past the next (or before the
    /// previous) visible character, hidden marks skipped, never into a
    /// block prefix. Nil when there's nowhere to go.
    static func step(from location: Int, forward: Bool, in storage: NSAttributedString) -> Int? {
        let ns = storage.string as NSString
        func hidden(_ i: Int) -> Bool { storage.attribute(.qmConceal, at: i, effectiveRange: nil) != nil }
        var target: Int
        if forward {
            var i = location
            while i < ns.length, hidden(i) { i += 1 }
            guard i < ns.length else { return nil }
            target = NSMaxRange(ns.rangeOfComposedCharacterSequence(at: i))
        } else {
            var i = location - 1
            while i >= 0, hidden(i) { i -= 1 }
            guard i >= 0 else { return location > 0 ? snap(0, from: location, step: false, in: storage) : nil }
            target = ns.rangeOfComposedCharacterSequence(at: i).location
        }
        // Landing in a block prefix: going on to the content, or back to the line before.
        if target <= ns.length {
            let line = ns.lineRange(for: NSRange(location: min(target, ns.length), length: 0))
            if let prefix = blockPrefix(lineRange: line, in: storage), target >= line.location, target < prefix.contentStart {
                target = forward || line.location == 0 ? prefix.contentStart : line.location - 1
            }
        }
        return target
    }

    /// Where a collapsed caret headed for `location` should land.
    /// `from` is where it was; `step` is true for a one-character move
    /// (an arrow key), which must always move the caret visibly.
    static func snap(_ location: Int, from: Int?, step: Bool, in storage: NSAttributedString) -> Int {
        let ns = storage.string as NSString
        guard ns.length > 0, location <= ns.length else { return location }
        let forward = from.map { location > $0 } ?? true
        if location < ns.length || location > 0 {
            let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
            if let prefix = blockPrefix(lineRange: line, in: storage),
               location >= line.location, location < prefix.contentStart {
                // ← from the content start goes on to the line before.
                if step, !forward, let from, from >= prefix.contentStart, line.location > 0 { return line.location - 1 }
                return prefix.contentStart
            }
        }
        guard let run = concealedRun(around: location, in: storage) else { return location }
        if forward {
            // From the run's start the caret already looks like it's at
            // the end: move past the next character too.
            if step, let from, from >= run.location, from <= NSMaxRange(run), NSMaxRange(run) < ns.length {
                return snap(NSMaxRange(ns.rangeOfComposedCharacterSequence(at: NSMaxRange(run))), from: NSMaxRange(run), step: false, in: storage)
            }
            return NSMaxRange(run)
        }
        if step, let from, from >= run.location, from <= NSMaxRange(run), run.location > 0 {
            let before = ns.rangeOfComposedCharacterSequence(at: run.location - 1).location
            return snap(before, from: run.location, step: true, in: storage)
        }
        return run.location
    }
}
