import AppKit
import Testing
@testable import QuickMD

/// Renders the editor offscreen in the one design, light and dark,
/// to PNGs for a visual check. Runs only when QM_SNAPSHOT names a folder.
@MainActor
struct SnapshotTests {
    static let sample = """
    # Yol haritası

    Tek görünüm kararı korunuyor. Önizleme yalnızca dışa aktarmada yaşıyor; editör okuma modunda açılıyor ve imlecin olduğu satır Markdown'ı gösteriyor.

    ## Tur 2: Görünüm

    - Tek sütun, tek font; uzun satırlar sütun genişliğinde kırılır ve fazla genişlik kenar boşluğu olur.
    - Durum satırı: kelime, satır:sütun, kayıt.
      - İç içe madde bir adım içeride.
    - [ ] Odak modu
    - [x] Tek tasarım

    > Yapı kenara, kelimeler sayfaya. Alıntı da kendi işaretini kenarda taşır.

    > [!NOTE]
    > Callout türü başlığında okunur; renk yok, ince çerçeve var.

    1. Kâğıt zemin
    2. Tek vurgu rengi

    ### Bileşenler

    | Bileşen | Tür |
    |---|---|
    | Metin sütunu | Sabit |
    | Kenar sütunu | Sabit |

    ```swift
    let column = Design.columnWidth(size: 16)
    ```

    ---

    Son paragraf **kalın**, *italik* ve `satır içi kod` ile.
    """

    @Test func render() throws {
        guard let folder = ProcessInfo.processInfo.environment["QM_SNAPSHOT"] else { return }
        let previous = Settings.themePreference
        defer { Settings.themePreference = previous }
        for preference in [ThemePreference.light, .dark] {
            Settings.themePreference = preference
            let theme = preference.resolve()
            let controller = EditorViewController()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1150), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: theme.appearanceName)
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 1000, height: 1150))
            controller.load(Self.sample)
            // Caret on the "Tur 2" heading, so one line shows its source.
            let caret = (Self.sample as NSString).range(of: "Tur 2").location
            controller.textView.setSelectedRange(NSRange(location: caret, length: 0))
            controller.view.layoutSubtreeIfNeeded()
            controller.textView.layoutManager?.ensureLayout(for: controller.textView.textContainer!)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))

            let view = window.contentView!
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: view.bounds.size)
            image.lockFocus()
            Palette.for(theme).background.setFill()
            view.bounds.fill()
            let layer = NSImage(size: view.bounds.size)
            layer.addRepresentation(rep)
            layer.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1)
            image.unlockFocus()
            let tiff = try #require(image.tiffRepresentation)
            let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("editor-\(preference.rawValue).png"))
        }
    }
}
