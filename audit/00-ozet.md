# QuickMD — "Gerçek bir Apple macOS uygulaması" olmak için eksikler ve düzeltme planı

**Tarih:** 2026-11-01 · **Kapsam:** `/Users/ihsan/Desktop/macOS_Dev/quickmd` (branch `main`, HEAD `9803cde`; çalışma ağacı kirli: 20 dosya değişmiş + 11 izlenmeyen dosya/dizin)
**Yöntem:** 4 paralel denetim (paketleme · platform/HIG/erişilebilirlik · belge G/Ç/güvenlik · derleme/test/performans), her bulgu kod satırı veya çalıştırılmış komut/deneyle kanıtlandı. Ayrıntı: `audit/01…04` raporları (1.752 satır). Uygulama ayrıca çalıştırılıp menü çubuğu AX ile döküldü, otomatik kaydetme/çakışma senaryoları fiilen test edildi.

---

## 0. Kısa hüküm

**QuickMD zaten gerçek bir native macOS uygulaması.** Swift/AppKit, `NSDocument` mimarisi, evrensel binary (arm64 + x86_64), sandbox entitlement'ları, gizlilik manifesti, geçerli ikon, sıfır derleme uyarısı. "Mac uygulaması mı?" sorusunun yanıtı **evet**; eksik olan şey **"Apple'ın dağıtılabilir bir ürünü"** katmanı.

Dört eksen var ve önem sırası şu:

| Eksen | Durum | Neden önemli |
|---|---|---|
| **1. Dağıtım / sürüm mühendisliği** | ❌ Yok denecek kadar eksik | Uygulama bugün **hiç kimseye verilemez**: imzasız/notarize edilmemiş, depodan yeniden üretilemiyor, App Store hattı hiç çalıştırılmamış |
| **2. Veri güvenliği (sessiz bozulma)** | ⚠️ Çekirdek sağlam, kenar durumlar riskli | Kodlama/satır sonu dönüşümü ve ikili dosya kapısı yok; kullanıcı farkında olmadan dosyası değişebilir |
| **3. Apple vatandaşlığı (HIG)** | ⚠️ İyi bir "editör", eksik bir "Mac uygulaması" | Help menüsü boş, yerelleştirme sıfır, erişilebilirlik sıfır — Apple'ın kendi uygulamalarında bunların hiçbiri böyle değil |
| **4. Performans / mühendislik** | ⚠️ Ölçüldü, sınırları biliniyor | Büyük dosyada ana thread kilidi; Swift 6 kilidi ve CI yokluğu geleceği bağlıyor |

**Blocker sayısı:** Paketlemede 4, veri güvenliğinde 0 (NSDocument zinciri sağlam), platformda 0.

---

## 1. Bugün gerçekten iyi olan (korunmalı, bulgu değil)

Bunlar denetimde **fiilen doğrulandı**; "eksik" listesini okurken kaybetmemek gerekir:

- **Belge çekirdeği sağlam:** autosave-in-place, atomik/safe-save, değişiklik takibi ("Edited" rozeti), ve en önemlisi **kirli belge + dışarıdan dosya değişimi → NSDocument'ın standart çakışma sayfası** ("Save Anyway / Revert / Save As…"). Yani "sessiz veri kaybı" senaryosunun en tehlikelisi çalışmıyor. (Bu makinede elle tekrar üretildi.)
- **Undo bütünlüğü:** 31.024 turluk fuzz'da çökme yok; checkbox/tablo/akıllı düzenleme değişiklikleri undo'ya kaydediliyor.
- **Önizleme güvenliği:** APT yok. 43 XSS payload'ı temiz; sanitizer + nonce'lu CSP + özel URL şeması ile `default-src 'none'`. Ham HTML'de script/iframe/event handler engelli.
- **Derleme kalitesi:** release + x86_64 çapraz derleme **0 uyarı, 0 deprecated API**; 38 test geçiyor; regex'ler statik/cache'li (her tuşta yeniden derleme yok — yaygın iddianın aksine); tüm escaping closure'lar `[weak self]`, observer'lar `deinit`'te kaldırılıyor.
- **Paket hijyeni:** ikon geçerli (16→1024 px, tam Apple 824/1024 ızgarası), `PrivacyInfo.xcprivacy` doğru yerde ve mühürlü, entitlements tutarlı, üçüncü parti framework/helper yok, lisanslar (Inter, Nanum Myeongjo, KaTeX, Mermaid) tam.
- **Kullanıcı deneyimi:** birleşik + özelleştirilebilir toolbar, sekmeler, Find bar + Replace, sürükle-bırak ile göreli link/görsel, ⌘-tık link açma, `controlAccentColor` uyumu, dinamik Show/Hide menü başlıkları, sistem Light/Dark takibi.

