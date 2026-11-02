# 04 — Mühendislik Kalitesi, Derleme/Test, Swift 6 ve Sürdürülebilirlik Denetimi

**Proje:** QuickMD — native Swift/AppKit macOS Markdown editörü
**Denetim türü:** Salt-okunur kod kalitesi denetimi (kaynak kodu değiştirilmedi; yalnızca bu rapor yazıldı)
**Denetim tarihi:** 2026-11-01
**Denetlenen sürüm:** `main` @ `9803cde`, çalışma ağacı kirli (aşağıya bakın) — 24 kaynak dosya / 5.968 satır + 2 test dosyası / 322 satır

## 0. Ölçüm ortamı ve yöntem

| Bileşen | Değer |
|---|---|
| Donanım | Apple M1, macOS 15.7.9 (24G830) |
| Toolchain | `swift-driver 1.120.5`, Apple Swift **6.1.2**, hedef `arm64-apple-macosx15.0` |
| Xcode | **Yok** (`xcodebuild` → "requires Xcode, but active developer directory … Command Line Tools") — yalnızca CLT |
| Paket | `swift-tools-version:6.0`, platform `.macOS(.v13)`, `swiftLanguageMode(.v5)`, `enableUpcomingFeature("BareSlashRegexLiterals")` |

Yöntem: (1) soğuk/ılık derleme ve testler gerçekten çalıştırıldı, çıktılar kanıt olarak aşağıda; (2) regex/observer/timer/@MainActor/Sendable taramaları `grep` ile sayıldı; (3) Swift 6 modu ve macOS 15 hedefi **/tmp kopyalarında** derlenerek ölçüldü — depoya dokunulmadı; (4) performans, deponun `/tmp/qmd-bench` kopyasına **yalnızca test dosyası eklenerek** `swift test -c release` ile ölçüldü (üretim kodu birebir aynı); (5) en uzun fonksiyon/ölü kod analizi basit Python+awk betikleriyle yapıldı.

> Not: Tüm performans sayıları **release** yapılandırmasında, boşta (başka derleme çalışmıyorken) alınmıştır. Makine M1 (8 çekirdek); başka donanımda mutlak değerler değişir, oranlar korunur.

---

## 1. Derleme ve test ölçümleri

### 1.1 Derleme

| Komut | Sonuç | Süre | Uyarı | Hata |
|---|---|---|---|---|
| `swift build -c release` (ılık, mevcut `.build`) | ✅ | 2,0 s | **0** | 0 |
| `swift build -c release --scratch-path /tmp/qmd-final` (soğuk, izole) | ✅ | **76,3 s** | **0** | 0 |
| `swift build -c release --triple x86_64-apple-macosx13.0` (çapraz, soğuk) | ✅ Mach-O x86_64 | 114,2 s | **0** | 0 |
| `swift build -c release --triple arm64-apple-macosx15.0` (soğuk) | ✅ | 54,1 s | **0** | 0 |
| `swift test` (debug, ılık) | ✅ 38/38 (boşta) | 1,9 s (test koşusu 0,73 s) | 0 | 0 |
| `swift test` (ilk koşu, arka planda release build varken) | ❌ **1 hata** | 3,1 s | 0 | 0 |

**Kanıt (soğuk build):**

```
$ swift build -c release --scratch-path /tmp/qmd-final
[3/5] Compiling QuickMD AppDelegate.swift
[4/5] Linking QuickMD
Build complete! (76.30s)
real	1m16.937s
```

**Değerlendirme:** Ana derleme gerçekten temiz — **0 uyarı, 0 hata**, hem arm64 hem x86_64 hem de macOS 15 hedefiyle. 5.968 satırlık bir AppKit uygulaması için soğuk release derlemesinin ~76 s olması normalin üst bandında ama kabul edilebilir (tek modül, tüm dosyalar tek `swift-frontend` işinde; `.build` 516 MB). `--triple` çapraz derleme sorunsuz: universal `.app` üretimi (`lipo`) CLT ile çalışıyor, bu iyi bir kurulum.

### 1.2 Testler — sayı, süre, kapsam

| Ölçüm | Değer |
|---|---|
| Toplam test | **38** (swift-testing / `import Testing`) |
| `RendererTests` | 23 test (177 satır) |
| `EditorTests` | 15 test (145 satır) — suite `@MainActor` |
| Boşta toplam süre | **0,46–0,73 s** (medyan ~0,55 s) |
| En yavaş test | `largeNoteRendersQuickly` ~1,6 s (11.000 satırlık not, eşik 3 s) |
| İkinci en yavaş | `pathologicalLinesStayFast` ~0,33 s (eşik 1 s) |
| Başarı durumu | Boşta **8/8 koşu geçti**; yük altında **1 kez kırıldı** (aşağıda) |

**Kanıt (başarısız koşu, arka planda release build çalışırken):**

```
✘ Test pathologicalLinesStayFast() recorded an issue at RendererTests.swift:169:9:
  Expectation failed: (time { _ = html(String(repeating: "[a](", count: 5_000)) } → 1.0266250371932983) < (1 → 1.0)
✘ Suite RendererTests failed after 1.596 seconds with 1 issue.
✘ Test run with 38 tests failed after 1.597 seconds with 1 issue.
```

Aynı test boşta 8/8 geçti (0,33 s) → **duvar saati tabanlı eşik, makine yüküne duyarlı**: CI'da flaky test üretir. (`largeNoteRendersQuickly` 1,6 s / 3 s eşiği de aynı riski taşır.)

### 1.3 Test kapsamı — dosya bazında eşleme

Testler yalnızca iki dosyada; 24 kaynak dosyadan **yalnızca 3'ü doğrudan** test ediliyor (MarkdownHTML, MarkdownTextView, Outline), **6'sı yalnızca dolaylı** (editör/renderer üzerinden), **15'inin hiçbir test kapsaması yok**.

