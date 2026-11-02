import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var appearanceObservation: NSKeyValueObservation?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The shared controller must exist before any file is opened.
        _ = QuickMDDocumentController()
        AppResources.registerFonts()
        FolderAccess.restore()
        NSApp.mainMenu = MainMenu.build(target: self)
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
                alert.messageText = "Couldn't make QuickMD the default"
                alert.informativeText = failure.localizedDescription
            } else {
                alert.messageText = "QuickMD now opens Markdown files"
                alert.informativeText = "Finder and Quick Look will offer “Open with QuickMD” for .md files."
            }
            alert.runModal()
        }
    }

    // MARK: Preferences

    @objc func chooseFont(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, !id.isEmpty { Settings.fontFace = FontFace(rawValue: id) }
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
        SettingsWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }

    /// ⌘T: a blank document, as a tab when tabs are on.
    @objc func newTab(_ sender: Any?) {
        (NSDocumentController.shared as? QuickMDDocumentController)?.newDocument(from: .blank)
    }

    @objc func chooseTemplate(_ sender: NSMenuItem) {
        if let template = Template(rawValue: sender.representedObject as? String ?? "") { Settings.template = template }
    }

    @objc func chooseTheme(_ sender: NSMenuItem) {
        if let theme = ThemePreference(rawValue: sender.representedObject as? String ?? "") { Settings.themePreference = theme }
    }

    @objc func chooseTransparency(_ sender: NSMenuItem) {
        if let level = Transparency(rawValue: sender.representedObject as? String ?? "") { Settings.transparency = level }
    }

    @objc func biggerText(_ sender: Any?) { Settings.fontSize += 1 }
    @objc func smallerText(_ sender: Any?) { Settings.fontSize -= 1 }
    @objc func defaultTextSize(_ sender: Any?) { Settings.fontSize = Settings.template.defaultSize }
    @objc func toggleReadableWidth(_ sender: Any?) { Settings.readableWidth.toggle() }
    @objc func toggleStatusBar(_ sender: Any?) { Settings.showsStatusBar.toggle() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(chooseFont(_:)):
            menuItem.state = Settings.fontFace.rawValue == menuItem.representedObject as? String ? .on : .off
        case #selector(chooseTemplate(_:)):
            menuItem.state = Settings.template.rawValue == menuItem.representedObject as? String ? .on : .off
        case #selector(chooseTheme(_:)):
            menuItem.state = Settings.themePreference.rawValue == menuItem.representedObject as? String ? .on : .off
        case #selector(chooseTransparency(_:)):
            menuItem.state = Settings.transparency.rawValue == menuItem.representedObject as? String ? .on : .off
        case #selector(toggleReadableWidth(_:)):
            menuItem.state = Settings.readableWidth ? .on : .off
        case #selector(toggleStatusBar(_:)):
            menuItem.state = Settings.showsStatusBar ? .on : .off
        case #selector(makeDefault(_:)):
            menuItem.state = isDefault ? .on : .off
        default:
            break
        }
        return true
    }
}
