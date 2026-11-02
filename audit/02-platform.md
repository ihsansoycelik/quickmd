# 02 — macOS Platform Entegrasyonu, HIG, Erişilebilirlik ve Yerelleştirme Denetimi

**Repo:** `/Users/ihsan/Desktop/macOS_Dev/quickmd` · **Kaynak:** çalışma ağacı — git HEAD `9803cde` (2026-10-31) **+ commit edilmemiş değişiklikler** (20 dosya, +2595/−438 satır; `git status` 31 kayıt). Bu rapordaki tüm satır numaraları çalışma ağacındaki dosyalara aittir.
**Denetlenen build:** `build/QuickMD.app` (CFBundleShortVersionString 1.0.0, CFBundleVersion 3), bu çalışma ağacından 13:01'de derlendi.
**Ortam:** macOS 15.7.9 (24G830), sistem dili **Türkçe**, klavye **Turkish-QWERTY-PC**, ekran 1440×900 @2×.
**Yöntem:** Salt-okunur kod incelemesi + uygulamayı gerçekten derleyip çalıştırma. Menü çubuğu System Events/AX ile döküldü, pencereler `screencapture -l <windowID>` ile tek tek görüntülendi, kısayollar gerçek klavye olaylarıyla denendi, kalıcılık `defaults read com.ursula.quickmd` ile doğrulandı.
**Kural:** Kaynak kod değiştirilmedi; yalnızca bu dosya yazıldı.

---

## 0. Yönetici özeti

QuickMD'nin menü çubuğu, Apple'ın kendi uygulamalarına **şablon olarak yakın**: uygulama menüsü tam (About / Settings… ⌘, / Services / Hide / Hide Others / Quit), Window menüsü `NSApp.windowsMenu`'ye bağlı olduğu için AppKit'in standart öğelerini (Minimize ⌘M, Zoom, Bring All to Front, sekme öğeleri) otomatik alıyor, Edit menüsü first-responder selector'larını doğru kullanıyor, toolbar birleşik (unified) ve özelleştirilebilir, sekmeler çalışıyor, Share ve Find bar doğru kurulmuş. `⌘,` Settings'i açıyor; Find and Replace (⌥⌘F) gerçekten Replace alanıyla açılıyor (test edildi).

Buna karşılık "Apple'ın kendi uygulaması" hissini bozan üç yapısal boşluk var:

1. **Help menüsü tamamen boş** (0 öğe). Yardım kitabı (help book) yok, yardım araması yok.
2. **Yerelleştirme altyapısı hiç yok**: `.lproj`/`.strings`/`.xcstrings` yok, `String(localized:)` yok, `CFBundleLocalizations` yok; ~146 kullanıcı metni kod içinde İngilizce sabit. Türkçe sistemde menü çubuğu tamamen İngilizce (Apple menüsü Türkçe: "Bu Mac Hakkında…", "Sistem Ayarları…").
3. **Erişilebilirlik yalnızca AppKit'in bedava verdikleri kadar**: `setAccessibilityLabel`/rol tanımı yok, özel çizilen onay kutuları ve footer tıklaması VoiceOver/klavye dışı, `Increase Contrast` görünümü pencere düzeyinde **zorla iptal ediliyor**, `Reduce Motion`/`Reduce Transparency` hiç okunmuyor.

Ayrıca Quick Look önizleme eklentisi, Spotlight indeksleme, App Intents/Shortcuts, Services sağlama ve Dock menüsü yok; durum geri yükleme (state restoration) için tek satır kod yok.

**Dağılım:** 4 High · 8 Medium · 8 Low. Blocker yok — uygulama çalışıyor ve günlük kullanımda sağlam; eksikler "platform vatandaşlığı" katmanında.

---

## 1. Kanıtların toplanma biçimi (tekrarlanabilir)

```sh
./scripts/build-app.sh                 # build/QuickMD.app (13:01, bu çalışma ağacından)
build/QuickMD.app/Contents/MacOS/QuickMD &   # doğrudan çalıştır (LaunchServices'in /Applications kopyasına
                                             #  yönlendirmemesi için; bkz. §12 not)
# Menü dökümü: System Events + AX (AXMenuItemCmdChar / AXMenuItemCmdModifiers / enabled)
osascript -e 'tell application "System Events" to tell process "QuickMD" to get name of every menu bar item of menu bar 1'
osascript  # menü öğeleri + alt menüler + kısayol karakterleri (Ek A)
screencapture -l <CGWindowID> -x -o out.png   # pencere bazlı görüntü (CGWindowList ile ID)
defaults read com.ursula.quickmd
```

Ölçülen/karşılaştırılan pencere görüntüleri: belge penceresi (sekmeli, toolbar: sidebar / Format "Aa" / göz / Share, footer "5 words"), Settings penceresi (Appearance sekmesi), Find bar + Replace alanı.

---

## 2. Bulgu tablosu

| ID | Önem | Alan | Bulgu |
|---|---|---|---|
| P-01 | **High** | Menü | Help menüsü tamamen boş; help book ve yardım araması yok |
| P-02 | **High** | Yerelleştirme | Sıfır yerelleştirme altyapısı; tüm UI metinleri kod içinde İngilizce |
| P-03 | **High** | Erişilebilirlik | AX etiketi/rolü yok; özel çizilen onay kutuları ve footer AX/klavye dışı |
| P-04 | **High** | Erişilebilirlik | Increase Contrast / Reduce Motion / Reduce Transparency hiç okunmuyor; görünüm adı sabitlenerek yüksek kontrast iptal ediliyor |
| P-05 | Medium | Pencere | Durum geri yükleme (state restoration) yok / doğrulanamadı |
| P-06 | Medium | Menü | File ▸ Open Recent iki kez görünüyor; ikincisi hiç dolmuyor |
| P-07 | Medium | Settings | Örnek metin ham markdown gösteriyor; sabit 520 pt genişlik; General yerine Appearance'ta açılıyor |
| P-08 | Medium | Menü | Show/Hide Sidebar (⌃⌘S) ve Show/Hide Toolbar (⌥⌘T) yok; Format ▸ Table ⌥⌘T ile çakışıyor |
| P-09 | Medium | Pencere | Belge proxy ikonu gizlenmiş (sürükle / ⌘-tık yol menüsü kayboluyor) |
| P-10 | Medium | Sistem | Quick Look önizleme eklentisi yok → Space ile ham markdown görünüyor |
| P-11 | Medium | Sistem | Spotlight, App Intents/Shortcuts, Services sağlama, Dock menüsü, Handoff, AppleScript sözlüğü yok |
| P-12 | Medium | Klavye | View ▸ Bigger (⌘+) Türkçe klavyede ⇧⌘4 (sistem ekran görüntüsü) ile çakışıyor; ⌘= alternatifi yok |
| P-13 | Low | Erişilebilirlik | Footer istatistiği yalnızca fare ile (NSClickGestureRecognizer), AX rolü/kısayolu yok |
| P-14 | Low | Menü | "Save…" elipsisli; Save As yok, Export as PDF kısayolsuz, New / New Tab ikiliği |
| P-15 | Low | Menü | "Default App for Markdown" uygulama menüsünde (HIG: Settings'e ait; Settings'te zaten var) |
| P-16 | Low | Menü | Undo/Redo string selector; Copy as HTML ⌥⌘C sistem "Copy Style" ile çakışıyor |
| P-17 | Low | Yazdırma | `MarkdownDocument.printOperation` ham metni yazdırıyor, File ▸ Print ise render edilmiş sayfayı → iki farklı çıktı |
| P-18 | Low | Bilgi | Window menüsü elle 3 öğe + AppKit'in ekledikleri (macOS 15 Fill/Center/Move & Resize…); elle "Show Tab Bar" AppKit'in "Show All Tabs"ı ile kavramsal tekrar |
| P-19 | Low | Tam ekran | Full screen için pencere delegesi kancası yok; opak olmayan özel cam + full screen riski doğrulanmadı |
| P-20 | Low | Güncelleme | "Check for Updates…" / güncelleme kanalı yok (paketleme denetimiyle ortak) |

---

## 3. Menü çubuğu

### P-01 — Help menüsü tamamen boş · **High**