| Kaynak dosya | Satır | Test durumu | Not |
|---|---|---|---|
| `MarkdownHTML.swift` | 945 | ✅ 23 test (dolaylı) | ATX/setext, liste/görev, tablo, fence, front matter, inline, sanitizer, kaçış, link/URL, hız |
| `MarkdownTextView.swift` | 511 | ✅ 15 test (dolaylı) | Return/Tab, liste, tablo, görev, caret bağlama |
| `SmartEditing.swift` | 45 | 🟡 dolaylı | editör testleri üzerinden |
| `Outline.swift` | 116 | ✅ 1 test | `outlineMatchesTheRenderer` |
| `MarkdownDocument.swift` | 118 | 🟡 1 test | yalnızca CRLF oku/yaz (`crlfFilesEditInLFAndSaveAsCRLF`) |
| `MarkdownStyler.swift` | 848 | 🟡 dolaylı | satır başına stil testi yok; yalnızca "linear time" var |
| `TableEditing.swift` | 122 | 🟡 dolaylı | hücre hizalama çıktısı test edilmiyor |
| `MarkdownWrap.swift` | 59 | 🟡 dolaylı | 1 vaka (`typingOverASelectionWraps`) |
| `Checkbox.swift` | 55 | ❌ | tick karakteri / aralık mantığı |
| `FolderAccess.swift` | 79 | ❌ | sandbox bookmark/`canRead` path kontrolü |
| `Settings.swift` | 110 | ❌ | UserDefaults kalıcılığı, şablon başına font |
| `Template.swift` | 99 | ❌ | font/size/measure eşlemeleri |
| `FontFace.swift` | 107 | ❌ | font çözümleme / fallback |
| `Theme.swift` | 250 | ❌ | palet eşlemeleri (dark/light × şablon) |
| `SyntaxHighlighter.swift` | 144 | ❌ | tokenizer (regex/anchor mantığı) |
| `HorizontalRuleLayoutManager.swift` | 274 | ❌ | setext/HR/checkbox çizimi (saf fonksiyonlar test edilebilir) |
| `SidePanes.swift` | 289 | ❌ | önizleme `quickmd:` şeması (path traversal savunması!), görev mesajı |
| `DocumentWindowController.swift` | 425 | ❌ | önizleme debounce, toolbar, paylaşım |
| `MainMenu.swift` | 225 | ❌ | menü yapısı / kısayollar |
| `SettingsWindow.swift` | 343 | ❌ | — |
| `EditorViewController.swift` | 311 | 🟡 dolaylı | stil/restyle yolu test edilmiyor |
| `AppDelegate.swift` | 132 | ❌ | — |
| `Starters.swift` | 311 | ❌ | şablon başlangıç metinleri |
| `main.swift` | 51 | ❌ | `--render` CLI yolu |

**Kritik testsiz alanlar (etki sırasıyla):** belge G/Ç'nin tamamı (yalnızca tek CRLF vakası; UTF-16/Latin-1 düşüşü, BOM, encoding kaybı, `presentedItemDidChange` yeniden yükleme yok), önizleme URL şeması (`PreviewScheme` path traversal → *güvenlik*), undo/redo davranışı (yalnızca `undoManager?.removeAllActions()` var, geri alma testi yok), tablo düzenleme çıktıları, `Settings`/`Theme` kalıcılığı, `main.swift --render` sözleşmesi.

---

## 2. Swift 6 hazırlığı ve eşzamanlılık

### 2.1 Ölçülen envanter

| Ölçüm | Değer | Kanıt |
|---|---|---|
| `@MainActor` anotasyonu | **14** (13 tip + 1 metot), **9 dosya** | `grep -rn '@MainActor' Sources` |
| Açıkça `@MainActor` tipler | 13 (Settings, Theme.resolve, MainMenu, FolderAccess, NoteLinks, MarkdownWrap, MarkdownStyler, Style, AppDelegate, QuickMDDocumentController, SettingsWindowController, SettingsPane + 2 alt sınıf) | yukarıdaki grep |
| Örtük `@MainActor` tip (AppKit tabanı) | ~11 (`NSTextView`, `NSView`, `NSViewController`×4, `NSWindowController`, `NSDocument`, `NSLayoutManager`, `NSDocumentController`) | sınıf bildirimleri |
| `nonisolated` | **2** (yalnızca `MarkdownStyler` içinde: `lineHeightMultiple`, `bodyParagraph()`) | `MarkdownStyler.swift:23,62` |
| `Sendable` uyumu | **0** | `grep -rn Sendable Sources Tests` → boş |
| `@unchecked Sendable` | **0** | — |
| Global mutable static | 3+ (`FolderAccess.granted`, `MarkdownHTML.cache`, `Settings.defaults`, `PreviewScheme.stopped`) | `FolderAccess.swift:11`, `MarkdownHTML.swift:672` |
| `Task` / `async` / `await` | **0** | `grep` — uygulama tamamen senkron + GCD |
| `DispatchQueue.main.async` | 7 | — |
| Arka plan işi | 1 yer: önizleme kaynak sunumu (`DispatchQueue.global(qos:.userInitiated)`, `SidePanes.swift:191`) | dosya okuma; render **değil** |

### 2.2 `.swiftLanguageMode(.v5)` kilidinin nedeni — ölçüldü

Depo kopyasında **yalnızca** `Package.swift` içindeki `.v5` → `.v6` değiştirilip derlendi:

| Ölçüm | Sonuç |
|---|---|
| Hata | **137** (temiz scratch build; aynı teşhisin `note` satırları hariç) |
| Uyarı | **59** |
| Hatalı dosya sayısı | **5**: `MarkdownDocument.swift` **45**, `MarkdownHTML.swift` 7, `EditorViewController.swift` 7, `DocumentWindowController.swift` 6, `SettingsWindow.swift` 3 |

