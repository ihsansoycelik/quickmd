import AppKit

/// Folded sections: a heading's body (up to the next heading of the
/// same or a higher level) drawn as nothing, with a small `…` after the
/// heading. Purely visual: the text, and so the file, never changes.
/// Editing in a folded body, or the caret going into it, unfolds it.
enum Folding {
    struct Fold: Equatable {
        /// Start of the heading's line.
        var heading: Int
        /// The hidden lines, their last newline included.
        var body: NSRange
    }

    /// The heading whose section holds `location`: the last one at or before it.
    static func sectionHeading(in text: String, at location: Int) -> Headings.Heading? {
        Headings.find(in: text).last { $0.location <= location }
    }

    /// The body of the section the heading at `heading` opens, or nil
    /// when there's nothing but blank lines to fold.
    static func sectionBody(in text: String, heading location: Int) -> NSRange? {
        let headings = Headings.find(in: text)
        guard let i = headings.firstIndex(where: { $0.location == location }) else { return nil }
        let ns = text as NSString
        var start = NSMaxRange(ns.lineRange(for: NSRange(location: location, length: 0)))
        // A setext heading's underline stays with it.
        if !ns.substring(with: ns.lineRange(for: NSRange(location: location, length: 0)))
            .trimmingCharacters(in: .whitespaces).hasPrefix("#"), start < ns.length {
            start = NSMaxRange(ns.lineRange(for: NSRange(location: start, length: 0)))
        }
        let level = headings[i].level
        let end = headings[(i + 1)...].first(where: { $0.level <= level })?.location ?? ns.length
        guard end > start else { return nil }
        let body = NSRange(location: start, length: end - start)
        guard !ns.substring(with: body).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return body
    }

    /// Folds after an edit that replaced `old` (a range before the edit)
    /// with `delta` more characters: those before it shift, those after
    /// it stay, those it touched are dropped.
    /// `insertsLines`: the edit only inserted text ending in a newline,
    /// so lines put in right before a heading leave it whole.
    static func adjust(_ folds: [Fold], replacing old: NSRange, delta: Int,
                       insertsLines: Bool = false) -> (kept: [Fold], dropped: [Fold]) {
        var kept: [Fold] = [], dropped: [Fold] = []
        let s = old.location, e = NSMaxRange(old)
        for var fold in folds {
            let end = NSMaxRange(fold.body)
            if e < fold.heading || (insertsLines && old.length == 0 && s == fold.heading) {
                fold.heading += delta
                fold.body.location += delta
                kept.append(fold)
            } else if s > end || (s == end && e == end) {
                kept.append(fold)
            } else {
                dropped.append(fold)
            }
        }
        return (kept, dropped)
    }
}

/// The folds of one editor, and what the layout asks of them.
@MainActor
final class FoldController {
    private(set) var folds: [Folding.Fold] = []
    private weak var textView: MarkdownTextView?
    private weak var layoutManager: HorizontalRuleLayoutManager?

    func attach(_ textView: MarkdownTextView, _ layoutManager: HorizontalRuleLayoutManager) {
        self.textView = textView
        self.layoutManager = layoutManager
        textView.folding = self
        layoutManager.folding = self
    }

    var hasFolds: Bool { !folds.isEmpty }

    func isFolded(_ location: Int) -> Bool {
        folds.contains { NSLocationInRange(location, $0.body) }
    }

    // MARK: Commands

    func canPerform(_ action: Selector, in textView: MarkdownTextView) -> Bool {
        switch action {
        case #selector(MarkdownTextView.foldSection(_:)):
            guard let heading = Folding.sectionHeading(in: textView.string, at: textView.selectedRange().location) else { return false }
            return !folds.contains { $0.heading == heading.location }
                && Folding.sectionBody(in: textView.string, heading: heading.location) != nil
        case #selector(MarkdownTextView.unfoldSection(_:)):
            return foldToOpen(at: textView.selectedRange().location) != nil
        default:
            return hasFolds
        }
    }