**Kanıt**
- `Sources/QuickMD/MainMenu.swift:16-18`: `let help = NSMenu(title: "Help"); main.addItem(submenu(help)); NSApp.helpMenu = help` — menü oluşturuluyor, **hiç öğe eklenmiyor**.
- AX dökümü: `=== Help ===` ve ardından **hiçbir öğe yok** (Ek A). `NSHelpManager` kullanımı: 0 (grep).
- Bundle'da help book yok: `find build/QuickMD.app \( -name '*.help' -o -name '*.lproj' \)` → boş. `Info.plist`'te `CFBundleHelpBookName`/`CFBundleHelpBookFolder` yok (`scripts/build-app.sh:61-119`).
- Görsel: menü çubuğunda son menü açıldığında boş açılan tek menü Help.

**Neden önemli**
HIG: her uygulamanın Help menüsü vardır; macOS yardım araması (Help ▸ arama alanı, ⌘?) Help menüsüne AppKit tarafından eklenir **ancak** kayıtlı bir help book varsa. Şu hâliyle kullanıcı ⌘? ile hiçbir şey bulamaz; "tamamlanmamış uygulama" izleniminin en görünür kaynağı budur. Ayrıca README/uygulama içi metinler (README "Opens .md files…", `AppDelegate.swift:71`) kullanıcıyı zaten desteklenmeyen yollara işaret ediyor (bkz. P-10).

**Somut düzeltme**
- `Resources/QuickMD.help/Contents/Resources/en.lproj/` altında en az 3 sayfalık help book (index, editing, preview/export); `Info.plist`'e `CFBundleHelpBookName = com.ursula.quickmd.help` ve (paket kökünde `.help` klasörü için) `CFBundleHelpBookFolder` ekle; `scripts/build-app.sh:56` satırındaki kopyalama listesine `Resources/QuickMD.help`'i ekle.
- `MainMenu.swift`'e öğeler: `"QuickMD Help"` (⌘?) → `NSHelpManager.shared.openHelpBook`; `"What's New"`, `"Release Notes"`, `"Report an Issue…"` (⌘ ile GitHub issue URL'i `NSWorkspace.shared.open`).
- Help menüsüne elle arama alanı koyma — AppKit ekler; doğrulama: AX ile Help menüsünde `AXMenuItemCmdChar` = "?" ve arama alanı görünmeli.

---

### P-06 — File ▸ Open Recent iki kez görünüyor, ikincisi boş · **Medium**