**Hata kategorileri (temiz build çıktısından otomatik sınıflandırma, toplam 137):**

| # | Kategori | Adet |
|---|---|---|
| 1 | `main actor-isolated property … can not be mutated from a nonisolated context` | 48 |
| 2 | `main actor-isolated property … can not be referenced from a nonisolated context` | 36 |
| 3 | `call to main actor-isolated instance method … in a synchronous nonisolated context` | 24 |
| 4 | `static property … is not concurrency-safe because non-'Sendable' type …` | 8 |
| 5 | `main actor-isolated method … cannot be used to satisfy nonisolated requirement` | 8 |
| 6 | `cannot access property … with a non-sendable type … from nonisolated deinit` | 6 |
| 7 | `call to main actor-isolated static method …` | 6 |
| 8 | `emit-module command failed` (özet satırı) | 1 |

**Uyarı kategorileri (59):** 25 × `upcoming feature 'BareSlashRegexLiterals' is already enabled as of Swift version 6`, 16 × `instance method … nearly matches optional requirement … of protocol 'WKNavigationDelegate'` (delegate imza eşleşmesi), 6 × `reference to captured var in concurrently-executing code`, 6 × `capture of non-Sendable type in a closure`, 6 × `add … to treat …-related errors from module … as warnings`.

**Asıl engel (mimari, mekanik değil):** `MarkdownDocument` (NSDocument) `@MainActor`; ancak `read(from:ofType:)` ve `data(ofType:)` protokol gereği **nonisolated** ve metin durumuna erişiyor:

```
MarkdownDocument.swift:74: error: main actor-isolated property 'text' can not be mutated from a nonisolated context
MarkdownDocument.swift:83: error: … 'text' / 'encoding' …
MarkdownDocument.swift:87: error: main actor-isolated property 'text' can not be referenced from a nonisolated context
```

Yani Swift 6'ya geçiş "anotasyon ekle" işi değil: belge G/Ç'nin hangi yürütücüde çalıştığı yeniden tasarlanmalı (text'i `nonisolated` bir kutuya/lock'a taşımak ya da `read`/`data` içinde ana aktöre atlamak). Buna `Settings`/`FolderAccess`'in UserDefaults tabanlı static erişimi, `deinit`'te non-Sendable `Any?` observer erişimi (`SettingsWindow.swift:67`) ve `BareSlashRegexLiterals`'ın Swift 6'da zaten açık olması (25 uyarı: "upcoming feature … is already enabled as of Swift version 6") ekleniyor.

### 2.3 Geçiş için ölçülebilir yol haritası

1. `.v5` modunda `-strict-concurrency=complete` (veya `enableUpcomingFeature("StrictConcurrency")`) ile **uyarı** üret; hatasız derleme korunur.
2. `Sendable` değer tipleri (`FontFace`, `Template`, `Theme`, `Starter`, `CalloutKind`, `TextStats.Counts`) — bunlar saf enum/struct, kolay.
3. Statik mutable durumu `@MainActor`'a al veya `nonisolated(unsafe)` + doküman; `FolderAccess.granted` için `@MainActor` + `nonisolated` okuma kopyası.
4. `MarkdownHTML.cache` (`NSCache`, thread-safe ama `Sendable` değil) → `@MainActor` sarmalayıcı veya `nonisolated(unsafe)` + gerekçe.
5. `MarkdownDocument`: `read`/`data`'yı `nonisolated` yap ve metin durumunu `OSAllocatedUnfairLock`/`NSLock` korumalı bir `DocumentText` kutusuna taşı; ana aktör erişimi bu kutu üzerinden.
6. `deinit`'lerde observer'ı `nonisolated` bir kopya üzerinden kaldır (`observer` alanını `@MainActor` olmayan bir depoya taşı).
7. Ancak 1–6 tamamlanınca `.v6`; aksi halde kilit bilinçli bir teknik borçtur (aşağıda B2).

**Risk notu:** `.v5` kilidi, Swift 6.1 toolchain'inde sorunsuz; ancak Xcode/Swift 7'ye geçişte bu borç faizi artar ve bugün **hiçbir eşzamanlılık denetimi yok** (Sendable 0). Buna rağmen uygulamanın tek iş parçacıklı tasarımı (render hariç her şey main) veri yarışı riskini pratikte düşük tutuyor.

---

## 3. Deprecated API taraması ve macOS 13 deployment target maliyeti

| Ölçüm | Sonuç |
|---|---|
| Hedef 13 ile derleme uyarıları | **0** deprecation uyarısı |
| Hedef 15 (`--triple arm64-apple-macosx15.0`) ile derleme | **0 uyarı, 0 hata** |
| `NSFont.font(withName:)` | 0 kullanım (modern `NSFont(name:size:)`/`NSFontManager.font(withFamily:traits:weight:size:)` kullanılıyor) |
| `try! / as! / fatalError` | 14 / 6 / 4 |

**Sonuç: kullanımda deprecated API yok** — hem 13 hem 15 hedefinde uyarısız derleniyor. `try!`'lerin tamamı statik regex/`NSCache` kurulumu (`MarkdownStyler.swift:29-58`, `SyntaxHighlighter.swift:45`, `MarkdownHTML.swift:677`), `as!`'ler `NSMutableParagraphStyle`/`NSPrintInfo` kopyası (`MarkdownStyler.swift:331,748,755,775,779`, `DocumentWindowController.swift:331`), `fatalError`'lar yalnızca `init(coder:)` (`SettingsWindow.swift:33`, `DocumentWindowController.swift:101`, `EditorViewController.swift:39,310`). Bunlar kabul edilebilir fail-fast noktaları; ancak **regex'lerin derlendiğini doğrulayan bir test yok** — bozuk bir desen uygulamayı ilk kullanımda çökertir (`try!`).