    func foldSection() {
        guard let textView else { return }
        let text = textView.string
        let ns = text as NSString
        guard let heading = Folding.sectionHeading(in: text, at: textView.selectedRange().location),
              !folds.contains(where: { $0.heading == heading.location }),
              let body = Folding.sectionBody(in: text, heading: heading.location) else { return NSSound.beep() }
        // The caret waits at the end of the heading, outside what hides.
        let line = ns.lineRange(for: NSRange(location: heading.location, length: 0))
        var end = NSMaxRange(line)
        while end > line.location, ns.character(at: end - 1) == 0x0A { end -= 1 }
        textView.setSelectedRange(NSRange(location: end, length: 0))
        folds.append(.init(heading: heading.location, body: body))
        refresh(NSRange(location: heading.location, length: NSMaxRange(body) - heading.location))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// The fold on the caret's heading line, else the one closest above.
    private func foldToOpen(at location: Int) -> Folding.Fold? {
        guard let textView else { return nil }
        let ns = textView.string as NSString
        let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        if let onLine = folds.first(where: { NSLocationInRange($0.heading, line) || $0.heading == line.location }) { return onLine }
        guard let heading = Folding.sectionHeading(in: textView.string, at: location) else { return nil }
        return folds.first { $0.heading == heading.location }
    }

    func unfoldSection() {
        guard let textView, let fold = foldToOpen(at: textView.selectedRange().location) else { return NSSound.beep() }
        // Folds inside it open with it.
        let opened = folds.filter { $0 == fold || NSLocationInRange($0.heading, fold.body) }
        folds.removeAll { opened.contains($0) }
        refresh(NSRange(location: fold.heading, length: NSMaxRange(fold.body) - fold.heading))
    }

    func unfoldAll() {
        guard let textView, hasFolds else { return }
        folds.removeAll()
        refresh(NSRange(location: 0, length: (textView.string as NSString).length))
    }

    // MARK: Following the text

    /// From the storage's didProcessEditing: layout isn't updated yet,
    /// so dropped folds are redrawn just after.
    func storageEdited(_ range: NSRange, delta: Int) {
        guard hasFolds else { return }
        let old = NSRange(location: range.location, length: max(0, range.length - delta))
        var insertsLines = false
        if let ns = textView?.textStorage?.string as NSString?, range.length > 0, NSMaxRange(range) <= ns.length {
            insertsLines = ns.character(at: NSMaxRange(range) - 1) == 0x0A
        }
        let (kept, dropped) = Folding.adjust(folds, replacing: old, delta: delta, insertsLines: insertsLines)
        folds = kept
        guard !dropped.isEmpty else { return }
        let start = dropped.map(\.heading).min()!
        let end = dropped.map { NSMaxRange($0.body) }.max()! + max(0, delta)
        DispatchQueue.main.async { [weak self] in
            self?.refresh(NSRange(location: min(start, range.location), length: max(end, NSMaxRange(range)) - min(start, range.location)))
        }
    }

    /// The caret went into a folded body: it opens.
    func selectionChanged() {
        guard hasFolds, let textView, textView.selectedRange().length == 0 else { return }
        let caret = textView.selectedRange().location
        let length = (textView.string as NSString).length
        let entered = folds.filter {
            caret >= $0.body.location && (caret < NSMaxRange($0.body) || (caret == length && NSMaxRange($0.body) == length))
        }
        guard !entered.isEmpty else { return }
        folds.removeAll { entered.contains($0) }
        for fold in entered { refresh(NSRange(location: fold.heading, length: NSMaxRange(fold.body) - fold.heading)) }
    }

    private func refresh(_ range: NSRange) {
        guard let textView, let layoutManager else { return }
        let length = (textView.string as NSString).length
        let r = NSIntersectionRange(range, NSRange(location: 0, length: length))
        guard r.length > 0 || length == 0 else { return }
        layoutManager.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: r, actualCharacterRange: nil)
        textView.needsDisplay = true
    }

    // MARK: Drawing

    /// The parts of `glyphs` outside folded bodies, or nil when no fold
    /// touches it (the caller then draws it as usual).
    func visibleParts(of glyphs: NSRange, in layoutManager: NSLayoutManager) -> [NSRange]? {
        guard hasFolds else { return nil }
        let hidden = folds.map { layoutManager.glyphRange(forCharacterRange: $0.body, actualCharacterRange: nil) }
            .filter { NSIntersectionRange($0, glyphs).length > 0 }
            .sorted { $0.location < $1.location }
        guard !hidden.isEmpty else { return nil }
        var parts: [NSRange] = []
        var at = glyphs.location
        for h in hidden {
            if h.location > at { parts.append(NSRange(location: at, length: h.location - at)) }
            at = max(at, NSMaxRange(h))
        }
        if at < NSMaxRange(glyphs) { parts.append(NSRange(location: at, length: NSMaxRange(glyphs) - at)) }
        return parts
    }

    /// A quiet `…` chip after each folded heading in `glyphs`.
    func drawMarkers(forGlyphRange glyphs: NSRange, at origin: NSPoint, in layoutManager: NSLayoutManager) {
        guard hasFolds, let storage = layoutManager.textStorage, let container = layoutManager.textContainers.first else { return }
        let ns = storage.string as NSString
        let palette = Palette.for(Settings.theme)
        for fold in folds where fold.heading < ns.length {
            let line = ns.lineRange(for: NSRange(location: fold.heading, length: 0))
            var end = NSMaxRange(line)
            while end > line.location, ns.character(at: end - 1) == 0x0A { end -= 1 }
            guard end > line.location else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: end - 1)
            guard NSLocationInRange(glyph, glyphs) || glyph == NSMaxRange(glyphs) - 1 else { continue }
            let font = storage.attribute(.font, at: end - 1, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
            let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = fragment.minY + layoutManager.location(forGlyphAt: glyph).y
            let label = NSAttributedString(string: "…", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: max(10, font.pointSize * 0.75), weight: .regular),
                .foregroundColor: palette.text.withAlphaComponent(0.6),
            ])
            let size = label.size()
            let chip = NSRect(x: origin.x + box.maxX + 8, y: origin.y + baseline - font.xHeight / 2 - size.height / 2 - 1,
                              width: size.width + 10, height: size.height + 2)
            palette.codeBackground.withAlphaComponent(Settings.theme == .dark ? 0.12 : 0.09).setFill()
            NSBezierPath(roundedRect: chip, xRadius: chip.height / 2, yRadius: chip.height / 2).fill()
            label.draw(at: NSPoint(x: chip.minX + 5, y: chip.minY + 1))
        }
    }
}

extension MarkdownTextView {
    @objc func foldSection(_ sender: Any?) { folding?.foldSection() }
    @objc func unfoldSection(_ sender: Any?) { folding?.unfoldSection() }
    @objc func unfoldAll(_ sender: Any?) { folding?.unfoldAll() }
}