**Kanıt**
- AX dökümü (gözlem iki farklı QuickMD build'inde de tekrar etti):
  `Open Recent #1: [restore-probe.md] [note.md] [—] [Clear Menu]`
  `Open Recent #2: [Clear Menu]`
- Kaynak: `MainMenu.swift:72-75` elle bir `NSMenu(title: "Open Recent")` ekliyor ve içine `Clear Menu` koyuyor; yorumda "NSDocumentController finds this menu by its Clear Menu item and fills it" deniyor.
- Sonuç: NSDocumentController **ilkini** dolduruyor; AppKit'in eklediği/ikinci kopya hiç dolmuyor, sadece `Clear Menu` gösteriyor.

**Neden önemli**
Menüde aynı adlı iki öğe, biri sürekli boş: kullanıcı yanlış olana tıklayıp "neden geçmiş yok" diye düşünüyor; iki `Clear Menu` de "Temizle" beklentisini bozuyor. Apple uygulamalarında tek ve dolu bir Open Recent vardır.

**Somut düzeltme**
- `MainMenu.swift:72-75`'i kaldır ve Open Recent'i NSDocumentController'ın kurmasına bırak (File menüsünde hiç yoksa kendi ekler), **veya** kurulumdan sonra tek öğe kaldığından emin ol: menüde `title == "Open Recent"` olan ikinci öğeyi bulup `main.removeItem(_:)`.
- Kabul kriteri (AX ile): `count of (menu items of File where name == "Open Recent") == 1` ve dosya açtıktan sonra içinde en az bir dosya.

---

### P-08 — Show/Hide Sidebar ve Show/Hide Toolbar yok; ⌥⌘T çakışması · **Medium**

**Kanıt**
- `MainMenu.swift:185-214` (View menüsü): `Show Preview ⌥⌘P`, `Show Outline ⌥⌘O`, `Footer`, `Readable Line Width`, `Bigger/Smaller/Actual Size`, `Appearance`, `Transparency`, `Customize Toolbar…`, `Show Tab Bar`, `Enter Full Screen ⌃⌘F`. **`Show/Hide Sidebar` ve `Show/Hide Toolbar` yok** (grep: `toggleSidebar` 0, `toggleToolbar` 0).
- `MainMenu.swift:150`: `Table` = **⌥⌘T**; bu, HIG'in standart "Show/Hide Toolbar" kısayoludur.
- `MainMenu.swift:212`: elle `Show Tab Bar` eklenmiş; oysa AppKit aynı menüye `Show All Tabs ⌥⌘,` öğesini kendisi ekliyor (AX dökümünde View menüsünün ilk öğesi) → iki farklı "sekme çubuğu" kavramı.

**Neden önemli**
Sidebar'ı olan bir uygulamada ⌃⌘S standarttır (Finder, Mail, Notes, Xcode). Toolbar'ı olan uygulamada ⌥⌘T standarttır. Kullanıcının parmak hafızası bunları arar; Table'ın ⌥⌘T'yi alması ileride toolbar düğmesi eklendiğinde çakışma üretir.

**Somut düzeltme**
- View menüsüne: `Show Sidebar` (⌃⌘S, action `NSSplitViewController.toggleSidebar(_:)`; `MainMenu.swift:211`'den önce) ve `Hide/Show Toolbar` (⌥⌘T, action `NSWindow.toggleToolbarShown(_:)`).
- `Table` kısayolunu ⌥⌘⇧T veya ⌃⌘T yap (HIG'de serbest).
- Elle eklenen `Show Tab Bar` öğesini kaldır; sekme çubuğu görünürlüğü zaten AppKit'in `Show All Tabs`/otomatik tab bar davranışıyla yönetiliyor (ve `Settings.opensInTabs` ile).
- Doğrulama: AX dökümünde View menüsünde tek `Show Tab Bar` benzeri öğe ve ⌥⌘T = Show/Hide Toolbar.

---

### P-14 — "Save…" elipsisli; Save As yok, Export as PDF kısayolsuz, New/New Tab ikiliği · **Low**

**Kanıt**
- `MainMenu.swift:78`: `item("Save…", #selector(NSDocument.save(_:)), "s")` → menüde "Save…" (AX dökümünde de `Save… [S / mods 0]`). HIG: kaydetme her zaman iletişim kutusu açmıyorsa **"Save"** (elipsis yok); autosave kullanan bu uygulamada yol belli olduğunda kutu da açılmıyor.
- `Save As…` (⌥⇧⌘S) yok; `Duplicate ⇧⌘S` var (doğru).
- `Export as PDF…` (satır 85) kısayolsuz, `Export as HTML…` ⇧⌘E.
- `New ⌘N` (satır 60, `Settings.newDocumentStarter`) ve `New Tab ⌘T` (satır 61, her zaman `.blank`) neredeyse aynı işi yapıyor; ikisi de "yeni belge" vaat ediyor.

**Neden önemli**
Elipsis, "bu komut soru soracak" demektir; Apple uygulamalarında "Save" elipsissizdir. New/New Tab ikiliği ise Notes/Safari'de olmayan bir belirsizlik: kullanıcı hangisinin şablonu kullanacağını bilemez.

**Somut düzeltme**
- `"Save…"` → `"Save"`; isteğe bağlı `Save As…` ⌥⇧⌘S (`NSDocument.saveAs(_:)`).
- New Tab'i kaldır veya ⌘T'yi "New (Tab)" olarak tek komuta indir; şablon seçimi Settings'teki "New document" + File ▸ New from Template'te zaten var.

---

### P-15 — "Default App for Markdown" uygulama menüsünde · **Low**

**Kanıt**
- `MainMenu.swift:44`: `item("Default App for Markdown", #selector(AppDelegate.makeDefault(_:)), target: app)` — uygulama menüsünde, Settings'in hemen altında.
- Aynı işlev Settings'te de var: `SettingsWindow.swift:179` "Make Default for .md" düğmesi (çift kaynak).

**Neden önemli**
HIG uygulama menüsü: About / Settings… / Services / Hide / Hide Others / Show All / Quit. Tercih niteliğindeki öğeler Settings'e girer; menüde çift bulunması bakım yükü ve tutarsızlık üretir.

**Somut düzeltme**
- Menü öğesini kaldır (Settings'teki düğme kalsın) **veya** menüde kalsın ama Settings'ten kaldırılıp "Preferences" mantığı korunsun; ikisinde birden tutma.

---

### P-16 — Undo/Redo string selector; Copy as HTML ⌥⌘C çakışması · **Low**

**Kanıt**
- `MainMenu.swift:94-95`: `Selector(("undo:"))` / `Selector(("redo:"))` — derleyici denetimi yok; yazım hatası sessizce ölü menü öğesi üretir (şu an çalışıyor, AX'te Undo ⌘Z / Redo ⇧⌘Z).
- `MainMenu.swift:99`: `Copy as HTML` = ⌥⌘C. macOS'ta ⌥⌘C "Copy Style" (biçim kopyala) standardıdır; zengin metin bağlamında başka uygulamalarla karışır.

**Neden önemli**
Düşük etkili; ama diğer metin düzenleyicilerle geçiş yapan kullanıcı ⌥⌘C'yi yanlış anlamlandırır.

**Somut düzeltme**
- Undo/Redo için `#selector(UndoManager.undo)` benzeri derlenebilir alternatif yoksa da en azından `NSSelectorFromString("undo:")` kullanımını tek bir yerde sabitle ve test et; Copy as HTML'i ⌃⌥⌘C veya ⇧⌘C (Inline Code'u ⌃⌘C'ye taşı) yap.

---

## 4. Pencere, sekme, toolbar, durum geri yükleme

### P-05 — Durum geri yükleme yok / doğrulanamadı · **Medium**

**Kanıt**
- Kod: `isRestorable`, `restorationClass`, `encodeRestorableState`, `applicationShouldSaveApplicationState`, `applicationShouldRestoreApplicationState` aramaları **0 sonuç**. `AppDelegate.swift:32` yalnızca `applicationSupportsSecureRestorableState -> true` döndürüyor (bu bir güvenlik bayrağıdır, geri yükleme yapmaz).
- Gözlem: oturum boyunca `~/Library/Saved Application State/com.ursula.quickmd.savedState` **hiç oluşmadı** (`ls` → "No such file or directory"); bir belge açıkken çıkıp aynı bundle yeniden başlatıldığında yalnızca boş `Untitled` penceresi geldi (CGWindowList: `name=[Untitled]`), önceki belge geri gelmedi.
- **Uyarı (dürüstlük notu):** Bu makinede (a) sistem "çıkarken pencereleri kapat" davranışı açık olabilir, (b) aynı anda birden çok QuickMD örneği çalıştığı için kontrollü "aç–kapat–aç" testi yapılamadı ve (c) 13:07'deki yeniden açma denemesinde LaunchServices, `build/QuickMD.app` yerine makinede kurulu **v0.1.0** kopyasını (`/Applications/QuickMD.app`) başlatmış olabilir. Bu yüzden sonuç "yok" değil, "**doğrulanamadı; kodda hiçbir destek yok**" olarak okunmalı. Kod kanıtı kesin: geri yükleme API'lerinin hiçbiri kullanılmıyor.
- Buna rağmen pencere çerçevesi ve split durumu kalıcı: `DocumentWindowController.swift:39` (`windowFrameAutosaveName`), `:55` (`splitView.autosaveName`), `SettingsWindow.swift:30` (`setFrameAutosaveName`). AX/`defaults`: `"NSWindow Frame QuickMDDocument" = "538 274 900 700 …"` kaydedilmiş.

**Neden önemli**
Apple'ın belge uygulamaları çıkışta açık belgeleri/pencereleri geri getirir; uygulama menüsünde AppKit'in otomatik eklediği **"Quit and Keep Windows" ⌥⌘Q** (AX dökümünde görünüyor) kullanıcıya bu sözü veriyor. Aynı davranış, önizleme/outline görünürlüğü ve tam ekran durumu için de beklenir.

**Somut düzeltme**
- `AppDelegate`'e `applicationShouldSaveApplicationState` / `applicationShouldRestoreApplicationState` (true) ekle; `DocumentWindowController`'a `restorationClass` + `encodeRestorableState(with:)`/`restoreState(with:)` vererek `previewItem.isCollapsed`, `outlineItem.isCollapsed`, `Settings` ve sekme düzenini sakla; `window.identifier = NSUserInterfaceItemIdentifier("QuickMDDocumentWindow")`, `window.isRestorable = true`.
- Sekmeler için `NSWindow.tabbingIdentifier` zaten doğru (`DocumentWindowController.swift:35`) — geri yükleme bunun üzerine kurulabilir.
- Kabul testi: 2 sekme açık, önizleme açık → ⌘Q → uygulamayı aç → 2 sekme + önizleme açık gelmeli; `~/Library/Saved Application State/...savedState` oluşmalı.

### P-09 — Belge proxy ikonu gizlenmiş · **Medium**

**Kanıt**
- `DocumentWindowController.swift:121`: `window?.standardWindowButton(.documentIconButton)?.isHidden = true`, yorum: "Title text only, no proxy icon."
- Belge penceresi görüntüsünde başlıkta ikon yok (screencapture, `note.md` + "Edited").
- `window.representedURL` atanmıyor (grep: 0).

**Neden önemli**
Proxy ikonu macOS belge penceresinin imzasıdır: dosyayı sürükleyip taşıma, ⌘-tık ile yol menüsü, "Finder'da Göster". Gizlenmesi bilinçli bir estetik tercih olabilir (bkz. §11), ama HIG'in standart belge davranışını kaybettiriyor.

**Somut düzeltme**
- İkonu görünür bırak (`isHidden = false`) ve `window.representedURL = markdownDocument?.fileURL` ata; estetik kaygı varsa `window.titleVisibility` veya `titlebarAppearsTransparent` ile başlığı sadeleştir, ikonu değil. Sekmeli pencerede proxy ikonu sekme çubuğunda da doğru görünür.

### P-19 — Tam ekran davranışı doğrulanamadı · **Low**

**Kanıt**
- `MainMenu.swift:213` `Enter Full Screen ⌃⌘F` menüde var (AX: `mods 24` = ⌃⌘). Ancak `NSWindowDelegate`'te `window(_:willUseFullScreenPresentationOptions:)`, `windowWillEnterFullScreen`, `windowDidExitFullScreen` **yok**; `window.collectionBehavior` ayarlanmıyor.
- `DocumentWindowController.swift:29-30, 129-134`: `titlebarAppearsTransparent`, `isOpaque = false`, `NSVisualEffectView(.fullScreenUI, behindWindow)` + sabit alfalı tint. Tam ekranda titlebar gizlenince `behindWindow` cam davranışı değişebilir; denenmedi.
- Stage Manager / birden çok Space davranışı da test edilmedi (pencere `collectionBehavior` varsayılan `.managed`).

**Neden önemli**
Tam ekran, macOS'ta günlük kullanım; özel cam kullanan uygulamalarda siyah/bulanık görüntü veya toolbar'ın kaybolması klasik hatadır.

**Somut düzeltme**
- Tam ekran girişinde `glass.blendingMode = .withinWindow` veya `material = .fullScreenUI` + opak tint'e geç; çıkışta geri al. `window(_:willUseFullScreenContentSize:)` ile okuma genişliğini koru. Ardından ⌃⌘F gir/çık ve görüntü alarak doğrula.

---

## 5. Erişilebilirlik

### P-03 — AX etiketi/rolü yok; özel çizilen kontroller AX/klavye dışı · **High**

**Kanıt**
- `Sources/` içinde `accessibilityLabel`/`setAccessibility*`/`isAccessibilityElement` **yok**; tüm "accessibility" eşleşmeleri `NSImage(systemSymbolName:accessibilityDescription:)` (7 adet).
- AX dökümü (belge penceresi):
  `AXSplitGroup (title=[], desc=[])` · `AXScrollArea (title=[], desc=[])` · **`AXTextArea (title=[], desc=[missing value])`** · `AXToolbar` · `AXButton desc=[Outline] help=[Show or hide the outline (⌥⌘O)]` · `AXButton desc=[Preview]` · `AXButton desc=[Share]`
  → Toolbar düğmeleri iyi (pozitif), ama **editörün metin alanının adı yok**; VoiceOver "metin alanı" der, hangi belge/pane olduğunu söylemez.
- Özel çizilen ve etkileşimli olanlar:
  - Onay kutuları `HorizontalRuleLayoutManager.swift:125-160` ile çiziliyor; alttaki `[ ]`/`[x]` karakterlerinin rengi `NSColor.clear` yapılıyor (`MarkdownStyler.swift:439`). Tıklama yalnızca fare: `MarkdownTextView.swift:301-312` (`mouseDown` → `toggleCheckbox`). AX'te bunlar sadece metin; **VoiceOver ile işaretlenemez**, klavye ile de yalnızca ⌘↩ ("Mark Task Done", `MainMenu.swift:146`) ile tüm satırlar.
  - Footer istatistiği: `EditorViewController.swift:86-87` düz `NSView` + `NSClickGestureRecognizer` + `toolTip`. AX rolü yok, `accessibilityPerformPress` yok, kısayol yok.
  - Yatay çizgi/panel çizimleri (`HorizontalRuleLayoutManager.swift:31-109, 162-204`) — AX açısından sorun değil (karakterler storage'da duruyor), ama çizilen onay kutusu öyle değil.
- Olumlu: `OutlineViewController` gerçek `NSTableView` kullanıyor (`SidePanes.swift:215-288`, `cell.textField = label`) → AX'te gezinilebilir; toolbar düğmelerinde `accessibilityDescription` var (`DocumentWindowController.swift:210, 228`).

**Neden önemli**
HIG ve App Store incelemesi: özel çizilen her etkileşimli öğenin AX karşılığı olmalı. Şu hâlde VoiceOver kullanıcısı (a) görev listelerini işaretleyemez, (b) footer'ın tıklanabilir olduğunu öğrenemez, (c) hangi metin alanında yazdığını duymaz. Full Keyboard Access açıkken de odaklanabilir kontrol yok.

**Somut düzeltme**
- `EditorViewController.loadView`: `textView.setAccessibilityLabel("Markdown editor")`, `setAccessibilityHelp("Type Markdown; ⌘⌥P previews, ⌘↩ ticks a task")`.
- Footer: `NSView` yerine erişilebilir bir kontrol (ör. `NSButton` bezel `.accessoryBarAction` veya `NSView` + `setAccessibilityRole(.button)` + `accessibilityLabel("Word count")` + `accessibilityValue(label)` + `accessibilityPerformPress { cycle() }`); View menüsüne "Cycle Footer Statistic" öğesi ekle.
- Onay kutuları: `MarkdownTextView`'a `accessibilityCustomActions` ekle ("Toggle task") **veya** her `[ ]` aralığı için `NSAccessibilityElement`/`accessibilityChildren` üret (rol `.checkBox`, değer `.number`/`.button` durumu); en azından `accessibilityValue` ile "3 of 7 tasks done" bilgisini footer'a taşı.
- Kabul testi: Accessibility Inspector ile editör adı, footer rolü, onay kutusu aksiyonu görünmeli.

### P-04 — Sistem erişilebilirlik ayarları hiç okunmuyor; yüksek kontrast zorla iptal · **High**

**Kanıt**
- `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` / `...ShouldReduceTransparency` / `...ShouldIncreaseContrast` ve `accessibilityDisplayOptionsDidChangeNotification`: **0 sonuç** (grep).
- Görünüm adı sabitleniyor: `DocumentWindowController.swift:128` `window?.appearance = NSAppearance(named: chrome.appearance)`; `Theme.swift:246` `appearance: theme == .dark ? .darkAqua : .aqua`; aynı sabitleme `SettingsWindow.swift:322`, `EditorViewController.swift:231`, `SidePanes.swift:86`. `NSAppearance.Name.accessibilityHighContrastAqua` / `…DarkAqua` hiç kullanılmıyor. → Sistem "Kontrastı artır" açıkken pencere yine normal kontrast görünümüne sabitlenir ve **yüksek kontrast görünüm varyantı devre dışı kalır**.
- "Saydamlığı azalt" için: cam `NSVisualEffectView` + üstünde sabit alfalı tint (`Theme.swift:203-229`: `.strong` → 0.22/0.40, `.subtle` → 0.50/0.72) ve `window.isOpaque = false` (`DocumentWindowController.swift:30, 129`). Uygulama bu ayarı okumadığı için pencere, kullanıcı saydamlığı azaltmış olsa da masaüstünü göstermeye devam eder.
- "Hareketi azalt" için: `previewItem.animator().isCollapsed.toggle()` ve `outlineItem.animator()…` (`DocumentWindowController.swift:156, 166`) ile yan panel animasyonu; önizlemede `scrollIntoView({behavior: 'smooth'})` (`SidePanes.swift:143`). Hiçbiri `ShouldReduceMotion` okumuyor.
- Palet/renkler: `Theme.swift:111-181` sabit sRGB değerleri; `syntax`/`divider` alfa 0.30-0.38. `ShouldIncreaseContrast` açıkken bu düşük kontrastlı markdown işaretleri koyulaşmıyor. (Sistem renkleri — `controlAccentColor`, `separatorColor` — doğru kullanılmış, onlar otomatik uyum sağlıyor.)

**Neden önemli**
Bu üç ayar macOS'un erişilebilirlik çekirdeği; okunmaması, engelli kullanıcılar için uygulamayı kullanılamaz kılar. Ayrıca görünüm pinlemesi AppKit'in otomatik yaptığı yüksek-kontrast uyarlamasını bilinçli olarak geri alıyor — HIG'de "uygulama görünümü kullanıcı tercihini geçersiz kılmamalı" ilkesine aykırı.

**Somut düzeltme**
- `Theme.swift`'e bir `AccessibilityContext` ekle:
  ```swift
  let ws = NSWorkspace.shared
  struct AXPrefs { var highContrast, reduceMotion, reduceTransparency: Bool }
  // ws.accessibilityDisplayShouldIncreaseContrast / …ReduceMotion / …ReduceTransparency
  NotificationCenter.default.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, …)
  ```
- Görünüm adı çözümü: yüksek kontrast açıksa `.accessibilityHighContrastDarkAqua` / `.accessibilityHighContrastAqua` seç (veya `window.appearance`'ı yalnızca app teması Light/Dark iken pinle; `System` seçiliyken hiç dokunma).
- Saydamlık: `reduceTransparency` ise `Chrome.usesVisualEffect = false`, tint alfa = 1.0.
- Hareket: `reduceMotion` ise `animator()` yerine doğrudan `isCollapsed = …`; önizlemede `behavior: 'auto'`.
- Kontrast: `increaseContrast` iken `Palette`'te `syntax`/`divider` alfa ≥ 0.55 ve `findHighlight`'ı daha doygun yap.
- Kabul testi: ayarları aç/kapat, uygulama çalışırken anında tepki vermeli (bildirim dinlenmeli).

### P-13 — Footer istatistiği yalnızca fare ile · **Low**

**Kanıt** — `EditorViewController.swift:86-88`: `NSClickGestureRecognizer`, `toolTip`; AX rolü/kısayolu yok. (P-03'ün alt kümesi.)

**Neden önemli** — HIG: tıklanabilir metin düğme gibi davranmalı ve klavyeden erişilebilir olmalı.

**Somut düzeltme** — Gerçek `NSButton`/erişilebilir kontrol + View menüsünde kısayollu öğe (P-03 ile birlikte).

---

## 6. Yerelleştirme

### P-02 — Sıfır yerelleştirme altyapısı · **High**

**Kanıt**
- Bundle'da yerelleştirme yok: `find build/QuickMD.app -name '*.lproj' -o -name '*.strings' -o -name '*.xcstrings'` → **boş**; `Sources/` içinde de yok.
- `scripts/build-app.sh:66` yalnızca `CFBundleDevelopmentRegion = en`; **`CFBundleLocalizations` yok** (`plutil -p build/QuickMD.app/Contents/Info.plist` çıktısında da yok). `CFBundleAllowMixedLocalizations` yok.
- `String(localized:)`/`NSLocalizedString` kullanımı: 0. Buna karşılık kullanıcıya görünen sabitler:
  - `MainMenu.swift`: ~90 satırda kullanıcı metni — menü öğesi başlıkları ve `NSMenu(title:)` başlıkları ("New from Template", "Style", "Transparency", "Callout", "Mark Task Done", "Default App for Markdown" …).
  - `SettingsWindow.swift`: 32 — "General", "Appearance", "Settings", "Make Default for .md", "Reset", "Style Default (…)", 4 onay kutusu, 3 açıklama notu ("Opening another Markdown file adds a tab…", "⌘+ and ⌘− change it from any window.", "File › New from Template offers all of them.").
  - `AppDelegate.swift:67-71`: iki NSAlert ("Couldn't make QuickMD the default", "QuickMD now opens Markdown files", "Finder and Quick Look will offer …").
  - `DocumentWindowController.swift`: 42 — toolbar etiketleri/ipuçları ("Headings, lists and blocks", "Show or hide the outline (⌥⌘O)" …).
  - `SidePanes.swift:78-79`: önizleme içi erişim istemi ("Images next to this note need access to its folder. Allow Access…").
  - `Outline.swift:97-115`: footer metinleri ("1 word"/"\(n) words", "1 character"/…, "\(n) min read", "\(a) of \(b) words").
  - `Starters.swift` (311 satır): 10 şablonun İngilizce gövdesi; `displayName`'ler ("Meeting Notes", "To-Do List" …).
  - `Template.swift:43`, `FontFace.swift:33`, `Theme.swift:15-21, 191-197`, `CalloutKind.title` (`Theme.swift:91`).
- Toplam: kaynakta 1130 string sabiti; bunların ~146'sı çok kelimeli kullanıcı metni. Gözlem: sistem Türkçe (Apple menüsü "Bu Mac Hakkında", "Sistem Ayarları…", "Çıkmaya Zorla…") ama QuickMD'nin tüm menüleri İngilizce — aynı menü çubuğunda iki dil.
- Sayı/tarih biçimlendirme: `NumberFormatter` **yok**; footer'da binlik ayırıcı yok ("12345 words" — Türkçe'de "12.345"). Settings'te "\(Int(value)) pt" (`SettingsWindow.swift:293`) birim de sabit. `MeasurementFormatter` yok.
- Çoğul: elle İngilizce kurallar (`Outline.swift:99-115`); `.stringsdict`/xcstrings plural yok. "3 of 5 words" gibi ifadeler İngilizce kelime sırasına bağlı; Türkçe karşılığı "5 kelimenin 3'ü".
- Sabit genişlikler yerelleştirmeyi kırar: `SettingsWindow.swift:53` `root.widthAnchor = 520`, `:98` `preferredMaxLayoutWidth = 340`; Almanca/Fransızca etiketler taşar.
- **Olumlu:** tarih biçimlendirme doğru yapılmış — `Starters.swift:267-280` kullanıcı yereline göre `DateFormatter` (`.long`/`.medium`), ISO tarih için bilinçli olarak `en_US_POSIX` + Gregoryen.

**Neden önemli**
Apple uygulamaları sistem dilini izler; bu, "yerli bir Mac uygulaması" hissinin en güçlü göstergelerinden biri. Altyapı olmadan sonradan çeviri eklemek 146 metni tek tek avlamak demek; ayrıca çoğul/sayı/tarih hataları çeviri sonrası da kalır. App Store'da yerelleştirilmiş ürün sayfası ve ekran görüntüleri için de bu altyapı gerekir.

**Somut düzeltme (sırayla)**
1. Xcode 15 String Catalog: `Sources/QuickMD/Resources/Localizable.xcstrings`; `Package.swift`'e `resources: [.process("Resources")]` ekle (şu an hiç resource tanımlı değil, `Package.swift:8-12`).
2. Menü kurulumunu metin yerine anahtar kullanacak şekilde değiştir: `item("menu.file.new", …)` gibi bir enum + `String(localized:)`. HIG sırası korunarak.
3. Alert/ipucu/not metinlerini aynı kataloğa taşı; toolbar etiketlerini `NSToolbarItem.label = String(localized:)`.
4. `Info.plist`'e `CFBundleLocalizations` (en, tr, de, fr…), `CFBundleAllowMixedLocalizations = true`; `--appstore`/normal build'de `Base.lproj` şart değil (kod tabanlı UI), ama `.xcstrings` bundle'a kopyalanmalı.
5. Çoğul: `.xcstrings` plural varyantları ("%lld word"/"words"), sayılar için `value.formatted()` / `NumberFormatter` (locale-aware), "pt" için `MeasurementFormatter` veya yerelleştirilmiş birim.
6. Düzen: Settings panes'te sabit 520 pt yerine `NSGridView` doğal boyut + `window.contentMinSize`; uzun metinlerle test (Almanca).
7. RTL: `leadingAnchor/trailingAnchor` zaten kullanılıyor (iyi); Arapça bir sahte lokalizasyonla (pseudo-localization) bir kez gözle kontrol et.

---

## 7. Klavye kısayolları

### P-12 — ⌘+ (Bigger) Türkçe klavyede sistem ekran görüntüsü kısayoluyla çakışıyor · **Medium**

**Kanıt**
- `MainMenu.swift:192-194`: `Bigger` = `"+"` (⌘), `Smaller` = `"-"` (⌘), `Actual Size` = `"0"` (⌘).
- Sistemdeki klavye düzeni `Turkish-QWERTY-PC` (com.apple.HIToolbox). `UCKeyTranslate` ile ölçüm: keycode 24 → `-`, keycode 27 → `*`, **keycode 21 + Shift → `+`**, keycode 29 + Shift → `=` (yani `=` karakteri ⌘ ile doğrudan basılamıyor).
- Bu yüzden bu klavyede ⌘+ = **⇧⌘4** olur; ⇧⌘4 macOS'un "Seçili alanın ekran görüntüsü" sistem kısayoludur ve sistem kısayolları uygulama menüsünden önce çalışır.
- Deneysel doğrulama:
  - ⌘- (keycode 24) → `defaults read com.ursula.quickmd FontSize.invisible`: 17 → 16 → 15 (**küçüldü**, doğru).
  - ⇧⌘4 (yani ⌘+ karşılığı) → değer **değişmedi** (sistem yakaladı; Esc ile iptal edildi).
  - AX dökümü: `Bigger [":" / mods 0]` — "+" karakteri bu düzende ":" tuşuna düşüyor; `Smaller [-]` çalışıyor.
- ⌘= alternatifi yok (menüde ikinci/allternate öğe yok; `isAlternate` kullanılmıyor).
- Aynı sınıf sorun: `Indent ⌘]` / `Outdent ⌘[` AX'te **⌘Ü / ⌘Ğ** olarak görünüyor (Türkçe-QWERTY-PC düzeninde `]` tuşu `Ü`, `[` tuşu `Ğ`) — çalışıyor ama keşfedilebilirliği düşük.

**Neden önemli**
Türkçe (ve çoğu AB) klavye düzeninde `+` Shift'li bir tuştur; ⌘+ tek başına basılamaz. Apple uygulamaları bu yüzden "⌘+" ile "⌘=" alternatifini birlikte verir (TextEdit: "Bigger" ⌘+ ve ⌘= eşdeğeri). Şu hâlde QuickMD'de metni büyütmenin klavye yolu bu makinede ölü; kullanıcı yalnızca Settings slider'ına mahkûm.

**Somut düzeltme**
- `MainMenu.swift`'e ikinci (alternate) öğe ekle: `Bigger` için `"+"` (⌘) **ve** `"="` (⌘) aynı action'a; `Smaller` için `"-"` (⌘). Gerekirse `.isAlternate = true` yerine iki ayrı görünür öğe (`Bigger` ⌘+ / `Bigger =` ⌘=) — HIG'de gizli alternate kabul edilir.
- Kritik kısayolları harf tabanlı seç (⌘⇧. / ⌘⇧, gibi) veya `NSEvent` karakter eşlemesine güvenmeyen `NSMenuItem.keyEquivalent` + `keyEquivalentModifierMask` kombinasyonlarıyla test et.
- Test matrisi: US, Turkish-QWERTY, German, French (AZERTY) düzenlerinde ⌘+/⌘-/⌘0, ⌘]/⌘[, ⌥⌘P/O, ⌃⌘F.

**Not:** Copy as HTML'in ⌥⌘C çakışması §3'teki P-16'da ele alındı.

**Doğrulanan standart kısayollar (pozitif):** ⌘N, ⌘O, ⌘S, ⌘W, ⌘M, **⌘,** (Settings açıldı, ekran görüntüsü), ⌘Z/⇧⌘Z, ⌘X/C/V/A, ⌘F, ⌘G/⇧⌘G, ⌥⌘F (Replace alanıyla açıldı — aşağıda), ⌘B/⌘I/⌘K, ⌥⌘1-4, ⌥⌘P, ⌥⌘O, ⌃⌘F, ⌘↩ (Mark Task Done), ⌘E (Use Selection for Find), ⌘J (Jump to Selection).

---

## 8. Settings (Ayarlar) penceresi

### P-07 — Örnek ham markdown; sabit genişlik; General yerine Appearance · **Medium**

**Kanıt**
- `SettingsWindow.swift:21`: `tabs.selectedTabViewItemIndex = 1` → pencere **Appearance** sekmesinde açılıyor; HIG'de ilk/General sekmesi beklenir.
- `:23-31`: `NSWindow(contentViewController: tabs)`, `styleMask = [.titled, .closable]`, `toolbarStyle = .preference`, `title = "Settings"`, `isReleasedWhenClosed = false`, `center()` + autosave. Genel olarak doğru: Settings adı (macOS 13+), ⌘, ile açılıyor (AX: `Settings… [Ö / mods 0]` = ⌘,), toolbar tarzı sekmeler.
- `:53`: sabit `root.widthAnchor = 520` — yerelleştirmede taşma riski (P-02).
- `:303-324` `updateSample()`: yalnızca gövde fontu + başlık fontu uygulanıyor; örnek metin **`**Bold**`, `*italic*`, `` `code` `` işaretlerini ham gösteriyor** (ekran görüntüsünde doğrulandı: "The quick brown fox jumps over the lazy dog. **Bold**, *italic* and `code`."). Örnek, amacı olan "bu font nasıl görünecek" sorusunu yanıtlamıyor; aksine markdown editörünün ham metin gösterdiği izlenimini veriyor.
- `:293`: `sizeLabel.stringValue = "\(Int(value)) pt"` — birim ve sayı yerelleştirilmemiş.
- `:179` "Make Default for .md" düğmesi app menüsündeki öğeyle çift (P-15).
- `:257` "⌘+ and ⌘− change it from any window." — P-12 ile çelişiyor (⌘+ bu klavyede çalışmıyor).
- `:184-196`: "New document" başlangıç şablonu ve "Windows/Sidebar" seçenekleri HIG'e uygun.
- AX: Settings penceresi normal `AXStandardWindow`; sekme düğmeleri görünür; satır etiketleri `NSTextField(labelWithString:)` → AX'te okunur (iyi).

**Neden önemli**
Settings, "Apple uygulaması" hissinin vitrini. Ham markdown gösteren bir stil önizlemesi burada özellikle ters etki yapar; yanlış açılış sekmesi ve sabit genişlik ise cila eksikliği.

**Somut düzeltme**
- `selectedTabViewItemIndex = 0`.
- Örnek metni gerçekten stillendir: `MarkdownStyler.restyle(storage, …)` çağır veya doğrudan `**`/`*`/`` ` `` aralıklarına bold/italic/monospace font + `Palette` renkleri uygula; iki satır markdown'ın *render edilmiş* hâlini göster.
- Genişlik: sabit constraint yerine `NSGridView` doğal boyutu + `window.contentMinSize`/`setContentSize`; `preferredMaxLayoutWidth`'ı metne bırak.
- "pt" için `MeasurementFormatter`; ⌘+/⌘− notunu P-12 düzeltmesinden sonra güncelle.
- "Make Default" için tek kaynak belirle.

---

## 9. Sistem entegrasyonu

### P-10 — Quick Look önizleme eklentisi yok · **Medium**

**Kanıt**
- Bundle'da uzantı yok: `find build/QuickMD.app \( -name '*.appex' -o -name 'PlugIns' \)` → boş; `NSExtension` anahtarı yok.
- Sistemde kayıtlı Quick Look üreticileri (`qlmanage -m plugins`): metin için **tek** eşleşme `public.plain-text -> /System/Library/QuickLook/Text.qlgenerator`; QuickMD'ye/bundle'ına ait üretici yok. `net.daringfireball.markdown` bu tipe uyduğu için Finder'da Space ile **ham markdown kaynağı** görünüyor.
- README ("Opens `.md` files from Finder and Quick Look") ve `AppDelegate.swift:70-71` metni ("Finder and Quick Look will offer 'Open with QuickMD'") kullanıcıya Quick Look entegrasyonu vaat ediyor.

**Neden önemli**
Markdown editöründe Apple'ın yaptığı şey (Bear, iA Writer, Xcode'da docc): Space ile **render edilmiş** önizleme. Ham kaynak göstermek, uygulamanın varlık sebebiyle çelişiyor; ayrıca README'deki vaat karşılanmıyor.

**Somut düzeltme**
- Ayrı bir `MarkdownPreview.appex` (Quick Look Preview Extension, `com.apple.quicklook.preview`) hedefi ekle; `QLPreviewingController` içinde `WKWebView` + mevcut `MarkdownHTML.page(...)` çıktısını yükle (`SidePanes.swift`'teki `PreviewScheme` handler'ı yeniden kullan). Assets (Inter/Myeongjo/KaTeX/Mermaid) eklenti bundle'ına da kopyalanmalı (`scripts/build-app.sh:56`).
- `Package.swift`'te ayrı target + app bundle'a `Contents/PlugIns` olarak kopyalama; `Info.plist`'e `QLSupportedContentTypes`/`NSExtensionAttributes`.
- Test: `qlmanage -p /tmp/deneme.md` ve Finder'da Space; App Store'da sandbox'lı uzantı için `com.apple.security.app-sandbox` + uzantı entitlement'ı gerekir.

### P-11 — Spotlight, App Intents/Shortcuts, Services sağlama, Dock menüsü, Handoff, AppleScript · **Medium**

**Kanıt (hepsi grep = 0)**
- `CSSearchableIndex`/`CoreSpotlight` yok → notlar Spotlight'te bulunamıyor.
- `AppIntents`/`AppShortcuts` yok → Shortcuts.app'te "Yeni Markdown notu" aksiyonu yok.
- `NSApp.servicesProvider` yok → başka uygulamalardan seçili metni "QuickMD'de yeni not" olarak gönderme yok. (Services menüsü *alıcı* olarak çalışıyor: AX'te `Services ▸ {New HoudahSpot Search, Services Settings…}` — sistem servisleri listeleniyor, `NSApp.servicesMenu` doğru bağlanmış `MainMenu.swift:46-48`.)
- `applicationDockMenu` yok → Dock'ta sağ tık menüsünde "Yeni Not" / son belgeler yok (yalnızca sistemin "Son Kullanılanlar/Pencereler" listesi).
- `NSUserActivity`/Handoff yok; `NSServicesMenu`/`.sdef` yok → AppleScript sözlüğü yok (standart `NSApplication` komutları dışında otomasyon yok).
- `NSSharingService` yalnızca 3 yerde ve doğru biçimde: `DocumentWindowController.swift:232-238` `NSSharingServicePickerToolbarItem`; ayrıca AppKit File menüsüne otomatik "Share" öğesi ekliyor (AX: `Share ▸ {No Document}` yer tutucusu). **Paylaşım tarafı tamam.**

**Neden önemli**
Apple'ın kendi uygulamaları bu yüzeylerin hepsine dokunur: Spotlight (Notes), Shortcuts (Notes/Finder), Services (TextEdit), Dock menüsü (Notes/Finder), Handoff. Bunlar "uygulama değil, sistemin parçası" hissini veren katman; tek tek küçük ama toplamda belirgin.

**Somut düzeltme (etki/emek sırasıyla)**
1. **Services sağlama** (yarım gün): `NSApp.servicesProvider = self`, `@objc func newNoteFromString(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>)`; `Info.plist`'e `NSServices` tanımı.
2. **Dock menüsü** (yarım gün): `applicationDockMenu(_:) -> NSMenu?` → "New Note" + `NSDocumentController.shared.recentDocumentURLs.prefix(5)`.
3. **App Intents** (1 gün): `AppIntent` "Create Markdown Note" (parametre: başlık/metin), `AppShortcutsProvider` ile Siri/Shortcuts.
4. **Spotlight** (1-2 gün): açılan/kaydedilen belgeleri `CSSearchableIndex` ile indeksle (`title`, `text` snippet, `kMDItemContentType`); App Store'da gizlilik gerekçesi yaz (yerel indeks).
5. **Handoff/AppleScript** (isteğe bağlı): `NSUserActivity` (`isEligibleForHandoff`), `.sdef` ile `open`/`make new document`.

---

## 10. Kanıtlanmış olumlu yönler (zaten "Apple gibi")

Bunlar denetim sırasında **çalışır** durumda bulundu; korunmalı.

1. **Uygulama menüsü tam ve doğru sırada:** About / Settings… ⌘, / Services / Hide ⌘H / Hide Others ⌥⌘H / Show All / Quit ⌘Q (`MainMenu.swift:39-56`; AX dökümü). `NSApp.servicesMenu` bağlı (`:48`).
2. **Window menüsü AppKit'e devredilmiş:** `NSApp.windowsMenu = window` (`:15`); AppKit Minimize ⌘M, Zoom, Bring All to Front, ayrıca sekmeler için Show Previous/Next Tab (⌃⇧⇥/⌃⇥), Move Tab to New Window, Merge All Windows ve macOS 15'in Fill/Center/Move & Resize/Full Screen Tile öğelerini kendisi ekliyor (AX dökümü). Elle eklenen 3 öğe doğru.
3. **Edit menüsü first-responder zinciri:** Cut/Copy/Paste/Delete/Select All `NSText.*` selector'ları, hedef nil (`:97-103`) → Settings penceresinde de doğru davranır.
4. **Find bar + Replace doğru:** `usesFindBar = true`, `isIncrementalSearchingEnabled = true` (`EditorViewController.swift:70-71`); "Find and Replace…" `NSTextFinder.Action.showReplaceInterface = 12` tag'ini kullanıyor (`MainMenu.swift:109`). **Test edildi:** ⌥⌘F find bar'ı Replace alanı ve "Replace/All" düğmeleriyle açtı (ekran görüntüsü). (İlk bakışta "yanlış enum" gibi görünse de `usesFindBar` ile doğru çalışıyor — bu bir bug değil.)
5. **`⌘,` Settings'i açıyor**, pencere adı "Settings", `toolbarStyle = .preference`, `NSTabViewController(.toolbar)` — macOS 13+ Settings kalıbı (`SettingsWindow.swift:11-31`).
6. **Birleşik toolbar + özelleştirme + durum saklama:** `toolbarStyle = .unified`, `allowsUserCustomization = true`, `autosavesConfiguration = true` (`DocumentWindowController.swift:188-191`); `NSTrackingSeparatorToolbarItem` sidebar ayırıcısına bağlı (`:220`); Share `NSSharingServicePickerToolbarItem` (`:232-238`). View ▸ Customize Toolbar… mevcut.
7. **Sekmeler:** `tabbingIdentifier = "QuickMDDocument"` (`:35`), elle sekme ekleme (`MarkdownDocument.swift:34-59`), tab bar göründü (görüntü); AppKit sekme menü öğeleri otomatik geldi.
8. **Belge yaşam döngüsü:** `autosavesInPlace = true` (`MarkdownDocument.swift:17`) → File ▸ Revert To alt menüsü otomatik; pencere/split frame autosave (`DocumentWindowController.swift:39,55`); min boyut 420×300 (`:31`).
9. **Dinamik menü başlıkları:** `validateMenuItem` Show/Hide Preview, Show/Hide Outline başlıklarını çeviriyor (`DocumentWindowController.swift:348-353`) — HIG'in istediği davranış.
10. **Renk uyumu:** seçim ve onay kutusu `NSColor.controlAccentColor` kullanıyor (`Theme.swift:142,152,163,175`; `HorizontalRuleLayoutManager.swift:143`) → Sistem Ayarları'ndaki vurgu rengini izliyor. Ayırıcılar `separatorColor`/`secondaryLabelColor`.
11. **Sistem görünümü:** `System/Light/Dark` üçlüsü; `NSApp.effectiveAppearance` KVO ile yeniden boyama (`AppDelegate.swift:18-23`), `NSHighResolutionCapable`, `NSRequiresAquaSystemAppearance` yok (doğru).
12. **Sürükle-bırak (içeri):** dosya bırakınca markdown link/görsel üretimi, klasör içindeyse göreli yol (`MarkdownTextView.swift:144-170`) — elle yazmaktan çok daha "Mac gibi".
13. **Belge içi bağlantılar:** ⌘-tık link açma, `#anchor` ile başlığa atlama (`MarkdownTextView.swift:299-360`).
14. **Yazdırma/dışa aktarma:** File ▸ Print render edilmiş sayfayı yazdırıyor (`DocumentWindowController.swift:325-336`), PDF'e kaydetme aynı yolu kullanıyor; Export HTML/PDF + Copy as HTML var.
15. **Yerelleştirilmiş tarih (doğru yapılmış):** `Starters.swift:267-280`.
16. **Güvenli geri yükleme bayrağı:** `applicationSupportsSecureRestorableState` (`AppDelegate.swift:32`) — macOS 12+ uyarısını önler.
17. **Menü ikonları:** New from Template / Callout / Style / Font öğelerinde SF Symbols (`MainMenu.swift:67`, `:176`; `DocumentWindowController.swift:251`; AX'te doğru).
18. **Recents çalışıyor:** ilk Open Recent gerçekten doldu (`note.md`, `restore-probe.md`) — sorun ikinci kopyada (P-06).

---

## 11. Bilinçli tasarım tercihleri (HIG'den sapıyor ama hata değil)

Bunlar kod/yorumlarda açıkça tercih olarak duruyor; raporda hata gibi sayılmadı. Yalnızca **yan etkilerine** dikkat çekiyorum.

| # | Tercih | Kanıt | Not / öneri |
|---|---|---|---|
| 1 | Özel "cam" pencere: `NSVisualEffectView` + tint, `.fullScreenUI`, opak olmayan pencere | `DocumentWindowController.swift:18-19, 59-62, 129-134`; `Theme.swift:232-249` | Marka kimliği; ama P-04 (Reduce Transparency) ve P-19 (full screen) ile birlikte ele alınmalı |
| 2 | Kullanıcıya üç kademeli saydamlık (Off/Subtle/Strong) | `Theme.swift:186-230`; View ▸ Transparency | HIG'de böyle bir ayar yok; hoş bir "kişiselleştirme". Sistem ayarını geçersiz kılmamalı |
| 3 | Uygulamanın kendi Light/Dark/System teması, pencere görünümünü sabitlemesi | `Theme.swift:10-31`; `Appearance` alt menüsü | Sonuç: sistemin yüksek-kontrast varyantı kayboluyor (P-04). "System" seçiliyken pinlememek en az riskli düzeltme |
| 4 | Proxy ikonunun gizlenmesi ("Title text only") | `DocumentWindowController.swift:121` | Standart sürükle/⌘-tık davranışını kaybettiriyor (P-09); estetik hedefe `titleVisibility` ile ulaşılabilir |
| 5 | Sekme davranışının sistem "Sekmeleri tercih et" ayarı yerine uygulama ayarına bağlanması | `DocumentWindowController.swift:32-34` (yorumda açıkça yazıyor) | Bilinçli; ama sistem tercihini yok saymak HIG'de önerilmez — Settings'te "System" seçeneği eklenebilir |
| 6 | Küratörlü Font menüsü + Settings'te font seçimi; sistem Font Paneli (⌘T "Show Fonts") yok | `MainMenu.swift:172-181`; `FontFace.curated` | Marka fontları için mantıklı; isteğe bağlı olarak "Show Fonts…" ⌘T eklenebilir (⌘T şu an New Tab) |
| 7 | Biçimlendirme tamamen Format menüsünden; biçim toolbar'ı/paneli yok | `MainMenu.swift:130-183` | Sade; HIG'de kabul edilebilir |
| 8 | Footer'a tıklayınca istatistik döngüsü (words → chars → reading time) | `EditorViewController.swift:86-87`; `Outline.swift:89-115` | Şık ama keşfedilemez + AX dışı (P-13); kısayol/menü öğesi eklenmeli |
| 9 | "Default App for Markdown" uygulama menüsünde | `MainMenu.swift:44` | HIG'de yeri Settings (P-15) |
| 10 | Markdown işaretlerinin ekranda kalması (`#`, `**`, `` ` ``) | `Theme.swift:121-124`; `MarkdownStyler` | Ürünün özü: dosya düz metin kalır. HIG'ye aykırı değil, tercih |
| 11 | Task onay kutularının metin üzerine çizilmesi | `HorizontalRuleLayoutManager.swift:125-160` | Görsel olarak çok iyi; AX karşılığı yok (P-03) |
| 12 | `windowDidBecomeKey` ile odağın her zaman editöre verilmesi | `DocumentWindowController.swift:113-115` | Pencereye dönünce sidebar/toolbar odağı çalınabilir; küçük UX tercihi |
| 13 | Touch Bar desteği yok | — | macOS 13+ HIG'de gerekli değil; not olarak yazıldı, aksiyon yok |

---

## 12. Doğrulanamayanlar / riskler

1. **VoiceOver ile gerçek anonslar** — AX hiyerarşisi incelendi; VoiceOver oturumu açılıp dinlenmedi.
2. **Durum geri yükleme** — sistem ayarı ve eşzamanlı örnekler nedeniyle kontrollü test yapılamadı (P-05).
3. **Tam ekran görselleri** — özel cam ile full screen davranışı test edilmedi (P-19).
4. **Yüksek kontrast / saydamlık azaltma görsel sonucu** — sistem ayarları değiştirilmedi (kullanıcı makinesi); yalnızca kod yolu kanıtlandı (P-04).
5. **RTL** — Arapça/İbranice yerelleştirme olmadığı için test edilecek bir RTL düzeni yok; `leading/trailing` kullanımı iyi.
6. **Stage Manager / çoklu Space / Bildirim Merkezi** — denenmedi.
7. **Quick Look, Spotlight, App Intents** — olmadıkları için davranış testi yok; öneriler yeni hedef gerektiriyor (paketleme/imzalama etkisi 01 numaralı denetimde).
8. **`/Applications/QuickMD.app` (v0.1.0, 31 Eki) makinede kurulu** — `open build/QuickMD.app` bazen LaunchServices nedeniyle eski kopyayı açtı. Menü dökümü ve pencere görüntüleri doğrudan çalıştırılan `build/QuickMD.app/Contents/MacOS/QuickMD` (bu çalışma ağacından derlenmiş build) üzerinden alındı; iki build arasındaki fark menü dökümünde görüldü (eski kopyada New Tab, New from Template, Export as PDF yok). Yalnızca 13:07'deki çıkış–yeniden açma denemesi eski kopyaya düşmüş olabilir — bu nedenle P-05 "doğrulanamadı" olarak işaretli.
9. **`MarkdownDocument.printOperation(withSettings:)`** (`MarkdownDocument.swift:112-117`) ham `NSTextView`'ı yazdırıyor; menü yolu render edilmiş sayfayı kullanıyor (P-17). Sistem "Print" çağrıları bu yolu kullanırsa çıktı farklı olur — hangi yolların kullanıldığı test edilmedi.

---

## 13. İlk 5 düzeltme, sırayla

1. **Help menüsünü doldur (P-01).** En görünür eksik; 1 gün içinde yapılır: 3 sayfalık help book + `CFBundleHelpBookName` + `QuickMD Help ⌘?` / `What's New` / `Report an Issue…`. Kazanç: menü çubuğu artık Apple şablonunun tamamı.
2. **Yerelleştirme altyapısını kur (P-02).** `.xcstrings` String Catalog + `String(localized:)`, menü/alert/Settings metinlerinin anahtarlara taşınması, `CFBundleLocalizations`, plural + `NumberFormatter`/`MeasurementFormatter`. Önce TR+EN; ardından DE/FR ile düzen testi. Kazanç: Türkçe sistemde Türkçe uygulama; App Store için çevrilebilirlik.
3. **Erişilebilirlik paketi (P-03 + P-04 + P-13).** Editör/footer/onay kutusu AX etiketleri ve aksiyonları; görünüm sabitlemesini yüksek-kontrast'ı ezmeyecek şekilde değiştir; `ShouldReduceTransparency`/`ShouldReduceMotion`/`ShouldIncreaseContrast` oku ve `accessibilityDisplayOptionsDidChange` dinle. Kazanç: VoiceOver/klavye kullanıcıları + HIG uyumu + App Store inceleme riskinin azalması.
4. **Menü ve kısayol doğruluğu (P-06 + P-08 + P-12 + P-14).** Boş ikinci Open Recent'i kaldır; Show/Hide Sidebar ⌃⌘S ve Show/Hide Toolbar ⌥⌘T ekle (Table'ı ⌥⌘⇧T'ye taşı); ⌘+ için ⌘= alternatifi ekle ve Türkçe düzende doğrula; "Save…" → "Save". Kazanç: günlük kullanımda "Apple gibi" hissi; boş menülerin yok olması.
5. **Sistem entegrasyonu: Quick Look önizleme eklentisi + Services + Dock menüsü (P-10 + P-11).** `MarkdownPreview.appex` (mevcut `MarkdownHTML`/`PreviewScheme` yeniden kullanılarak), `NSApp.servicesProvider` ile "New Note from Selection", `applicationDockMenu` ile son notlar. Kazanç: Finder/başka uygulamalar içinde görünürlük — "sistemin parçası" hissi.

**Sonraki 5 (kısa):** durum geri yükleme (P-05) ve kontrollü testi · proxy ikonu + `representedURL` (P-09) · Settings cila: General'da açılış, gerçek stil önizlemesi, akışkan genişlik (P-07) · tam ekran davranışı ve cam (P-19) · Spotlight + App Intents (P-11).

---

## Ek A — Menü çubuğu dökümü (bu çalışma ağacından derlenen build, AX çıktısı; özet)

`Apple` · `QuickMD` · `File` · `Edit` · `Format` · `View` · `Window` · `Help`

```
QuickMD: About QuickMD | — | Settings… ⌘, | Default App for Markdown | — | Services ▸ {New HoudahSpot Search, Services Settings…}
         | — | Hide QuickMD ⌘H | Hide Others ⌥⌘H | Show All | — | Quit QuickMD ⌘Q | Quit and Keep Windows ⌥⌘Q (AppKit)
File:    New ⌘N | New Tab ⌘T | New from Template ▸ {Blank, –, Note, Meeting Notes, To-Do List, Daily Journal,
         Weekly Review, Project Plan, README, Blog Post, Decision Record} | Open… ⌘O | Open Recent ▸ {…} |
         Open Recent ▸ {Clear Menu}  ← ikinci, boş | — | Close ⌘W | Close All ⌥⌘W (AppKit) | Save… ⌘S |
         Duplicate ⇧⌘S | Rename… | Move To… | Revert To ▸ {…} | — | Share ▸ {…} (AppKit) | —
         Export as HTML… ⇧⌘E | Export as PDF… | — | Page Setup… ⇧⌘P | Print… ⌘P
Edit:    Undo ⌘Z | Redo ⇧⌘Z | — | Cut ⌘X | Copy ⌘C | Copy as HTML ⌥⌘C | Paste ⌘V | Paste and Match Style ⌥⇧⌘V |
         Delete | Select All ⌘A | — | Find ▸ {Find… ⌘F, Find and Replace… ⌥⌘F, Find Next ⌘G, Find Previous ⇧⌘G,
         Use Selection for Find ⌘E, Jump to Selection ⌘J} | Spelling and Grammar ▸ {…} | Substitutions ▸ {…} |
         — | AutoFill ▸ {…} (AppKit) | Start Dictation… | Emoji & Symbols (AppKit)
Format:  Bold ⌘B | Italic ⌘I | Strikethrough ⇧⌘X | Inline Code ⇧⌘C | Link ⌘K | — | Heading 1..4 ⌥⌘1..4 |
         Body Text ⌥⌘0 | — | Bulleted List ⇧⌘L | Numbered List ⇧⌘O | Task List ⇧⌘T | Mark Task Done ⌘↩ |
         Quote ⌘' | Code Block ⌥⇧⌘C | Horizontal Rule ⇧⌘- | Table ⌥⌘T | Callout ▸ {Note, Tip, Important, Warning, Caution} |
         Math Block ⌥⌘M | Mermaid Diagram | — | Indent ⌘] (AX: ⌘Ü) | Outdent ⌘[ (AX: ⌘Ğ) | — |
         Style ▸ {Invisible Details, Classic} | Font ▸ {Inter, San Francisco, Avenir Next, Helvetica Neue, Charter,
         Iowan Old Style, New York, Georgia, Myeongjo, SF Mono, Menlo, –, More Fonts and Size…}
View:    Show All Tabs ⌥⌘, (AppKit) | Show Preview ⌥⌘P | Show Outline ⌥⌘O | Footer | Readable Line Width |
         — | Bigger ⌘+ | Smaller ⌘- | Actual Size ⌘0 | — | Appearance ▸ {Light, Dark, System} |
         Transparency ▸ {Off, Subtle, Strong} | — | Customize Toolbar… | Show Tab Bar | Enter Full Screen ⌃⌘F
Window:  Minimize ⌘M | Minimize All ⌥⌘M (AppKit) | Zoom | Zoom All (AppKit) | Fill ⌃⌥⌘F (AppKit) | Center (AppKit) |
         — | Move & Resize ▸ {…} (AppKit) | Full Screen Tile (AppKit) | — | Remove Window from Set (AppKit) | — |
         Bring All to Front | Arrange in Front (AppKit) | — | Show Previous Tab ⌃⇧⇥ | Show Next Tab ⌃⇥ |
         Move Tab to New Window | Merge All Windows | — | — | <pencere listesi: note.md>
Help:    (BOŞ — hiç öğe yok)
```

AX tarafından ölçülen, raporda kullanılan diğer değerler: `AXTextArea desc=missing value`, `AXButton desc=[Outline]/[Preview]/[Share]`, Settings penceresi `AXStandardWindow` 520×582, belge penceresi `AXStandardWindow` 900×700 (sekmeli).