**macOS 13 hedefinin maliyeti:** API erişimi açısından pratikte sıfır (0 deprecation + 0 availability hatası). Tek gerçek maliyet **TextKit 2**: editör TextKit 1 üzerinde kurulu (`HorizontalRuleLayoutManager: NSLayoutManager` + `allowsNonContiguousLayout`, `EditorViewController.swift:30-34`). TextKit 2 (`NSTextLayoutManager`) macOS **12**'den beri var — yani deployment target engel değil, **mimari tercih**. TextKit 2'ye geçiş, tam belge yeniden stilize etme maliyetini ve layout manager alt sınıfındaki çizim kancalarını doğrudan etkiler; bu yüzden hedefi yükseltmek tek başına bir kazanç sağlamaz.

**Fırsatlar (öncelik sırası):** (a) TextKit 2'ye kademeli geçiş için ayrı bir spike; (b) `Settings` için SwiftUI `Settings` scene (macOS 13+ zaten yeterli); (c) `.xcstrings` kullanımı — ancak proje SPM olduğu ve Xcode kurulu olmadığı için bugün uygulanamaz (bkz. B1/M9). **Hedefi 14/15'e çıkarmak için acil bir gerekçe yok**.

---

## 4. Performans riskleri (ölçümlü)

### 4.1 Regex derleme maliyeti — **risk yok (doğrulandı)**

| Kontrol | Sonuç |
|---|---|
| Her çağrıda `NSRegularExpression` oluşturuluyor mu? | **Hayır.** `MarkdownStyler`'da 12 desen `private static let` (`MarkdownStyler.swift:29-58`), `SyntaxHighlighter`'da 1 (`:45`), `MarkdownHTML`'de 10 statik desen + `regex()` fabrikası ve `static let cache = NSCache<…>` (`:672-680`) |
| `try! NSRegularExpression` fonksiyon gövdesinde | Yalnızca `MarkdownHTML.regex()` içinde, cache miss'te (`:677`) |
| Toplam regex arama çağrısı | 24 site (`firstMatch/matches/enumerateMatches`) |

**Sonuç:** "her tuş vuruşunda regex yeniden derleme" iddiası **bu kod tabanında geçerli değil** — doğru yapılmış. (Buna karşın `MarkdownHTML` cache'i `NSCache` olduğu için Swift 6'da `Sendable` değil; bkz. §2.2.)

### 4.2 Her tuş vuruşunda tam belge mi işleniyor?

Kod, paragraf-yerel restyle yapıyor (`MarkdownStyler.restyle(…edited:)`, `EditorViewController.textDidChange` → `restyle(edited:)`) — yani **tam belge her tuşta yeniden stilize edilmiyor**. Ancak restyle yolu yine de her vuruşta **tam belge üzerinde iki O(n) iş** yapıyor:

1. `blockFenceLineStarts(in:)` — belgenin tamamını `[unichar]` tamponuna kopyalayıp satır satır tarar (`MarkdownStyler.swift:569-600`);
2. `ns as String` — tam metin kopyası (`MarkdownStyler.swift:132`; kodun kendi yorumu: "every `as String` is a full copy").

Ayrıca düzenlenen blok fence sınırını değiştirdiyse **tüm belge** yeniden stilize edilir (`blocksUnchanged`, `:619`).

**Ölçüm (release, sentetik belge, /tmp kopyasında benchmark testi):**

| Belge | Satır | Tam restyle | Tuş başına artımlı restyle | Sadece fence taraması |
|---|---|---|---|---|
| 64,8 KB | ~2.600 | **292 ms** | **1,21 ms** | 0,08 ms |
| 259,2 KB | ~10.400 | **1.005 ms** | **7,32 ms** | 0,27 ms |

