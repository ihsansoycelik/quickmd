import AppKit

/// The writing surface: a live-styled markdown text view over the
/// document's text, with a quiet footer underneath. Draws no
/// background of its own; the window's glass shows through.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate, NSLayoutManagerDelegate {
    let textView: MarkdownTextView
    private let scrollView: NSScrollView
    private let footer = EditorFooter()
    private var footerHeight: NSLayoutConstraint!
    private var pendingEdit: NSRange?
    private var settingsObserver: Any?
    /// Whole-note work (counts, outline, preview) waits for a pause in typing.
    private var idleWork: DispatchWorkItem?
    private var stats = TextStats.Counts()

    /// Called after every edit (debounced by the receiver if it wants).
    var onTextChange: ((String) -> Void)?
    /// Called when the caret moves, with its UTF-16 offset.
    var onCaretMove: ((Int) -> Void)?

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

        footer.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(scrollView)
        root.addSubview(footer)
        // A click on the count switches words, characters, reading time.
        footer.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(cycleFooterStat(_:))))
        footer.toolTip = "Click to show words, characters or reading time"
        footerHeight = footer.heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            // Below the title bar, so text never scrolls under the title.
            scrollView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footerHeight,
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
        restyle()
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        textView.undoManager?.removeAllActions()
        noteChanged(immediately: true)
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
        noteChanged(immediately: true)
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

    private func updateActiveLine() {
        guard isReading, let layoutManager = textView.layoutManager else { return }
        let ns = textView.string as NSString
        let caret = min(textView.selectedRange().location, ns.length)
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
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
        for i in 0..<glyphRange.length {
            out[i] = props[i]
            let at = charIndexes[i]
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

    private func restyle(edited: NSRange? = nil) {
        guard let storage = textView.textStorage else { return }
        MarkdownStyler.restyle(
            storage, face: Settings.fontFace, size: Settings.fontSize,
            theme: Settings.theme, template: Settings.template,
            headingFace: Settings.headingFace, edited: edited
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
        noteChanged(immediately: false)
    }

    /// Counts, outline and preview cover the whole note, so while
    /// typing they run once the keys pause, not on every keystroke.
    private func noteChanged(immediately: Bool) {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.textView.string
            self.stats = TextStats.counts(in: text)
            self.updateStatus()
            self.onTextChange?(text)
        }
        idleWork = work
        if immediately { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work) }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateActiveLine()
        updateStatus()
        onCaretMove?(textView.selectedRange().location)
    }

    /// Line breaks stay `\n` in the editor (the document converts on
    /// save), so pasted CRLF text is normalised on the way in.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard let text, text.utf8.contains(0x0D) else { return true }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        DispatchQueue.main.async { textView.insertText(normalized, replacementRange: range) }
        return false
    }

    func reveal(location: Int) {
        let length = (textView.string as NSString).length
        let range = NSRange(location: min(location, length), length: 0)
        textView.setSelectedRange(range)
        // Put the heading near the top rather than wherever scrolling stops.
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            let y = max(0, rect.minY + textView.textContainerOrigin.y - 24)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        view.window?.makeFirstResponder(textView)
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
        let template = Settings.template
        let palette = Palette.for(theme, template: template)
        view.appearance = NSAppearance(named: theme.appearanceName)
        textView.insertionPointColor = palette.cursor
        textView.selectedTextAttributes = [.backgroundColor: palette.selection]
        footerHeight.constant = Settings.showsStatusBar ? 44 : 0
        footer.isHidden = !Settings.showsStatusBar
        if let layoutManager = textView.layoutManager as? HorizontalRuleLayoutManager {
            layoutManager.ruleColor = palette.divider
            layoutManager.codeBlockColor = Palette.codeBackground(for: theme, template: template)
            layoutManager.panelBorderColor = palette.divider
            layoutManager.panelFillColor = Palette.codeBackground(for: theme, template: template)
            layoutManager.checkboxColor = palette.text.withAlphaComponent(0.5)
        }
        let font = MarkdownStyler.bodyFont(face: Settings.fontFace, size: Settings.fontSize, template: template)
        textView.font = font
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.text,
            .paragraphStyle: MarkdownStyler.bodyParagraph(font: font, template: template),
        ]
        restyle()
        updateColumn()
        updateStatus()
        textView.needsDisplay = true
    }

    /// Past a comfortable measure (about 30–34 ems, near 70 characters) extra width becomes
    /// margin rather than longer lines.
    private func updateColumn() {
        let width = scrollView.contentView.bounds.width
        let minimum: CGFloat = 32
        var inset = minimum
        if Settings.readableWidth, Settings.template.measure > 0 {
            let measure = Settings.fontSize * Settings.template.measure
            inset = max(minimum, ((width - measure) / 2).rounded(.down))
        }
        let size = NSSize(width: inset, height: 28)
        if textView.textContainerInset != size { textView.textContainerInset = size }
    }

    private func updateStatus() {
        guard Settings.showsStatusBar else { return }
        let selection = textView.selectedRange()
        if selection.length > 0 {
            let selected = TextStats.counts(in: (textView.string as NSString).substring(with: selection))
            footer.label = Settings.footerStat.label(selected, of: stats)
        } else {
            footer.label = Settings.footerStat.label(stats)
        }
    }

    @objc private func cycleFooterStat(_ sender: Any?) {
        Settings.footerStat = Settings.footerStat.next
        updateStatus()
    }
}

/// The quiet footer: the word count, in tertiary grey.
final class EditorFooter: NSView {
    private let count = NSTextField(labelWithString: "")

    var label: String {
        get { count.stringValue }
        set { count.stringValue = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .tertiaryLabelColor
        count.lineBreakMode = .byTruncatingTail
        count.translatesAutoresizingMaskIntoConstraints = false
        addSubview(count)
        NSLayoutConstraint.activate([
            count.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            count.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
