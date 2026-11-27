import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var appearanceObservation: NSKeyValueObservation?
    private var settingsObserver: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The shared controller must exist before any file is opened.
        _ = QuickMDDocumentController()
        FolderAccess.restore()
        NSApp.mainMenu = MainMenu.build(target: self)
        NSApp.servicesProvider = self
        Settings.applicationAppearanceUpdater = { [weak self] in self?.applyApplicationAppearance() }
        applyApplicationAppearance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // "System" follows macOS when it switches between light and dark.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            DispatchQueue.main.async {
                guard Settings.themePreference == .system else { return }
                NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
            }
        }
        // Increase Contrast picks a different fixed appearance (Theme.appearanceName).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { _ in NotificationCenter.default.post(name: .editorSettingsChanged, object: nil) }
        // Menus, panels and controls use the app's appearance too, so a
        // forced Light/Dark never leaves a system-drawn control behind.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .editorSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.applyApplicationAppearance() } }
        #if !APPSTORE
        // Set by scripts/build-app.sh --install; the App Store build only does it from the menu.
        if CommandLine.arguments.contains("--make-default") {
            makeDefault(nil)
        }
        #endif
    }

    /// App-wide appearance: a fixed Light/Dark choice reaches menus and
    /// panels; System leaves AppKit following macOS.
    private func applyApplicationAppearance() {
        let wanted = Settings.themePreference == .system
            ? nil : NSAppearance(named: Settings.theme.appearanceName)
        guard NSApp.appearance?.name != wanted?.name else { return }
        NSApp.appearance = wanted
    }

    // MARK: Services

    /// Services › New QuickMD Note With Selection, from any app.
    @objc func newNoteWithSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = L("No text was selected.") as NSString
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        (NSDocumentController.shared as? QuickMDDocumentController)?.newDocument(text: normalized)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Clicking the Dock icon after minimizing should bring the note
        // back, not create another blank one. Settings alone being open
        // doesn't count as a visible document.
        let miniaturized = NSApp.windows.filter { $0.isMiniaturized }
        if !miniaturized.isEmpty {
            miniaturized.forEach { $0.deminiaturize(nil) }
            miniaturized.first?.makeKeyAndOrderFront(nil)
            return true
        }
        guard !flag else { return true }
        if let document = NSDocumentController.shared.documents.first {
            document.showWindows()
        } else {
            NSDocumentController.shared.newDocument(nil)
        }
        return true
    }

    // MARK: Default app

    static let markdownTypes = ["net.daringfireball.markdown"]

    static var isDefaultApp: Bool {
        guard let type = UTType("net.daringfireball.markdown"),
              let current = NSWorkspace.shared.urlForApplication(toOpen: type) else { return false }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// Makes QuickMD the app Finder and Quick Look offer for .md files.
    @objc func makeDefault(_ sender: Any?) {
        if Self.isDefaultApp {
            guard sender != nil else { return }
            let alert = NSAlert()
            alert.messageText = L("QuickMD already opens Markdown files")
            alert.informativeText = L("Finder and Quick Look offer “Open with QuickMD” for .md files.")
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
            return
        }
        let types = Self.markdownTypes.compactMap { UTType($0) }
        let group = DispatchGroup()
        var failure: Error?
        for type in types {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
                if let error { failure = error }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            // The Settings pane refreshes its button from this state.
            NotificationCenter.default.post(name: .editorSettingsChanged, object: nil)
            guard sender != nil else { return }
            let alert = NSAlert()
            if let failure {
                alert.messageText = L("Couldn’t make QuickMD the default")
                alert.informativeText = failure.localizedDescription
            } else {
                alert.messageText = L("QuickMD now opens Markdown files")
                alert.informativeText = L("Finder and Quick Look will offer “Open with QuickMD” for .md files.")
            }
            alert.runModal()
        }
    }

    // MARK: Preferences

    @objc func reportIssue(_ sender: Any?) {
        NSWorkspace.shared.open(Help.supportURL)
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
        SettingsWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }

    /// ⌘T: a blank document, as a tab when tabs are on.
    @objc func newTab(_ sender: Any?) {
        (NSDocumentController.shared as? QuickMDDocumentController)?.newDocument(from: .blank)
    }

    @objc func chooseTheme(_ sender: NSMenuItem) {
        if let theme = ThemePreference(rawValue: sender.representedObject as? String ?? "") { Settings.themePreference = theme }
    }

    @objc func biggerText(_ sender: Any?) { Settings.fontSize += 1 }
    @objc func smallerText(_ sender: Any?) { Settings.fontSize -= 1 }
    @objc func defaultTextSize(_ sender: Any?) { Settings.fontSize = Design.defaultSize }

    @objc func toggleWordCount(_ sender: Any?) { Settings.showsWordCount.toggle() }
    @objc func toggleFormattingBar(_ sender: Any?) { Settings.showsFormattingBar.toggle() }
    @objc func togglePaper(_ sender: Any?) { Settings.paperBackground.toggle() }
    @objc func toggleMarkdownSyntax(_ sender: Any?) { Settings.showsSyntax.toggle() }
    @objc func toggleFocusMode(_ sender: Any?) { Settings.focusMode.toggle() }
    @objc func toggleTypewriterMode(_ sender: Any?) { Settings.typewriterMode.toggle() }
    @objc func toggleFileSidebar(_ sender: Any?) { Settings.showsSidebar.toggle() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(chooseTheme(_:)):
            menuItem.state = Settings.themePreference.rawValue == menuItem.representedObject as? String ? .on : .off
        case #selector(toggleWordCount(_:)): menuItem.state = Settings.showsWordCount ? .on : .off
        case #selector(toggleFormattingBar(_:)): menuItem.state = Settings.showsFormattingBar ? .on : .off
        case #selector(togglePaper(_:)): menuItem.state = Settings.paperBackground ? .on : .off
        case #selector(toggleMarkdownSyntax(_:)): menuItem.state = Settings.showsSyntax ? .on : .off
        case #selector(toggleFocusMode(_:)): menuItem.state = Settings.focusMode ? .on : .off
        case #selector(toggleTypewriterMode(_:)): menuItem.state = Settings.typewriterMode ? .on : .off
        case #selector(toggleFileSidebar(_:)): menuItem.title = Settings.showsSidebar ? L("Hide Sidebar") : L("Show Sidebar")
        default:
            break
        }
        return true
    }
}
