import AppKit

/// The writing surface: a live-styled markdown text view in a centred
/// column. Draws no background of its own; the window's shows through.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate, NSLayoutManagerDelegate {
    let textView: MarkdownTextView
    private let scrollView: NSScrollView
    private var pendingEdit: NSRange?
    private var settingsObserver: Any?

    /// While a live change plays in, the text it's heading for.
    var currentText: String { playback?.target ?? textView.string }

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        scrollView = NSScrollView()
        let storage = NSTextStorage()
        let layoutManager = HorizontalRuleLayoutManager()
        // Lays out only what's on screen: typing in a long note stays
        // as quick as in a short one.
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        textView = MarkdownTextView(frame: .zero, textContainer: container)
        super.init(nibName: nil, bundle: nil)
        layoutManager.delegate = self
        layoutManager.imageForLine = { [weak self] line, target in
            guard let self, self.isReading, NSIntersectionRange(self.activeLine, line).length == 0 else { return nil }
            return self.localImage(target)
        }
        layoutManager.tableIsRendered = { [weak self] block in
            guard let self, self.isReading else { return false }
            return self.activeTable.map { NSIntersectionRange($0, block).length == 0 } ?? true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    override func loadView() {
        let root = NSView()

        // An overlay scroller, as everywhere on the Mac: hidden at rest,
        // shown while scrolling, so the page stays quiet.
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.delegate = self
        textView.setAccessibilityLabel("Note")
        textView.textStorage?.delegate = self

        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            // Below the title bar, so text never scrolls under the title.
            scrollView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .editorSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.applySettings() }
        applySettings()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateColumn()
    }

    // MARK: Text

    func load(_ text: String) {
        finishPlayback()
        guard text != textView.string else { return }
        let selection = textView.selectedRange()
        textView.string = text
        pendingEdit = nil
        restyleForDisplay()
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        textView.undoManager?.removeAllActions()
    }

    // MARK: Live writing

    /// A change written by another app, typing itself in.
    private struct Playback {
        let target: String
        let start: Int
        let inserted: NSString
        var typed = 0
        var timer: Timer?
    }
    private var playback: Playback?
    private var glowFade: Timer?
    /// Where the glow is drawn, so clearing it leaves the Find highlight alone.
    private var glowRange: NSRange?

    /// Shows `text` arriving as if typed: what changed is taken out,
    /// the new part runs in from the first changed character, the view
    /// follows it, and what arrived glows, then fades. Typing is held
    /// off until it's done, three seconds at most.
    func play(_ text: String) {
        finishPlayback()
        chunkWork?.cancel()
        chunkWork = nil
        styledUpTo = 0
        guard let storage = textView.textStorage, text != textView.string else { return }
        let old = textView.string as NSString, new = text as NSString
        let shorter = min(old.length, new.length)
        var prefix = 0
        while prefix < shorter, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < shorter - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        // Never split a surrogate pair.
        if prefix > 0, UTF16.isLeadSurrogate(new.character(at: prefix - 1)) { prefix -= 1 }
        if suffix > 0, UTF16.isTrailSurrogate(new.character(at: new.length - suffix)) { suffix -= 1 }

        clearGlow()
        storage.replaceCharacters(in: NSRange(location: prefix, length: old.length - prefix - suffix), with: "")
        restyle(edited: NSRange(location: prefix, length: 0))
        let inserted = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix)) as NSString
        playback = Playback(target: text, start: prefix, inserted: inserted)
        textView.isEditable = false
        guard inserted.length > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return finishPlayback() }
        // 60 frames a second: slow enough to read along (180 characters a
        // second), but never longer than three seconds.
        let perTick = max(3, Int((Double(inserted.length) / 180).rounded(.up)))
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.typeNext(perTick) }
        }
        RunLoop.main.add(timer, forMode: .common)
        playback?.timer = timer
    }

    private func typeNext(_ count: Int) {
        guard var p = playback, let storage = textView.textStorage else { return }
        var end = min(p.typed + count, p.inserted.length)
        if end < p.inserted.length { end = NSMaxRange(p.inserted.rangeOfComposedCharacterSequence(at: end)) }
        let chunk = p.inserted.substring(with: NSRange(location: p.typed, length: end - p.typed))
        let at = p.start + p.typed
        storage.replaceCharacters(in: NSRange(location: at, length: 0), with: chunk)
        p.typed = end
        playback = p
        let arrived = NSRange(location: at, length: end - (at - p.start))
        restyle(edited: arrived)
        textView.layoutManager?.addTemporaryAttribute(.backgroundColor, value: glowColor(1), forCharacterRange: arrived)
        glowRange = NSRange(location: p.start, length: p.typed)
        let caret = NSRange(location: p.start + p.typed, length: 0)
        textView.setSelectedRange(caret)
        textView.scrollRangeToVisible(caret)
        if p.typed >= p.inserted.length { finishPlayback() }
    }

    /// Ends a playback at once, with the whole change in place.
    private func finishPlayback() {
        guard let p = playback else { return }
        p.timer?.invalidate()
        playback = nil
        if textView.string != p.target, let storage = textView.textStorage {
            let rest = NSRange(location: p.start + p.typed, length: 0)
            storage.replaceCharacters(in: rest, with: p.inserted.substring(from: p.typed))
            restyle(edited: NSRange(location: p.start, length: p.inserted.length))
        }
        textView.isEditable = true
        // The storage changed under the text view; old undo steps point at the wrong places.
        textView.undoManager?.removeAllActions()
        // Chunked styling resumes over a big note; small ones are done.
        if (textView.string as NSString).length > Self.progressiveLimit, styledUpTo < (textView.string as NSString).length {
            scheduleChunk()
        } else {
            styledUpTo = (textView.string as NSString).length
        }
        fadeGlow(NSRange(location: p.start, length: p.inserted.length))
    }

    private func glowColor(_ strength: CGFloat) -> NSColor {
        NSColor.controlAccentColor.withAlphaComponent((Settings.theme == .dark ? 0.30 : 0.20) * strength)
    }

    /// The arrived text keeps its glow a moment, then lets it go.
    private func fadeGlow(_ range: NSRange) {
        guard range.length > 0, let layoutManager = textView.layoutManager else { return }
        glowFade?.invalidate()
        glowRange = range
        var step = 0
        let steps = 60  // two seconds
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                step += 1
                // Hold for the first half, then fade.
                let strength = step < steps / 2 ? 1 : CGFloat(steps - step) / CGFloat(steps / 2)
                let length = (self.textView.string as NSString).length
                let r = NSIntersectionRange(range, NSRange(location: 0, length: length))
                if step >= steps || r.length == 0 {
                    self.clearGlow()
                } else {
                    layoutManager.addTemporaryAttribute(.backgroundColor, value: self.glowColor(strength), forCharacterRange: r)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        glowFade = timer
    }

    private func clearGlow() {
        glowFade?.invalidate()
        glowFade = nil
        guard let range = glowRange, let layoutManager = textView.layoutManager else { return }
        glowRange = nil
        let length = (textView.string as NSString).length
        let r = NSIntersectionRange(range, NSRange(location: 0, length: length))
        if r.length > 0 { layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r) }
    }

    /// Reading mode (the default): tokens hidden, except on the line
    /// the caret is in, so they can still be edited. Writing mode:
    /// tokens always shown. Both are editable.
    var isReading = true {
        didSet {
            guard isReading != oldValue else { return }
            applyMode()
        }
    }

    func applyMode() {
        guard let layoutManager = textView.layoutManager else { return }
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        refresh(all, layoutManager)
        textView.needsDisplay = true
    }

    private func refresh(_ range: NSRange, _ layoutManager: NSLayoutManager) {
        layoutManager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    }

    /// The line the caret is in: its tokens stay visible in reading mode.
    private var activeLine = NSRange(location: 0, length: 0)

    /// Local pictures by resolved path; nil when a file didn't load.
    private var imageCache: [String: NSImage?] = [:]

    /// A local image: an absolute path, `file:` URL or path relative to
    /// the note. Remote images stay links (nothing is fetched).
    private func localImage(_ target: String) -> NSImage? {
        let decoded = target.removingPercentEncoding ?? target
        let url: URL
        if decoded.hasPrefix("file://"), let u = URL(string: target) {
            url = u
        } else if decoded.hasPrefix("/") {
            url = URL(fileURLWithPath: decoded)
        } else if decoded.hasPrefix("~/") {
            url = URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath)
        } else if !decoded.contains("://"), let base = textView.baseURL {
            url = base.appendingPathComponent(decoded)
        } else {
            return nil
        }
        let key = url.standardizedFileURL.path
        if let cached = imageCache[key] { return cached }
        let image = NSImage(contentsOf: url)
        imageCache[key] = image
        return image
    }

    /// The table the caret is in: shown as source, not as a grid.
    private var activeTable: NSRange?

    private func updateActiveLine() {
        guard isReading, let layoutManager = textView.layoutManager else { return }
        let ns = textView.string as NSString
        let caret = min(textView.selectedRange().location, ns.length)
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        var table: NSRange?
        if let storage = textView.textStorage, line.location < storage.length {
            var block = NSRange()
            if storage.attribute(.qmTable, at: line.location, longestEffectiveRange: &block, in: NSRange(location: 0, length: storage.length)) != nil {
                table = block
            }
        }
        if table != activeTable {
            let old = activeTable
            activeTable = table
            for r in [old, table].compactMap({ $0 }) {
                let clipped = NSIntersectionRange(r, NSRange(location: 0, length: ns.length))
                if clipped.length > 0 { refresh(clipped, layoutManager) }
            }
            textView.needsDisplay = true
        }
        guard line != activeLine else { return }
        let old = NSIntersectionRange(activeLine, NSRange(location: 0, length: ns.length))
        activeLine = line
        if old.length > 0 { refresh(old, layoutManager) }
        refresh(line, layoutManager)
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard isReading, let storage = layoutManager.textStorage else { return false }
        let at = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        // A table drawn as a grid: its first row makes room for the
        // whole grid, the other rows fold away.
        if let grids = layoutManager as? HorizontalRuleLayoutManager, let block = grids.renderedTable(at: at) {
            var height: CGFloat = 0
            if (storage.string as NSString).lineRange(for: NSRange(location: at, length: 0)).location == block.location,
               let grid = grids.grid(for: block, available: grids.gridWidth(forFragmentWidth: lineFragmentRect.pointee.width)) {
                height = grid.height + 2 * TableGrid.margin
            }
            lineFragmentRect.pointee.size.height = height
            lineFragmentUsedRect.pointee.size.height = height
            baselineOffset.pointee = 0
            return true
        }
        if let grids = layoutManager as? HorizontalRuleLayoutManager, let (_, image) = grids.renderedImage(at: at) {
            let size = HorizontalRuleLayoutManager.imageSize(image, available: grids.gridWidth(forFragmentWidth: lineFragmentRect.pointee.width))
            let height = size.height + 2 * HorizontalRuleLayoutManager.imageMargin
            lineFragmentRect.pointee.size.height = height
            lineFragmentUsedRect.pointee.size.height = height
            baselineOffset.pointee = 0
            return true
        }
        guard at < storage.length, !NSLocationInRange(at, activeLine) else { return false }
        if storage.attribute(.qmTableDelimiter, at: at, effectiveRange: nil) != nil {
            lineFragmentRect.pointee.size.height = 1
            lineFragmentUsedRect.pointee.size.height = 1
            baselineOffset.pointee = 0
            return true
        }
        // A paragraph that starts with hidden glyphs (a heading's `## `):
        // TextKit hangs them on the line before, so the visible line no
        // longer starts the paragraph and loses its space above. Put it back.
        let ns = storage.string as NSString
        let start = ns.lineRange(for: NSRange(location: at, length: 0)).location
        guard start < at,
              (start..<at).allSatisfy({ storage.attribute(.qmSyntax, at: $0, effectiveRange: nil) != nil }),
              let before = (storage.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle)?
                .paragraphSpacingBefore, before > 0 else { return false }
        lineFragmentRect.pointee.size.height += before
        lineFragmentUsedRect.pointee.size.height += before
        baselineOffset.pointee += before
        return true
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont, forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard isReading, let storage = layoutManager.textStorage else { return 0 }
        var changed = false
        var out = [NSLayoutManager.GlyphProperty](repeating: [], count: glyphRange.length)
        var glyphOut = [CGGlyph](UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var bullet: UniChar = 0x2022
        var bulletGlyph: CGGlyph = 0
        let hasBullet = CTFontGetGlyphsForCharacters(aFont, &bullet, &bulletGlyph, 1)
        let grids = layoutManager as? HorizontalRuleLayoutManager
        var table: NSRange?
        var notTable = -1
        for i in 0..<glyphRange.length {
            out[i] = props[i]
            let at = charIndexes[i]
            // An image line drawn as its picture hides its source text.
            if let grids, storage.attribute(.qmImage, at: at, effectiveRange: nil) != nil, grids.renderedImage(at: at) != nil {
                if !props[i].contains(.controlCharacter) { out[i] = .null; changed = true }
                continue
            }
            // A table drawn as a grid hides its source text.
            if let grids, at != notTable, storage.attribute(.qmTable, at: at, effectiveRange: nil) != nil {
                if table.map({ !NSLocationInRange(at, $0) }) ?? true { table = grids.renderedTable(at: at) }
                if let table, NSLocationInRange(at, table) {
                    if !props[i].contains(.controlCharacter) { out[i] = .null; changed = true }
                    continue
                }
                notTable = at
            }
            if !NSLocationInRange(at, activeLine), storage.attribute(.qmTaskBullet, at: at, effectiveRange: nil) != nil {
                out[i] = .controlCharacter
                changed = true
                continue
            }
            if !NSLocationInRange(at, activeLine), storage.attribute(.qmSyntax, at: at, effectiveRange: nil) != nil {
                out[i] = .null
                changed = true
            } else if hasBullet, !NSLocationInRange(at, activeLine), storage.attribute(.qmKeepSyntax, at: at, effectiveRange: nil) != nil,
                      let c = (storage.string as NSString).substring(with: NSRange(location: at, length: 1)).utf16.first,
                      c == 0x2D || c == 0x2A || c == 0x2B {
                glyphOut[i] = bulletGlyph
                changed = true
            }
        }
        guard changed else { return 0 }
        out.withUnsafeBufferPointer { props in glyphOut.withUnsafeBufferPointer {
            layoutManager.setGlyphs($0.baseAddress!, properties: props.baseAddress!, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        } }
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = layoutManager.textStorage, charIndex < storage.length,
              storage.attribute(.qmTaskBullet, at: charIndex, effectiveRange: nil) != nil else { return action }
        return .zeroAdvancement
    }

    /// Fence starts kept between keystrokes, so a large note's blocks
    /// don't rescan on every key. A full restyle (load, settings) resets it.
    private let fenceIndex = FenceIndex()

    /// Above this many characters styling runs in chunks: the opening
    /// screen is styled at once, the rest fills in while the note is
    /// being read. Below it, a full restyle is quick enough.
    private static let progressiveLimit = 150_000
    private static let chunkSize = 80_000
    /// Past this (UTF-16 units ≈ a 5 MB file), the note keeps its source
    /// look: markdown styling a note that big costs more than it gives.
    private static let plainTextLimit = 2_500_000
    /// Where chunk styling has reached; `length` when fully styled.
    private var styledUpTo = 0
    private var chunkWork: DispatchWorkItem?
    /// The note is past the plain-text limit: no markdown styling.
    private var isPlainText = false

    /// Styles the note for display: small notes at once, big ones in
    /// chunks that keep the opening screen quick, huge ones as plain text.
    func restyleForDisplay() {
        chunkWork?.cancel()
        chunkWork = nil
        guard let storage = textView.textStorage else { return }
        let length = (storage.string as NSString).length
        guard length <= Self.plainTextLimit else {
            isPlainText = true
            styledUpTo = length
            applyPlainTextLook(storage)
            return
        }
        isPlainText = false
        guard length > Self.progressiveLimit else {
            styledUpTo = length
            restyle()
            return
        }
        styledUpTo = 0
        styleNextChunk()
        scheduleChunk()
    }

    /// One chunk of a progressive restyle, ending on a blank line where
    /// one is near so a table or quote block isn't cut in half. Fences
    /// may straddle the edge: their membership comes from the global
    /// fence list, and contiguous attributes draw one panel anyway.
    private func styleNextChunk() {
        guard let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let length = ns.length
        guard styledUpTo < length else { styledUpTo = length; return }
        var end = min(styledUpTo + Self.chunkSize, length)
        var hunt = end
        for _ in 0..<40 where hunt < length {
            let line = ns.lineRange(for: NSRange(location: hunt, length: 0))
            var i = line.location
            while i < NSMaxRange(line),
                  ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09
                  || ns.character(at: i) == 0x0A || ns.character(at: i) == 0x0D { i += 1 }
            hunt = NSMaxRange(line)
            end = NSMaxRange(line)
            if i == NSMaxRange(line) { break }  // a blank line: a clean edge
        }
        restyle(chunk: NSRange(location: styledUpTo, length: end - styledUpTo))
        styledUpTo = end
    }

    private func scheduleChunk() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.styleNextChunk()
            if self.styledUpTo < (self.textView.string as NSString).length {
                self.scheduleChunk()
            } else {
                self.chunkWork = nil
            }
        }
        chunkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
    }

    /// The huge-note look: the body font and colour, nothing else.
    private func applyPlainTextLook(_ storage: NSTextStorage) {
        let palette = Palette.for(Settings.theme)
        storage.setAttributes(
            [.font: textView.font ?? .systemFont(ofSize: Settings.fontSize), .foregroundColor: palette.text],
            range: NSRange(location: 0, length: (storage.string as NSString).length)
        )
    }

    private func restyle(edited: NSRange? = nil, chunk: NSRange? = nil) {
        guard let storage = textView.textStorage else { return }
        guard !isPlainText else {
            applyPlainTextLook(storage)
            return
        }
        MarkdownStyler.restyle(
            storage, size: Settings.fontSize, theme: Settings.theme,
            edited: edited, chunk: chunk, fenceIndex: fenceIndex
        )
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        if let earlier = pendingEdit {
            let start = min(earlier.location, editedRange.location)
            let earlierEnd = NSMaxRange(earlier) + (editedRange.location <= NSMaxRange(earlier) ? delta : 0)
            let end = max(earlierEnd, NSMaxRange(editedRange))
            pendingEdit = NSRange(location: start, length: max(0, end - start))
        } else {
            pendingEdit = editedRange
        }
    }

    func textDidChange(_ notification: Notification) {
        // Mid-composition the input method's underline must survive;
        // the edit stays pending until it's committed.
        if !textView.hasMarkedText(), let edited = pendingEdit {
            pendingEdit = nil
            restyle(edited: edited)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateActiveLine()
    }

    /// Line breaks stay `\n` in the editor (the document converts on
    /// save), so pasted CRLF text is normalised on the way in.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard let text, text.utf8.contains(0x0D) else { return true }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        DispatchQueue.main.async { textView.insertText(normalized, replacementRange: range) }
        return false
    }

    /// In a new document made from a template, selects the title so
    /// typing replaces it.
    func placeCaretAtFirstBlank() {
        let ns = textView.string as NSString
        var location = 0
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let text = ns.substring(with: line)
            if text.hasPrefix("# ") {
                let title = text.dropFirst(2).trimmingCharacters(in: .newlines)
                textView.setSelectedRange(NSRange(location: line.location + 2, length: (title as NSString).length))
                textView.scrollRangeToVisible(textView.selectedRange())
                return
            }
            location = NSMaxRange(line)
        }
    }

    // MARK: Appearance

    private func applySettings() {
        let theme = Settings.theme
        let palette = Palette.for(theme)
        let font = MarkdownStyler.bodyFont(size: Settings.fontSize)
        view.appearance = NSAppearance(named: theme.appearanceName)
        textView.insertionPointColor = palette.cursor
        textView.selectedTextAttributes = [.backgroundColor: palette.selection]
        if let layoutManager = textView.layoutManager as? HorizontalRuleLayoutManager {
            layoutManager.ruleColor = palette.divider
            layoutManager.codeBlockColor = palette.codeBackground
            layoutManager.panelBorderColor = palette.divider
            layoutManager.panelFillColor = palette.codeBackground
            layoutManager.checkboxColor = palette.text.withAlphaComponent(0.5)
            layoutManager.tableBodyFont = font
        }
        textView.font = font
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.text,
            .paragraphStyle: MarkdownStyler.bodyParagraph(font: font),
        ]
        restyleForDisplay()
        updateColumn()
        textView.needsDisplay = true
    }

    /// The text keeps to `Design.measure` characters; extra width
    /// becomes equal margins either side.
    private func updateColumn() {
        let width = scrollView.contentView.bounds.width
        let minimum: CGFloat = 32
        let inset = max(minimum, ((width - Design.columnWidth(size: Settings.fontSize)) / 2).rounded(.down))
        let size = NSSize(width: inset, height: 40)
        if textView.textContainerInset != size { textView.textContainerInset = size }
    }
}