Yorum: tam restyle **açılışta** (`EditorViewController.load` → `restyle()`) ve **tema/font/şablon değişiminde** (`applySettings()` → `restyle()`, `EditorViewController.swift:250`) çalışır. Tuş başına maliyet 65 KB'de sorunsuz, 260 KB'de 7,3 ms (16,7 ms kare bütçesinin yarısı) — büyük notlarda yazma gecikmesi büyümeye devam eder (~1 MB'de ~30 ms beklentisi).

### 4.3 Ana iş parçacığında ağır iş — önizleme

`schedulePreview()` 0,25 s debounce sonrası `renderPreview()` çalışır (`DocumentWindowController.swift:136-158`); `PreviewViewController.show(markdown:)` **`MarkdownHTML.render` + `page` + `loadHTMLString` işini ana iş parçacığında** yapar (`SidePanes.swift:71+`). Render saf bir fonksiyon olmasına rağmen arka plana alınmamış.

**Ölçüm (release):**

| Belge | `MarkdownHTML.render(interactive:true)` | HTML gövdesi | `page()` sarmalama |
|---|---|---|---|
| 64,8 KB | **131–160 ms** | 173 KB (2,7×) | 10–14 ms |
| 259,2 KB | **565–624 ms** | 694 KB (2,7×) | 36–37 ms |

Yani önizleme açıkken 260 KB'lik bir notta yazmayı 0,25 s bırakmak ana iş parçacığında **~0,6–1,0 s'lik bir takılma** üretir; buna `loadHTMLString` + WebKit yeniden düzenlemesi eklenir. (Deponun kendi testi `largeNoteRendersQuickly` 11.000 satırı 1,6 s'de render ediyor ve bunu "hızlı" sayıyor — bu bir kabul eşiği, hedef değil.)

### 4.4 Sızıntı riskleri: observer / KVO / closure / timer

| Kontrol | Ölçüm | Değerlendirme |
|---|---|---|
| `Timer` | **0** | Timer/invalidate sızıntısı yok |
| `NotificationCenter.addObserver` | 5 ekleme / 3 `deinit` + 1 explicit kaldırma | `SettingsWindow.swift:61,67`, `DocumentWindowController.swift:89,104`, `EditorViewController.swift:42,102` — hepsi doğru |
| KVO (`NSApp.observe`) | 1 (`AppDelegate.swift:17`) | `NSKeyValueObservation` AppDelegate ömrü boyunca yaşıyor; sızıntı değil |
| `[weak self]` | **18** | Tüm escaping closure'lar weak (`DocumentWindowController.swift:80-87`, `EditorViewController.swift:168`, `SidePanes.swift:193`) |
| `[unowned self]` | 0 | — |
| `self` yakalayan weak'siz closure | 15 ham eşleşme | İncelendi: hepsi non-escaping/inline (`filter { $0 !== self }`, `init(owner:)`, property getter) — **gerçek sızıntı yok** |
| `DispatchWorkItem` iptali | `idleWork?.cancel()` / `previewWork?.cancel()` | Doğru; iptal edilen iş tetiklenmiyor |
| `PreviewScheme.stopped` set'i | `stop()` ekler, tamamlanınca siler (`SidePanes.swift:196,213`) | Sınırlı büyüme; iptal edilip hiç tamamlanmayan görevler kalıcı iz bırakabilir (düşük) |

**Sonuç:** Bellek sızıntısı tarafı temiz; asıl performans riski §4.2/§4.3'teki ana iş parçacığı maliyeti.

---

## 5. Proje hijyeni

### 5.1 Git durumu — **en ciddi bulgu**

| Ölçüm | Değer |
|---|---|
| Commit sayısı | **3** (12:59, 13:09, 13:35 — 36 dakikada) |
| Tag | **0** |
| Remote | **0** (`git remote -v` boş) |
| Branch | yalnızca `main`, upstream yok |
| Takipli dosya | 25 |
| Değiştirilmiş (M) | 20 dosya, **+2.595 / −438** |
| Takipli olmayan (??) | **44 dosya** |
| CI | **yok** (`.github/` yok) |
| CHANGELOG / CONTRIBUTING | **yok** |
| `TODO/FIXME/HACK/XXX` | **0** (temiz) |
| `.DS_Store` (diskte) | 18 — takipli **0**, `.gitignore`'da doğru şekilde var |
| `.build` / `build/` takipte | **hayır** (doğru) |
| Depo boyutu | 972 MB (`.build` 516 MB + `.build-universal` 443 MB — ignore'lu) |

**Kritik:** Çalışma ağacındaki 6 kaynak dosya (`FolderAccess`, `SettingsWindow`, `Starters`, `SyntaxHighlighter`, `TableEditing`, `Template`) ve **tüm test dizini** commit edilmemiş. Commit'li `Package.swift`'de `testTarget` yok:

```
$ git show HEAD:Package.swift        # yalnızca executableTarget var
$ cd /tmp/qmd-head && swift test
Build complete! (70.57s)
error: no tests found; create a target in the 'Tests' directory
```

Yani **temiz bir clone testleri çalıştıramıyor, hatta uygulamanın 6 dosyası eksik** (build çalışıyor çünkü dosyalar ağaçta; clone'da çalışmaz). Ayrıca `Resources/` (5,0 MB: 2 font ailesi, KaTeX, Mermaid, lisansları) ve `Packaging/` (entitlements, PrivacyInfo, Credits) commit edilmemiş ve `.gitignore`'da da değil → taze clone `scripts/build-app.sh` ile `.app` **paketleyemez** (`cp -R "$ROOT/Resources/Fonts"` başarısız olur, `set -e`). `git archive HEAD` çıktısında `Resources/`, `Packaging/`, `Tests/` yok.

**Hijyen artıları:** `.gitignore` kapsamlı (`.build/`, `build/`, `dist/`, `*.app`, `.DS_Store`, `.build-universal/`), diskteki `.DS_Store`/build artefaktları takipte değil. LICENSE tutarlı (MIT; Wisp + QuickMD contributors), README MIT diyor, `Credits.rtf` ve `Resources/{Fonts,katex,mermaid}/…LICENSE` dosyaları mevcut. `Packaging/PrivacyInfo.xcprivacy` ve sandbox entitlements (`app-sandbox`, user-selected read-write, bookmarks, print, network.client) düzgün.

**Küçük hijyen kusurları:**
- `.gitignore`'da `.build-universal/` var ama `build-app.sh --appstore`'un kullandığı **`.build-universal-appstore/` yok** → `git status` gürültüsü (doğrulandı: `NOT IGNORED`).
- Depo kökünde projeyle ilgisiz **`WATCHDOG.yml`** (3 satır, "advisors: … claude-opus-5-5") — takipsiz ama commit'lenmeye hazır duruyor; kaldırılmalı veya ignore'lanmalı.
- `BUILD_NUMBER=$(git rev-list --count HEAD)` (`scripts/build-app.sh:22`) → sürüm numarası sıkıştırılmış commit geçmişine bağlı; tag'siz süreçte release numarası anlamsız.

### 5.2 Kod ölçümleri

| Ölçüm | Değer |
|---|---|
| Kaynak | 24 dosya, **5.968 satır** (590 yorum = %9,8; 604 boş) |
| Test | 2 dosya, 322 satır |
| Tip bildirimi | 18 `class`, 24 `enum`, 12 `struct`, 3 `extension` (57) |
| En uzun fonksiyonlar | `renderBlocks` **198**, `page` **189**, `styleLines` **151**, `styleInline` 94, `MarkdownStyler.init` 90 |
| >80 satır fonksiyon | **5** |
| >50 satır fonksiyon | **14** |
| En büyük dosyalar | `MarkdownHTML.swift` 945, `MarkdownStyler.swift` 848, `MarkdownTextView.swift` 511 |
| Ölü kod (aday) | `MarkdownStyler.fenceLineStarts` (**:563**), `MarkdownStyler.mathFenceLineStarts` (**:605**), `FontFace.isMonospaced` (**:59**) — 3 tanesi hiç çağrılmıyor (grep ile doğrulandı) |
| Duplike 8 satırlık pencere | 1 (anlamlı kopya yok) |

`MarkdownStyler` (848) ve `MarkdownHTML` (945) tek dosyada çok fazla sorumluluk taşıyor; `MarkdownHTML.renderBlocks` (198 satır) ve `page` (189 satır) incelemesi zor. Bu, hata ayıklama/diff maliyetini doğrudan artırıyor ve konu bazlı test yazmayı zorlaştırıyor.

---

## 6. Test edilebilirlik

| Kontrol | Ölçüm | Etki |
|---|---|---|
| XCUITest / UI test hedefi | **0** | Arayüz akışları (open/save, toolbar, preview, menü) otomatik doğrulanamıyor |
| Erişilebilirlik API'leri | **0** (`setAccessibility*`, `accessibilityLabel/Role` hiç yok) | VoiceOver yok; XCUITest'in dayandığı a11y ağacı da yok → UI testi bu haliyle yazılamaz |
| Snapshot testi | 0 | Görsel gerileme yakalanamıyor |
| XCTest kullanımı | 0 (yalnızca swift-testing) | `xcodebuild`/XCTest altyapısından bağımsız olması iyi; ama XCUITest swift-testing'e taşınamıyor |
| Xcode kurulu mu? | **Hayır** (CLT only) → `xcodebuild` hata veriyor | Bu makinede UI testi/Instruments imkânsız; CI'da `macos-14` runner gerekir |
| CI'da çalıştırılabilirlik | Yok; `swift test` macOS + AppKit ister → yalnızca macOS runner | GitHub Actions `macos-14`, ~10–15 dk; matris: `swift test` + `swift build -c release` + `--triple x86_64` |
| Determinizm | Eşik tabanlı 2 perf testi (§1.2) duvar saatine bağlı; swift-testing suite'leri **varsayılan paralel** (`EditorTests` @MainActor, `RendererTests` paralel) | Yük altında flaky; `pathologicalLinesStayFast` bunu bir kez kanıtladı |
| Test enjeksiyonu | `Settings` doğrudan `UserDefaults.standard` okuyor (`Settings.swift:12`), `MarkdownStyler` statik, `NSDocumentController.shared` | Tercihleri/fontları testte izole etmek mümkün değil; sahte (fake) `Settings` protokolü yok |

**Test edilebilirlik için somut öneriler:** (1) `Settings`/`Theme`/`AppResources` için protokol veya `init(defaults:)` enjeksiyonu; (2) `HorizontalRuleLayoutManager`/`Outline`/`TableEditing`'in saf fonksiyonlarını ayrı test etmek; (3) toolbar/menü öğelerine `accessibilityIdentifier` + `setAccessibilityLabel`; (4) `PreviewScheme` path traversal testi (güvenlik); (5) perf testlerini `XCTMetric`/swift-testing benchmark hedefine taşıyıp CI'da işaretle.

---

## 7. Bulgu özeti (Önem | Kanıt | Etki | Düzeltme)

### Blocker

| # | Bulgu | Kanıt | Etki | Düzeltme |
|---|---|---|---|---|
| **B1** | Testler ve 6 kaynak dosya VCS'te yok; commit'li `Package.swift`'de `testTarget` yok | `git ls-files --others` = 8 swift (6 kaynak + 2 test); `git show HEAD:Package.swift`; `/tmp/qmd-head`'te `swift test` → `error: no tests found` | Temiz clone test çalıştıramaz; 44 dosyalık iş kaybolma riski; CI imkânsız; PR incelemesi gerçek kodu görmez | Tüm ağacı commit'le (testler + 6 kaynak + `Resources/` + `Packaging/`); `git clone` sonrası `swift build -c release && swift test` doğrula; `Resources/` için Git LFS değerlendir |
| **B2** | Swift 6 modu 137 hata ile derlenmiyor; `.v5` kilidi zorunlu teknik borç | `/tmp/qmd-swift6` temiz build: `swiftLanguageMode(.v6)` → **137 error / 59 warning**, 5 dosya (MarkdownDocument 45); 48+36+24 hata `@MainActor`/nonisolated; `MarkdownDocument.swift:74-91` | Gelecekte toolchain yükseltmesi bloke; Sendable/eşzamanlılık denetimi yok | §2.3 yol haritası: önce `.v5` + `StrictConcurrency` uyarıları, sonra `MarkdownDocument` G/Ç yeniden tasarımı, statik mutable durum, `deinit`; en son `.v6` |

### High

| # | Bulgu | Kanıt | Etki | Düzeltme |
|---|---|---|---|---|
| **H1** | Önizleme render + sayfa + `loadHTMLString` ana iş parçacığında; 260 KB'de ~0,6–1,0 s | Bench (release): `render` 565–624 ms @259 KB, 131–160 ms @65 KB; `DocumentWindowController.swift:136-158`; `SidePanes.swift:71+` | Önizleme açıkken büyük notta yazma takılması / plaj topu | `MarkdownHTML.render` saf → `DispatchQueue.global`/`Task.detached`'te render et, sonucu main'de `loadHTMLString`'e ver; mevcut `loadedKey` mekanizmasını artımlı gövde değişimiyle kullan |
| **H2** | Açılışta ve tema/font değişiminde tüm belge yeniden stilize; 260 KB'de ~1,0 s ana iş parçacığı | Bench: tam restyle 292 ms @65 KB, **1.005 ms @259 KB**; `EditorViewController.swift:120,250` | Büyük dosya açılışında donma; tema değişimi hissedilir kilit | Görünür aralığı önce stilize et (`allowsNonContiguousLayout` zaten açık), kalanı arka planda parça parça; veya restyle'ı `Task` ile parçalara böl + ilerleme iptali |
| **H3** | Her tuş vuruşunda O(n) tam belge kopyası + fence taraması; tuş başına 1,2→7,3 ms | Bench: `perEdit` 1,21 ms @65 KB, **7,32 ms @259 KB**; `MarkdownStyler.swift:93,132,569` | Girdi gecikmesi dosya boyutuyla doğrusal büyür (~30 ms/MB) | Fence satır indeksini artımlı güncelle (değişen paragraf dışına dokunma), `ns as String` kopyasını yalnız gerekince al, paragraph dışı taramayı kaldır; `os_signpost` ile ölç |
| **H4** | Duvar saati tabanlı performans testleri flaky | `/tmp/qmd_test.log`: `pathologicalLinesStayFast` **1,0266 s > 1,0 s** (yük altında); boşta 8/8 × 0,33 s | CI'da rastgele kırmızı; gerçek perf regresyonu gürültüde kaybolur | Eşikleri kaldır veya `XCTMetric`/benchmark hedefine taşı; `-c release` + ısınma turu; CI'da perf testlerini ayrı işaretle |
| **H5** | Erişilebilirlik API'si sıfır; XCUITest yazılabilecek a11y ağacı yok | `grep -E 'setAccessibility|accessibilityLabel|isAccessibilityElement' Sources` → **0**; UI test hedefi yok | VoiceOver kullanılamaz; UI otomasyonu imkânsız; App Store kalite beklentisi karşılanmaz | Toolbar/footer/sidebar/checkBox için label+role; layout manager'ın çizdiği checkbox/rule için `NSAccessibilityElement`; ilk XCUITest smoke (aç → yaz → kaydet) |
| **H6** | Sürüm/depo süreci yok: 3 commit, tag yok, remote yok, CI yok, CHANGELOG/CONTRIBUTING yok, 5 MB varlık takipsiz | `git log` (3), `git tag -l` (boş), `git remote -v` (boş), `.github` yok, `git archive HEAD` → Resources/Packaging/Tests yok | Release tekrarlanamaz, App Store paketi taze clone'dan üretilemez, ekip çalışması ölçeklenmez | B1'i düzelt; `v1.0.0` tag; `.github/workflows/ci.yml` (macos-14: build+test); CHANGELOG.md + CONTRIBUTING.md; remote ekle |

### Medium

| # | Bulgu | Kanıt | Etki | Düzeltme |
|---|---|---|---|---|
| **M1** | Swift 6 statik mutable durum / non-Sendable cache | `FolderAccess.swift:11` (`static var granted`), `MarkdownHTML.swift:672` (`NSCache`), `Settings.swift:12`; v6'da 6 "not concurrency-safe" hatası | Gelecekteki eşzamanlılık geçişinin ana engellerinden | `@MainActor` izolasyon + `nonisolated(unsafe)` gerekçeli istisnalar; `MarkdownHTML` cache'ini `@MainActor` sarmalayıcıya al |
| **M2** | Statik `try!` regex'ler test edilmiyor; bozuk desen ilk kullanımda çökertir | 14 `try!`, `MarkdownStyler.swift:29-58`, `MarkdownHTML.swift:677` | Geliştirme sırasında sessiz çökme riski (fail-fast kabul edilebilir, ama test yok) | Başlangıçta `MarkdownStyler`/`MarkdownHTML` regex'lerini derleyen 1 test; desenleri `enum Patterns` altında topla |
| **M3** | Dev dosyalar ve uzun fonksiyonlar | `MarkdownHTML.swift:945`, `MarkdownStyler.swift:848`; `renderBlocks` 198, `page` 189, `styleLines` 151 satır; 5 fonksiyon >80 | İnceleme/diff maliyeti, konu bazlı test zorluğu, merge çakışması | `MarkdownHTML` → `Blocks/Inline/Sanitizer/Page`; `MarkdownStyler` → construct başına dosya; `renderBlocks`/`page`'i alt fonksiyonlara böl |
| **M4** | Metin G/Ç ve güvenlik yüzeyi testsiz | `MarkdownDocument` yalnız 1 CRLF testi; `PreviewScheme` (path traversal), `FolderAccess.canRead`, encoding fallback testi yok | Veri kaybı (encoding/BOM) ve güvenlik regresyonu sessizce geçebilir | UTF-16/Latin-1/BOM/CR-only testleri; `PreviewScheme` için `..` ve medya-dışı uzantı testleri |
| **M5** | Testler izole değil; `Settings` doğrudan `UserDefaults.standard` | `Settings.swift:12`, `MarkdownStyler` statik, testler `EditorViewController()` üzerinden gerçek `NSView` kuruyor | Paralel/CI testlerinde sıra bağımlılığı ve kirlilik | `Settings`/`Theme` için enjeksiyon; `NSUserDefaults(suiteName:)` ile test izolasyonu; suite'leri hedefe göre ayır |
| **M6** | Ölü kod | `MarkdownStyler.fenceLineStarts:563`, `mathFenceLineStarts:605`, `FontFace.isMonospaced:59` — grep'te tek eşleşme | Yanıltıcı API yüzeyi, bakım maliyeti | Kaldır veya kullanan test yaz |
| **M7** | macOS 13 hedefi TextKit 1'e kilitli; TextKit 2 fırsatı kaçıyor | `HorizontalRuleLayoutManager: NSLayoutManager`, `EditorViewController.swift:30-34`; TextKit 2 macOS 12+ | Modern metin düzeni performans/içerik API'leri kullanılamıyor | Ayrı spike: TextKit 2 + `NSTextLayoutManager`; geçiş maliyeti H2/H3 ile birlikte değerlendir |

### Low

| # | Bulgu | Kanıt | Etki | Düzeltme |
|---|---|---|---|---|
| **L1** | `.gitignore` boşluğu + kökte ilgisiz dosya | `.build-universal-appstore` ignore'lu değil (doğrulandı); `WATCHDOG.yml` kökte | `git status` gürültüsü; yanlışlıkla commit riski | `.build-universal-appstore/` ekle; `WATCHDOG.yml`'i kaldır/ignore'la |
| **L2** | Release numarası commit sayısına bağlı, tag yok | `scripts/build-app.sh:22` `git rev-list --count HEAD` | Sürüm izlenebilirliği yok | Semver tag + `VERSION` doğrulaması |
| **L3** | Test-only hack | `EditorTests.swift:21` `nonisolated(unsafe) static var key = 0` | Küçük; test kod kalitesi | Yardımcı sınıfta `finish()`/saklama yerine `withExtendedLifetime` kullan |
| **L4** | Depo içinde 972 MB build artefaktı | `.build` 516 MB, `.build-universal` 443 MB (ignore'lu) | Disk/backup maliyeti, yanlış `git add -A` riski | Temizlik scripti / `swift package clean`; CI'da cache kullan |

---

## 8. İlk 5 düzeltme (sırayla)

1. **B1 — Her şeyi commit'le ve tekrarlanabilirliği kanıtla.** `Tests/`, 6 kaynak dosya, `Resources/`, `Packaging/` commit edilir; temiz bir dizinde `git clone → swift build -c release → swift test` yeşil olana kadar iş bitmez. (Süre: ~30 dk. En yüksek getiri: 44 dosyalık kayıp riski + CI'ya zemin.)
2. **H6 — CI + tag + sürüm süreci.** B1'den hemen sonra `.github/workflows/ci.yml`: `macos-14`, `swift build -c release`, `swift test`, `swift build --triple x86_64-apple-macosx13.0`; `v1.0.0` tag; CHANGELOG/CONTRIBUTING. (Süre: ~1–2 saat.)
3. **H4 — Flaky perf testlerini etkisizleştir.** Eşik tabanlı testleri ana suite'ten çıkar; `-c release` benchmark hedefi + ısınma + medyan; CI'da ayrı, bilgilendirici iş. (Süre: ~1 saat. Etki: CI güvenilirliği; gerçek regresyon görünür olur.)
4. **H1 + H3 — Ana iş parçacığı maliyetini düşür.** Önce önizleme render'ını arka plana al (en büyük tek kazanç, ~0,6–1,0 s → ~0), sonra fence indeksini artımlı yap (tuş başına 7,3 ms → <1 ms hedefi); her ikisi de mevcut testlerle doğrulanabilir. (Süre: 1–2 gün.)
5. **H2 + H5 — Restyle'ı parçala ve erişilebilirliği başlat.** Açılış/tema değişiminde görünür aralık önce, kalanı parçalı; toolbar/footer/sidebar + layout manager çizimlerine a11y label/role ve ilk XCUITest smoke. (H2: 1–2 gün; H5: 2–3 gün, Xcode/CI gerektirir.)

> B2 (Swift 6) bilinçli olarak ilk 5'e alınmadı: bugün çalışmayı engellemiyor, ancak B1/H6 (CI) kurulduktan sonra "StrictConcurrency uyarıları" adımıyla kademeli ilerletilmeli — aksi halde 137 hatayı tek seferde çözmek riskli bir "big bang" olur.

---

## 9. Yeniden üretim komutları

```bash
# Derleme
swift build -c release                                       # 0 uyarı, 0 hata
swift build -c release --scratch-path /tmp/clean             # soğuk: 76,3 s
swift build -c release --triple x86_64-apple-macosx13.0      # 0 uyarı
swift build -c release --triple arm64-apple-macosx15.0       # 0 uyarı (deprecation yok)

# Test
swift test                                                   # 38 test, ~0,5 s (boşta)
swift test --filter pathologicalLinesStayFast                # duvar saati eşiği (flaky)

# Swift 6 (depoya dokunmadan)
cp -R Sources Tests Package.swift /tmp/qmd-swift6/
sed -i '' 's/swiftLanguageMode(.v5)/swiftLanguageMode(.v6)/g' /tmp/qmd-swift6/Package.swift
cd /tmp/qmd-swift6 && swift build                            # 137 error, 59 warning

# VCS hijyeni
git ls-files --others --exclude-standard | wc -l             # 44
git show HEAD:Package.swift                                  # testTarget yok
git archive HEAD | tar -x -C /tmp/qmd-head && cd /tmp/qmd-head && swift test   # error: no tests found

# Statik taramalar
grep -rn '@MainActor' Sources | wc -l                        # 14
grep -rn 'nonisolated' Sources                               # 2
grep -rn 'Sendable' Sources Tests                            # 0
grep -rnE 'setAccessibility|accessibilityLabel' Sources      # 0
grep -rn 'Timer' Sources                                     # 0
grep -rnE 'TODO|FIXME|HACK' Sources Tests                    # 0
git ls-files | grep -E 'DS_Store|\.build|build/'             # 0 (temiz)
```

**Performans ölçümü (depo kopyasında, üretim kodu değiştirilmeden):** `/tmp/qmd-bench` kopyasına `Tests/QuickMDTests/BenchTests.swift` eklenip `swift test -c release --filter Bench` çalıştırıldı; ölçümler §4.2 ve §4.3'te. `MarkdownStyler.restyle`/`MarkdownHTML.render` public API olduğu için üretim koduna dokunulmadı.
