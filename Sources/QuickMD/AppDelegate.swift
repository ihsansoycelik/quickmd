import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var appearanceObservation: NSKeyValueObservation?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The shared controller must exist before any file is opened.
        _ = QuickMDDocumentController()
        FolderAccess.restore()
        NSApp.mainMenu = MainMenu.build(target: self)
        NSApp.servicesProvider = self
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
        #if !APPSTORE
        // Set by scripts/build-app.sh --install; the App Store build only does it from the menu.
        if CommandLine.arguments.contains("--make-default") {
            makeDefault(nil)
        }
        #endif
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
        if !flag { NSDocumentController.shared.newDocument(nil) }
        return true
    }

    // MARK: Default app

    static let markdownTypes = ["net.daringfireball.markdown"]

    private var isDefault: Bool {
        guard let type = UTType("net.daringfireball.markdown"),
              let current = NSWorkspace.shared.urlForApplication(toOpen: type) else { return false }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// Makes QuickMD the app Finder and Quick Look offer for .md files.
    @objc func makeDefault(_ sender: Any?) {
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

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(chooseTheme(_:)):
            menuItem.state = Settings.themePreference.rawValue == menuItem.representedObject as? String ? .on : .off
        case #selector(makeDefault(_:)):
            menuItem.state = isDefault ? .on : .off
        default:
            break
        }
        return true
    }
}