---

## 2. P0 — Dağıtımı engelleyen eksikler (bunlar bitmeden "uygulama" yok)

### P0-1 · Depo kendi kendini üretemiyor (en kritik)
`git ls-files` → **25 dosya**; 3 commit. Buna karşılık `Packaging/`, `Resources/` (5 MB font/KaTeX/Mermaid), `Tests/` ve **6 Swift kaynağı** (`FolderAccess`, `SettingsWindow`, `Starters`, `SyntaxHighlighter`, `TableEditing`, `Template`) hiç commit edilmemiş. Temiz klon **derleniyor ama eski 0.1.0'ı** üretiyor; `build-app.sh`'in `--appstore/--sandbox/productbuild` içeren hâli hiçbir commit'te yok.
→ **Düzeltme:** hepsini commit'le; `git status` temiz değilken release build'i durdur; `git clone → swift build → swift test` yeşil olana kadar bitmiş sayılmasın. (~30 dk, en yüksek getiri.)

### P0-2 · Notarization / DMG yolu yok → Gatekeeper reddediyor
`spctl -a -t exec build/QuickMD.app` → **rejected**; imza `adhoc`, `TeamIdentifier` yok. Depoda `notarytool`, `stapler`, `.dmg`, `ditto -c` **hiç geçmiyor**.
→ **Düzeltme:** `--dist` modu: Developer ID Application + `--options runtime` + `--timestamp` → `ditto` zip / `hdiutil` DMG → `notarytool submit --wait` → `stapler staple` → `spctl` doğrulaması. App Store-only gideceksen bu adım yerine README'de kapsamı netleştir.

### P0-3 · Sürüm numarası ve App Store çıktısı güvenilir değil
`CFBundleVersion = git rev-list --count` (build-app.sh:23): shallow clone'da **1**, git'siz ortamda **1**, kirli ağaçta aynı numarayla farklı binary. `security find-identity` → **0 kimlik**, `build/QuickMD.pkg` hiç üretilmemiş, script'in önerdiği `xcrun altool` bu makinede yok.
→ **Düzeltme:** VERSION git tag'inden, BUILD_NUMBER commit'li sayaç/CI run number'dan; format regex'i; `--appstore` öncesi sertifika/profil/bundle-id/`get-task-allow=false`/sandbox entitlement/`pkgutil --check-signature` doğrulamaları.

