import AppKit

/// What VoiceOver hears for the things the editor draws instead of
/// text: task boxes, grid tables and inline pictures. The text view
/// still reads its plain Markdown; these are extra children on top,
/// so a box can be found, read and ticked like a real checkbox.
enum DrawnBlocks {
    enum Kind: Equatable {
        case checkbox(checked: Bool, label: String)
        case table(rows: Int, columns: Int, summary: String)
        case image(label: String)
    }

    struct Item: Equatable {
        var kind: Kind
        /// The characters it stands for (the box, the whole table, the image line).
        var range: NSRange
    }

    /// The drawn blocks in `range` of `storage`. Tables and images are
    /// listed only when `rendered` says they're drawn (not as source).
    static func items(
        in storage: NSAttributedString, range: NSRange,
        tableIsRendered: (NSRange) -> Bool = { _ in true },
        imageIsRendered: (NSRange) -> Bool = { _ in true }
    ) -> [Item] {
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: storage.length)
        let range = NSIntersectionRange(range, full)
        var items: [Item] = []

        storage.enumerateAttribute(.qmCheckbox, in: range) { value, box, _ in
            guard let checked = value as? Bool else { return }
            let line = HorizontalRuleLayoutManager.lineContent(ns.lineRange(for: box), in: ns)
            let after = NSMaxRange(box)
            let rest = after < NSMaxRange(line) ? ns.substring(with: NSRange(location: after, length: NSMaxRange(line) - after)) : ""
            items.append(Item(kind: .checkbox(checked: checked, label: rest.trimmingCharacters(in: .whitespaces)), range: box))
        }

        var seen = Set<Int>()
        storage.enumerateAttribute(.qmTable, in: range) { value, at, _ in
            guard value != nil else { return }
            var block = NSRange()
            _ = storage.attribute(.qmTable, at: at.location, longestEffectiveRange: &block, in: full)
            guard seen.insert(block.location).inserted, tableIsRendered(block),
                  let table = table(block, in: ns) else { return }
            items.append(Item(kind: table, range: block))
        }

        storage.enumerateAttribute(.qmImage, in: range) { value, at, _ in
            guard let target = value as? String else { return }
            var line = NSRange()
            _ = storage.attribute(.qmImage, at: at.location, longestEffectiveRange: &line, in: full)
            guard seen.insert(line.location).inserted, imageIsRendered(line) else { return }
            let text = ns.substring(with: line)
            items.append(Item(kind: .image(label: imageLabel(text, target: target)), range: line))
        }
        return items.sorted { $0.range.location < $1.range.location }
    }

    /// "Table, 3 rows, 2 columns" plus the cells, row by row.
    static func table(_ block: NSRange, in ns: NSString) -> Kind? {
        var rows: [[String]] = []
        var location = block.location
        var hasDelimiter = false
        while location < NSMaxRange(block) {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let content = HorizontalRuleLayoutManager.lineContent(line, in: ns)
            let text = ns.substring(with: content)
            if TableEditing.isDelimiter(text) {
                hasDelimiter = true
            } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                rows.append(TableGrid.cellRanges(content, in: ns).map { ns.substring(with: $0) })
            }
            location = NSMaxRange(line)
        }
        guard hasDelimiter, !rows.isEmpty else { return nil }
        let columns = rows.map(\.count).max() ?? 0
        let summary = rows.map { $0.joined(separator: ", ") }.joined(separator: ". ")
        return .table(rows: rows.count, columns: columns, summary: summary)
    }

    /// The alt text of `![alt](target)`, else the file's name.
    static func imageLabel(_ line: String, target: String) -> String {
        if let open = line.range(of: "!["), let close = line.range(of: "](", range: open.upperBound..<line.endIndex) {
            let alt = line[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if !alt.isEmpty { return alt }
        }
        let name = (target.removingPercentEncoding ?? target) as NSString
        return name.lastPathComponent.isEmpty ? L("Image") : name.lastPathComponent
    }
}

/// A task box VoiceOver can tick (VO-Space).
final class TaskBoxElement: NSAccessibilityElement {
    var toggle: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        toggle?()
        return toggle != nil
    }
}

extension MarkdownTextView {
    /// The drawn blocks on screen, as accessibility elements.
    func drawnBlockElements() -> [NSAccessibilityElement] {
        guard let manager = layoutManager as? HorizontalRuleLayoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return [] }
        let visible = visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let items = DrawnBlocks.items(
            in: storage, range: chars,
            tableIsRendered: { manager.renderedTable(at: $0.location) == $0 },
            imageIsRendered: { manager.renderedImage(at: $0.location) != nil }
        )
        return items.compactMap { item in
            let glyphRange = manager.glyphRange(forCharacterRange: item.range, actualCharacterRange: nil)
            var rect = manager.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += textContainerOrigin.x
            rect.origin.y += textContainerOrigin.y
            let element: NSAccessibilityElement
            switch item.kind {
            case let .checkbox(checked, label):
                let box = TaskBoxElement()
                box.setAccessibilityRole(.checkBox)
                box.setAccessibilityLabel(label.isEmpty ? L("Task") : label)
                box.setAccessibilityValue(checked ? 1 : 0)
                let location = item.range.location
                box.toggle = { [weak self] in self?.toggleCheckbox(at: location) }
                element = box
            case let .table(rows, columns, summary):
                if let (grid, origin) = manager.gridFrame(for: item.range) {
                    rect = CGRect(x: origin.x + textContainerOrigin.x, y: origin.y + textContainerOrigin.y,
                                  width: grid.width, height: grid.height)
                }
                element = NSAccessibilityElement()
                element.setAccessibilityRole(.group)
                element.setAccessibilityRoleDescription(L("table"))
                element.setAccessibilityLabel(String(format: L("Table, %d rows, %d columns"), rows, columns))
                element.setAccessibilityValue(summary)
            case let .image(label):
                element = NSAccessibilityElement()
                element.setAccessibilityRole(.image)
                element.setAccessibilityLabel(label)
            }
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(rect)
            return element
        }
    }

    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + drawnBlockElements()
    }
}
