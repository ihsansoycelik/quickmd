import AppKit

/// Menu items for the structure and editing commands (outline, folding,
/// heading levels, line moves, tasks, tables, highlight, contents),
/// kept apart from MainMenu so each menu gains them in one line.
@MainActor
enum StructureMenus {
    private static func key(_ code: Int) -> String { String(Character(UnicodeScalar(UInt32(code))!)) }
    private static let up = key(NSUpArrowFunctionKey), down = key(NSDownArrowFunctionKey)
    private static let left = key(NSLeftArrowFunctionKey), right = key(NSRightArrowFunctionKey)

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: L(title), action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: L(title))
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// Edit: after Select All and Find.
    static func edit() -> [NSMenuItem] {
        [.separator(), item("Copy Link to Heading", #selector(MarkdownTextView.copyLinkToHeading(_:)))]
    }

    /// Format: appended at the end.
    static func format() -> [NSMenuItem] {
        let t = #selector(MarkdownTextView.tableCommand(_:))
        func table(_ c: TableCommand) -> NSMenuItem { item(c.title, t, tag: c.rawValue) }
        return [
            .separator(),
            item("Highlight", #selector(MarkdownTextView.toggleHighlight(_:)), "h", [.command, .shift]),
            item("Promote Heading", #selector(MarkdownTextView.promoteHeading(_:)), up, [.command, .control]),
            item("Demote Heading", #selector(MarkdownTextView.demoteHeading(_:)), down, [.command, .control]),
            .separator(),
            item("Move Line Up", #selector(MarkdownTextView.moveLineUp(_:)), up, [.command, .option]),
            item("Move Line Down", #selector(MarkdownTextView.moveLineDown(_:)), down, [.command, .option]),
            item("Delete Line", #selector(MarkdownTextView.deleteLine(_:)), "k", [.command, .shift]),
            .separator(),
            item("Check Selected", #selector(MarkdownTextView.checkSelectedTasks(_:))),
            item("Uncheck Selected", #selector(MarkdownTextView.uncheckSelectedTasks(_:))),
            submenu("Table", [
                table(.addRowAbove), table(.addRowBelow), table(.addColumnBefore), table(.addColumnAfter), .separator(),
                table(.deleteRow), table(.deleteColumn), .separator(),
                table(.moveRowUp), table(.moveRowDown), table(.moveColumnLeft), table(.moveColumnRight), .separator(),
                table(.alignLeft), table(.alignCenter), table(.alignRight), .separator(),
                table(.tidy),
            ]),
            .separator(),
            item("Table of Contents", #selector(MarkdownTextView.insertTableOfContents(_:))),
            item("Front Matter", #selector(MarkdownTextView.insertFrontMatter(_:))),
        ]
    }

    /// View: before the tab bar items.
    static func view() -> [NSMenuItem] {
        [
            item("Go to Heading…", #selector(MarkdownTextView.goToHeading(_:)), "o", [.command, .control]),
            item("Fold Section", #selector(MarkdownTextView.foldSection(_:)), left, [.command, .option]),
            item("Unfold Section", #selector(MarkdownTextView.unfoldSection(_:)), right, [.command, .option]),
            item("Unfold All", #selector(MarkdownTextView.unfoldAll(_:))),
            .separator(),
        ]
    }
}