### P0-4 · CI ve çökme sembolleri yok
`.github/` yok, tag yok, test kapısı yok. dSYM **üretiliyor** (UUID'ler final binary ile eşleşiyor) ama `build/` altına kopyalanmıyor/arşivlenmiyor → sahada çöken sürümün raporu çözülemez.
→ **Düzeltme:** `macos-14` runner'da build+test; dSYM'leri `build/dSYMs/<sürüm>-<build>/` altında `dwarfdump --uuid` eşleşmesiyle arşivle.

### P0-5 · UTI beyanı çakışıyor: vaat edilen uzantılar açılmıyor
Plist `net.daringfireball.markdown`'ı **import** edip `md, markdown, mdown, mkd, mdwn` + `text/markdown` sahipleniyor; sistemde `UTType(filenameExtension:)` → `markdown/mdown/mkd/mdwn` = **`com.looq.*`** (Obsidian), Apple Shortcuts ise aynı UTI'yi `.md, text/x-markdown` ile import ediyor. Yani "QuickMD .markdown açar" vaadi fiilen çalışmıyor.
→ **Düzeltme:** ithal beyanı minimal tut (yalnız `.md`, `text/x-markdown`) veya hiç tag verme; ek uzantılar isteniyorsa kendi **exported** UTI'nle (`com…quickmd.markdown`) tanımla ve `NoteLinks.noteExtensions` ile hizala.

### P0-6 · Info.plist tek doğruluk kaynağı değil
Plist build script içinde heredoc olarak üretiliyor; depoda şablon yok; sürüm formatı ve zorunlu anahtarlar doğrulanmıyor. Ayrıca macOS 26 Liquid Glass ikon beklentisi: `.icns` geçerli ama **ön-maskelenmiş bitmap + gömülü gölge**; Icon Composer `.icon` / `Assets.car` / `CFBundleIconName` yok (zorunluluk doğrulanmadı, Medium).
→ **Düzeltme:** `Packaging/Info.plist` şablonu + `PlistBuddy` ile değer enjeksiyonu + zorunlu anahtar/sürüm lint'i; ikon için katmanlı (maskesiz, gölgesiz) üretim modu.

---

## 3. P1 — Veri güvenliği: sessiz bozulma riskleri (küçük diff, yüksek fayda)

Bunlar "uygulama çalışıyor" hissini bozmaz ama kullanıcının dosyasını haberi olmadan değiştirebilir. Hepsi `/tmp` harness'larıyla **fiilen gösterildi**:

| # | Bulgu | Kanıt (deney) | Etki |
|---|---|---|---|
| P1-1 | Satır sonu dönüşümü **tüm dosyayı** yeniden yazıyor | `a␍␊b␊c␍d` (8 B) → `a␍␊b␍␊c␍␊d` (10 B). Dosyaya tek bir CRLF girmişse bütün dosya CRLF olur | Kullanıcının dokunmadığı satırlar değişir; git diff patlar |
| P1-2 | `lossy` bayrağı yok sayılıyor + sessiz UTF-8 transcode | UTF-8 BOM 12 B → 9 B (kaybolur); CP1254 dosya + emoji → dosyanın tamamı UTF-8'e döner; bozuk UTF-8 → mojibake/çift kodlama | Geri dönüşü zor bozulma |
| P1-3 | İkili dosya kapısı yok | Rastgele 300 B verinin **117/200'ü** "metin" kabul edildi; ilk düzenleme+kayıt içeriği bozar | Yanlış dosya açıldığında sessiz tahribat |
| P1-4 | Boyut sınırı yok, tam-belge işi ana thread'de | 0,5 MB: restyle **5,66 s** / render **7,10 s**; 2 MB: restyle **40,69 s**; 8 MB: >5 dk | Force-quit → autosave penceresinde kayıp riski |
| P1-5 | Uzak görseller varsayılan **açık**, `srcset`/`style` sanitize edilmiyor | CSP `img-src *`; `<img srcset="https://evil/track.gif">` ve `style="background:url(…)"` süzülmüyor | IP ifşası / takip pikseli; `network.client` entitlement'ı bu yüzden gerekli |
| P1-6 | `FolderAccess` dayanıklılığı | Çözülemeyen bookmark kalıcı siliniyor; `stopAccessing` hiç yok (sızıntı); her izinde yinelenen kayıt; `canRead` yol-öneki karşılaştırması symlink/harf duyarlı | "Allow" sonrası bağlantılar sessizce çalışmaz |
| P1-7 | Sürüm tarayıcısı erişilemez | `autosavesInPlace` var, ama File menüsünde `browseDocumentVersions` yok, yalnız "Revert To Saved" | "Browse All Versions" özelliği kullanıcıya kapalı |
| P1-8 | Önizleme dosya servisi denetimsiz | `PreviewScheme` medya yolunu `canRead` denetlemeden servis ediyor; `stopped` set'i hiç temizlenmiyor | Sandbox'ta beklenmedik dosya okuma / sınırsız büyüme |

**Öneri sırası:** (1) kodlama + satır sonu koruması, (2) dosya sağlık kapısı (boyut + NUL/kontrol karakteri) + büyük dosyada arka plan restyle, (3) uzak görsel varsayılan kapalı + `srcset/style` filtresi, (4) FolderAccess düzeltmeleri, (5) sürüm tarayıcısı + sessiz revert bildirimi.

---

## 4. P2 — "Apple'ın kendi uygulaması" hissi: platform vatandaşlığı

Bunlar çalışmayı engellemez; "iyi bir üçüncü parti editör" ile "Apple uygulaması" arasındaki farkı yapan katmandır. Menü çubuğu AX ile döküldü, uygulama çalıştırılarak doğrulandı.

1. **Help menüsü tamamen boş (0 öğe).** Yardım kitabı, "QuickMD Help ⌘?", arama yok. Apple şablonunda Help menüsü asla boş değildir.
2. **Yerelleştirme sıfır.** `.lproj`/`.strings`/`.xcstrings` yok, `String(localized:)` yok, `CFBundleLocalizations` yok; ~146 kullanıcı metni kodda İngilizce sabit. Türkçe sistemde menü çubuğu baştan sona İngilizce (Apple menüsü Türkçe).
3. **Erişilebilirlik sıfır.** `setAccessibilityLabel`/rol tanımı **0**; özel çizilen onay kutuları ve footer istatistiği VoiceOver/klavye dışı. Dahası tema sabitlemesi **Increase Contrast'ı eziyor**, `Reduce Motion`/`Reduce Transparency` hiç okunmuyor. VoiceOver ile uygulama kullanılamaz durumda.
4. **Durum geri yükleme (state restoration) yok.** `applicationSupportsSecureRestorableState = true` beyan ediliyor ama `NSWindowRestoration`/`restorationClass` yok → yeniden açılışta pencereler geri gelmiyor.
5. **Sistem entegrasyonu:** Quick Look önizleme eklentisi yok (Space'e basınca ham markdown), Spotlight indeksleme, App Intents/Shortcuts, Services sağlama, Dock menüsü, Handoff/AppleScript yok.
6. **Menü/kısayol cilası:** File ▸ Open Recent iki kez görünüyor (ikincisi boş); Show/Hide Sidebar (⌃⌘S) ve Show/Hide Toolbar (⌥⌘T) yok; **⌘+ Türkçe Q klavyede ⇧⌘4 (sistem ekran görüntüsü) ile çakışıyor**; "Save…" elipsisli; Export as PDF kısayolsuz; belge proxy ikonu gizlenmiş (sürükle/⌘-tık yol menüsü kayıp); ⌘T "New Tab" (Apple ⌘T'yi Show Fonts'a verir — bilinçli tercih, not).
7. **Settings:** sabit 520 pt genişlik, Appearance'ta açılıyor, örnek metin ham markdown; "Default App for Markdown" uygulama menüsünde (HIG'de yeri Settings).
8. **Yazdırma tutarsızlığı:** `MarkdownDocument.printOperation` ham metni yazdırıyor, File ▸ Print ise render edilmiş sayfayı → iki farklı çıktı.

---

## 5. P3 — Performans ve mühendislik (ölçüldü)

- **Önizleme render'ı ana thread'de:** 65 KB → 131–160 ms; 259 KB → **565–624 ms**. Yazma duraklamalarında takılma.
- **Tam restyle ana thread'de:** 65 KB → 292 ms; 259 KB → **1.005 ms** (açılış/tema değişimi).
- **Her tuş vuruşunda 2 × O(n) iş:** full-doc fence taraması + `ns as String` kopyası → 65 KB'de 1,21 ms, 259 KB'de **7,32 ms**.
- **Swift 6 kilidi:** `.swiftLanguageMode(.v5)`; temiz v6 build **137 hata** (asıl engel: `NSDocument`'ın nonisolated `read/data`'sının `@MainActor` metin durumuna erişmesi). Sendable 0.
- **Test/CI:** 38 test var (Renderer 23, Editor 15) ama belge G/Ç, undo, tablo düzenleme, sanitizer test edilmiyor; duvar saati tabanlı perf testi **flaky** (yük altında 1,0266 s > 1,0 s eşiği kırıldı). XCUITest/erişilebilirlik testi yok, makinede Xcode da yok (yalnız CLT).
- **Dosya boyutları:** `MarkdownHTML` 945, `MarkdownStyler` 848 satır (`renderBlocks` 198, `page` 189, `styleLines` 151 satır) — bölünmeye hazır. 3 ölü fonksiyon.
- **Depo:** 3 commit, 0 tag, 0 remote, CI yok, CHANGELOG/CONTRIBUTING yok, 972 MB build artefaktı.

---

## 6. Yol haritası (önerilen sıra)

**Dalga 1 — "Dağıtılabilir olsun" (≈2–3 gün, en yüksek getiri)**
1. Her şeyi commit'le; `git clone` + build + test yeşil doğrula. *(P0-1)*
2. Sürüm tek kaynağa: git tag → VERSION, sayaç/CI → BUILD_NUMBER, format doğrulaması. *(P0-3)*
3. CI: build + test + dSYM arşivi. *(P0-4)*
4. `--dist` (notarization + staple + DMG/zip) **veya** App Store: sertifika/profil + pkg + preflight doğrulamalar. *(P0-2, P0-3)*
5. UTI beyanını düzelt, Info.plist'i şablona taşı. *(P0-5, P0-6)*

**Dalga 2 — "Kullanıcının dosyasına güven" (≈3–5 gün)**
Kodlama + satır sonu koruması → dosya sağlık kapısı ve boyut sınırı → büyük dosyada arka plan restyle/render → uzak görsel varsayılan kapalı → FolderAccess + sürüm tarayıcısı. *(P1-1…P1-8)*

**Dalga 3 — "Apple gibi hissettirsin" (≈1–2 hafta)**
Help kitabı → yerelleştirme altyapısı (TR + EN, `.xcstrings`) → erişilebilirlik paketi (etiket/rol, Increase Contrast/Reduce Motion/Reduce Transparency) → durum geri yükleme → menü/kısayol cilası → Settings cilası → Quick Look eklentisi, Services, Dock menüsü, Spotlight/App Intents.

**Dalga 4 — sürekli**
Önizleme render'ını arka plana al + fence indeksini artımlı yap (tuş başına 7,3 ms → <1 ms hedefi) → flaky perf testlerini `XCTMetric`'e taşı → Swift 6 kademeli geçiş (önce `StrictConcurrency` uyarıları) → `MarkdownHTML`/`MarkdownStyler` böl → belge G/Ç ve güvenlik testlerini ekle.

**App Store'a gireceksen ek olarak (koda bağlı olmayan zorunluluklar):** gizlilik politikası URL'si, destek URL'si, ekran görüntüleri, yaş derecelendirmesi ve **`network.client` entitlement'ı için inceleme notu** ("ağ yalnızca kullanıcı notlarındaki uzak görselleri göstermek için; uygulama kendi başına istek atmaz").

---

## 7. Ayrıntılı raporlar

| Rapor | İçerik | Bulgular |
|---|---|---|
| [`audit/01-packaging.md`](01-packaging.md) | Paketleme, imzalama, notarization, App Store, ikon, dSYM, UTI | 4 Blocker · 5 High · 7 Medium · 8 Low |
| [`audit/02-platform.md`](02-platform.md) | Menü çubuğu (AX dökümü), pencere/sekmeler, erişilebilirlik, yerelleştirme, sistem entegrasyonu | 4 High · 8 Medium · 8 Low |
| [`audit/03-runtime.md`](03-runtime.md) | NSDocument, kodlama/satır sonu, büyük/ikili dosya, sandbox bookmark'ları, önizleme güvenliği, undo | 5 High · 6 Medium · 9 Low |
| [`audit/04-quality.md`](04-quality.md) | Derleme/test ölçümleri, Swift 6, deprecated API, performans, depo hijyeni | 2 Blocker · 6 High · 7 Medium · 4 Low |

> Her raporda bulgu başına **kanıt (dosya:satır / komut çıktısı)**, **kullanıcı etkisi** ve **somut düzeltme** (kod/script/plist taslağı) var; ayrıca kendi içinde "ilk 5 düzeltme" bölümü. Doğrulanamayan iddialar açıkça "doğrulanmadı" olarak işaretlendi.
