import AppKit

/// Settings › Fade window controls while typing (after Lede): typing
/// fades the title bar, its buttons and the tab bar; moving the mouse
/// brings them back. With Reduce Motion they hide and show at once.
@MainActor
final class ChromeFader {
    private weak var window: NSWindow?
    private var observers: [Any] = []
    private var mouseMonitor: Any?
    private(set) var isFaded = false

    init(window: NSWindow, textView: NSTextView) {
        self.window = window
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.typed() }
            },
            center.addObserver(forName: .editorSettingsChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applySetting() }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.show() }
            },
        ]
        applySetting()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }

    /// The title bar's container: title, window buttons and the tab bar.
    private var chrome: NSView? { window?.standardWindowButton(.closeButton)?.superview?.superview }

    private func applySetting() {
        if Settings.fadesChrome {
            window?.acceptsMouseMovedEvents = true
            if mouseMonitor == nil {
                mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .scrollWheel]) { [weak self] event in
                    MainActor.assumeIsolated {
                        if let self, event.window === self.window, self.isFaded,
                           event.type != .mouseMoved || abs(event.deltaX) + abs(event.deltaY) > 1 {
                            self.show()
                        }
                    }
                    return event
                }
            }
        } else {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            mouseMonitor = nil
            show()
        }
    }

    private func typed() {
        guard Settings.fadesChrome, let window, window.isKeyWindow, !window.styleMask.contains(.fullScreen), !isFaded else { return }
        set(alpha: 0)
        isFaded = true
    }

    func show() {
        guard isFaded else { return }
        isFaded = false
        set(alpha: 1)
    }

    private func set(alpha: CGFloat) {
        guard let chrome else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            chrome.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            // Leaving is slower than coming back.
            context.duration = alpha == 0 ? 0.3 : 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            chrome.animator().alphaValue = alpha
        }
    }
}
