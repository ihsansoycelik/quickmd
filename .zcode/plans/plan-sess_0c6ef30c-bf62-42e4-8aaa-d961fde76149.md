## Bağlam

QuickMD'de belge penceresi şu an üç bölmeli: kenar çubuğu + editör + web önizleme (WKWebView). ⌘1/⌘2/⌘3 ile "Yalnız Editör / Yan Yana / Yalnız Önizleme" seçiliyor; göz düğmesi önizleme ↔ editör arasında geçiyor. Gönderdiğin ekran görüntüleri sayfanın *önizleme* görünümü; pencere içinde düzenlenebilir tek yüzey ise canlı stillenmiş editör. İstek: **tek görünüm** — bölme/sekmeli geçiş kalksın, kalan görünüm hem doğru-okunaklı gösterim hem düzenleme sağlasın.

Tek görünüm = mevcut hibrit editör (okuma modu): başlıklar, listeler, kod blokları, callout'lar, görev kutuları sayfa gibi gösterilir, imleç bulunduğun satırda ham markdown'ı ortaya çıkarır; her yerde yazılabilir. (Web görünümünü contenteditable yapıp WYSIWYG'e çevirmek "şu an için" hedefine göre çok büyük ve riskli bir yeniden yazım olur.)

## Değişiklikler

**1. Önizleme sistemi tamamen kaldırılıyor**
- `Sources/QuickMD/Preview.swift` → **sil** (`PreviewViewController`). `PreviewScheme` `SidePanes.swift`'te yaşıyor, kalır (PDF/HTML dışa aktarma, yazdırma ve `--render` hâlâ kullanıyor).
- `Sources/QuickMD/DocumentWindowController.swift`: `preview`/`previewItem`/`layout`/`modeButton`/`previewButton` alanları; `toggleReadingMode`, `updateModeButton`, `choosePaneLayout`, `togglePreview`, `setLayout`, `balancePanes` ve `showWindow`'daki yeniden-uygulama işleri; önizleme kabloları (`onScroll` senkronu, `outline.onSelect`'in önizleme dalı, `preview.onToggleTask/onReveal`, ayar gözlemcisinde `invalidateLook`) kaldırılır. Araç çubuğu: [Outline, ayraç, esnek boşluk, Format, Share] — Mod ve Önizleme düğmeleri yok. `windowDidBecomeKey` her zaman `editor.textView`'e odaklanır; belge her zaman editörde, hibrit okuma modunda açılır.
- `Sources/QuickMD/Settings.swift`: `paneLayout`, `PaneLayout` enum'u ve `showsProperties` (yalnızca önizlemede kullanılıyordu) silinir.
- `Sources/QuickMD/MainMenu.swift`: View menüsünden ⌘1/⌘2/⌘3 düzeni ve "Edit Markdown" (⌥⌘P) ile "Properties" (⇧⌘I) satırı kalkar; Sidebar, yazı tipi boyutu, görünüm vb. kalır.
- `Sources/QuickMD/AppDelegate.swift`: `toggleProperties` + doğrulama durumu kaldırılır.
- `Sources/QuickMD/SettingsWindow.swift`: "Preview / Show properties" satırı + notu + senkronu kaldırılır.
- `Sources/QuickMD/EditorViewController.swift`: `onScroll` geri çağrısı ve `textScrolled` (yalnızca önizleme senkronunaydı) kaldırılır; `topLine`/`line(at:)` başka yerde kullanılmıyorsa onlar da gider. **`isReading` özelliği kalır** (editörün kendi iç kipi; `EditorTests` yazma modunu test için kullanıyor) — arayüzden artık kimse çevirmiyor, görünüm her zaman hibrit okuma modunda.
- `Sources/QuickMD/Help.swift`: "Reading" bölümü güncellenir (⌥⌘P Reading Mode maddesi kalkar; "imlecin bulunduğu satırda markdown görünür" anlatılır).

**2. Editör gösterim düzeltmesi — tablolar (Sofia-Komutlar.md'deki ana sorun)**
- `Sources/QuickMD/MarkdownStyler.swift` `styleTableRow`: hücre ayraç `|` karakterleri şu an `.qmSyntax` alıp okuma modunda **gizleniyor**; dolgusuz ajan tablolarında sütunlar bitişik akıyor. Düzeltme: borular liste madde imiyle aynı mekanizmayla **görünür ama soluk** kalsın (`.foregroundColor: syntax` + `.qmKeepSyntax: true`). Ayraç satırı yine 1 px'e iner; satır çizgileri, başlık zemini ve panel çerçevesi `HorizontalRuleLayoutManager.drawBackground` (.qmTable) ile zaten çiziliyor.
- Bilinçli sınır: NSTextView'da sütunları dosyayı **değiştirmeden** hizalamak mümkün değil (hizalama ancak metne dolgu ekleyerek olur). Kaynak dosya düz markdown olarak korunur; uygulamanın kendi eklediği tablolar `TableEditing.format` ile zaten hizalı ekleniyor. Grid tablo çizimi sonraki bir tura bırakılır (yol haritasına not düşülür).

**3. Belgeleme**
- `audit/08-yol-haritasi.md`: "Tur 1"in canlı önizleme panosunun 2026-11-06'da kullanıcı kararıyla kaldırıldığı, tek görünüm = hibrit editör olduğu notlanır.

## Doğrulama
1. `swift test` — tüm testler (Renderer, Editor, LineMark, TextFile) geçmeli; tablo boruları için `.qmKeepSyntax` iddiasına küçük bir test eklenir.
2. `./scripts/build-app.sh --install` ile kur, Sofia-Komutlar.md'yi aç: tek görünüm, göz düğmesi/⌘1-2-3 yok, tablo satırları çizgili panelde borular soluk görünüyor, imleç satırda markdown düzenlenebilir, yazarken stiller canlı.
3. Yazdırma/PDF dışa aktarma hâlâ sayfa gibi çıkarıyor (RenderedPrinter bağımsız çalışıyor).

Not: Mermaid/KaTeX ekran içi gösterimi önizlemeyle birlikte kalkıyor (dosyadan dışa aktarmada hâlâ işliyor). İstersen sonra "grafik satır içi" olarak ayrıca ele alırız.