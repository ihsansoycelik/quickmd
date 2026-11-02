import AppKit

/// The menu bar, built in code (there's no nib).
@MainActor
enum MainMenu {
    static func build(target app: AppDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu(app)))
        main.addItem(submenu(fileMenu(app)))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(formatMenu(app)))
        main.addItem(submenu(viewMenu(app)))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        help.addItem(item("QuickMD Help", #selector(QuickMDDocumentController.showHelp(_:)), "?",
                          target: NSDocumentController.shared))
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String, _ action: Selector?, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil, tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        item.tag = tag
        return item
    }

    private static func appMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "QuickMD")
        menu.addItem(item("About QuickMD", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ",", target: app))
        menu.addItem(item("Default App for Markdown", #selector(AppDelegate.makeDefault(_:)), target: app))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide QuickMD", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit QuickMD", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("New Tab", #selector(AppDelegate.newTab(_:)), "t", target: app))
        let starters = NSMenu(title: "New from Template")
        for starter in Starter.allCases {
            let entry = item(starter.displayName, #selector(QuickMDDocumentController.newDocumentFromTemplate(_:)),
                             target: NSDocumentController.shared)
            entry.representedObject = starter.rawValue
            entry.image = NSImage(systemSymbolName: starter.symbol, accessibilityDescription: nil)
            if starter == .blank { starters.addItem(entry); starters.addItem(.separator()) } else { starters.addItem(entry) }
        }
        menu.addItem(submenu(starters))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        // Open Recent is added after Open… by NSDocumentController itself.
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Revert To Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Export as HTML…", #selector(DocumentWindowController.exportHTML(_:)), "e", [.command, .shift]))
        menu.addItem(item("Export as PDF…", #selector(DocumentWindowController.exportPDF(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]))
        menu.addItem(item("Print…", #selector(DocumentWindowController.printRenderedDocument(_:)), "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Copy as HTML", #selector(DocumentWindowController.copyAsHTML(_:)), "c", [.command, .option]))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        let findAction = #selector(NSTextView.performFindPanelAction(_:))
        find.addItem(item("Find…", findAction, "f", tag: Int(NSFindPanelAction.showFindPanel.rawValue)))
        find.addItem(item("Find and Replace…", findAction, "f", [.command, .option], tag: Int(NSTextFinder.Action.showReplaceInterface.rawValue)))
        find.addItem(item("Find Next", findAction, "g", tag: Int(NSFindPanelAction.next.rawValue)))
        find.addItem(item("Find Previous", findAction, "g", [.command, .shift], tag: Int(NSFindPanelAction.previous.rawValue)))
        find.addItem(item("Use Selection for Find", findAction, "e", tag: Int(NSFindPanelAction.setFindString.rawValue)))
        find.addItem(item("Jump to Selection", #selector(NSResponder.centerSelectionInVisibleArea(_:)), "j"))
        menu.addItem(submenu(find))

        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"))
        spelling.addItem(item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"))
        spelling.addItem(item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))))
        menu.addItem(submenu(spelling))

        let substitutions = NSMenu(title: "Substitutions")
        substitutions.addItem(item("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))))
        substitutions.addItem(item("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:))))
        substitutions.addItem(item("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:))))
        menu.addItem(submenu(substitutions))
        return menu
    }

    private static func formatMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Format")
        menu.addItem(item("Bold", #selector(MarkdownTextView.toggleBold(_:)), "b"))
        menu.addItem(item("Italic", #selector(MarkdownTextView.toggleItalic(_:)), "i"))
        menu.addItem(item("Strikethrough", #selector(MarkdownTextView.toggleStrikethrough(_:)), "x", [.command, .shift]))
        menu.addItem(item("Inline Code", #selector(MarkdownTextView.toggleInlineCode(_:)), "c", [.command, .shift]))
        menu.addItem(item("Link", #selector(MarkdownTextView.insertLink(_:)), "k"))
        menu.addItem(.separator())
        for level in 1...4 {
            menu.addItem(item("Heading \(level)", #selector(MarkdownTextView.setHeading(_:)), "\(level)", [.command, .option], tag: level))
        }
        menu.addItem(item("Body Text", #selector(MarkdownTextView.setHeading(_:)), "0", [.command, .option], tag: 0))
        menu.addItem(.separator())
        menu.addItem(item("Bulleted List", #selector(MarkdownTextView.toggleBulletList(_:)), "l", [.command, .shift]))
        menu.addItem(item("Numbered List", #selector(MarkdownTextView.toggleNumberedList(_:)), "o", [.command, .shift]))
        menu.addItem(item("Task List", #selector(MarkdownTextView.toggleTaskList(_:)), "t", [.command, .shift]))
        menu.addItem(item("Mark Task Done", #selector(MarkdownTextView.toggleTaskDone(_:)), "\r"))
        menu.addItem(item("Quote", #selector(MarkdownTextView.toggleQuote(_:)), "'"))
        menu.addItem(item("Code Block", #selector(MarkdownTextView.insertCodeBlock(_:)), "c", [.command, .shift, .option]))
        menu.addItem(item("Horizontal Rule", #selector(MarkdownTextView.insertHorizontalRule(_:)), "-", [.command, .shift]))
        menu.addItem(item("Table", #selector(MarkdownTextView.insertTable(_:)), "t", [.command, .option]))
        let callouts = NSMenu(title: "Callout")
        for kind in CalloutKind.allCases {
            let entry = item(kind.title, #selector(MarkdownTextView.insertCallout(_:)))
            entry.representedObject = kind.rawValue
            callouts.addItem(entry)
        }
        menu.addItem(submenu(callouts))
        menu.addItem(item("Math Block", #selector(MarkdownTextView.insertMathBlock(_:)), "m", [.command, .option]))
        menu.addItem(item("Mermaid Diagram", #selector(MarkdownTextView.insertDiagram(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Indent", #selector(MarkdownTextView.indentLines(_:)), "]"))
        menu.addItem(item("Outdent", #selector(MarkdownTextView.outdentLines(_:)), "["))
        menu.addItem(.separator())

        let templates = NSMenu(title: "Style")
        for template in Template.allCases {
            let entry = item(template.displayName, #selector(AppDelegate.chooseTemplate(_:)), target: app)
            entry.representedObject = template.rawValue
            templates.addItem(entry)
        }
        menu.addItem(submenu(templates))
        let fonts = NSMenu(title: "Font")
        for face in FontFace.curated {
            let entry = item(face.displayName, #selector(AppDelegate.chooseFont(_:)), target: app)
            entry.representedObject = face.rawValue
            if let font = face.font(size: 13) { entry.attributedTitle = NSAttributedString(string: face.displayName, attributes: [.font: font]) }
            fonts.addItem(entry)
        }
        fonts.addItem(.separator())
        fonts.addItem(item("More Fonts and Size…", #selector(AppDelegate.showSettings(_:)), target: app))
        menu.addItem(submenu(fonts))
        return menu
    }

    private static func viewMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Edit Markdown", #selector(DocumentWindowController.toggleReadingMode(_:)), "p", [.command, .option]))
        menu.addItem(item("Show Sidebar", #selector(DocumentWindowController.toggleOutline(_:)), "s", [.command, .control]))
        menu.addItem(item("Footer", #selector(AppDelegate.toggleStatusBar(_:)), target: app))
        menu.addItem(item("Readable Line Width", #selector(AppDelegate.toggleReadableWidth(_:)), target: app))
        menu.addItem(.separator())
        menu.addItem(item("Bigger", #selector(AppDelegate.biggerText(_:)), "+", target: app))
        // ⌘= too: on many layouts, Turkish among them, + needs Shift.
        let bigger = item("Bigger", #selector(AppDelegate.biggerText(_:)), "=", target: app)
        bigger.isHidden = true
        bigger.allowsKeyEquivalentWhenHidden = true
        menu.addItem(bigger)
        menu.addItem(item("Smaller", #selector(AppDelegate.smallerText(_:)), "-", target: app))
        menu.addItem(item("Actual Size", #selector(AppDelegate.defaultTextSize(_:)), "0", target: app))
        menu.addItem(.separator())
        let themes = NSMenu(title: "Appearance")
        for theme in ThemePreference.allCases {
            let entry = item(theme.displayName, #selector(AppDelegate.chooseTheme(_:)), target: app)
            entry.representedObject = theme.rawValue
            themes.addItem(entry)
        }
        menu.addItem(submenu(themes))
        let glass = NSMenu(title: "Transparency")
        for level in Transparency.allCases {
            let entry = item(level.displayName, #selector(AppDelegate.chooseTransparency(_:)), target: app)
            entry.representedObject = level.rawValue
            glass.addItem(entry)
        }
        menu.addItem(submenu(glass))
        menu.addItem(.separator())
        menu.addItem(item("Hide Toolbar", #selector(NSWindow.toggleToolbarShown(_:))))
        menu.addItem(item("Customize Toolbar…", #selector(NSWindow.runToolbarCustomizationPalette(_:))))
        menu.addItem(item("Show Tab Bar", #selector(NSWindow.toggleTabBar(_:))))
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
