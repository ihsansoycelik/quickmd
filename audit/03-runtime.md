# 03 — Çalışma Zamanı Denetimi: Belge Yaşam Döngüsü, Dosya G/Ç, Önizleme

Kapsam: çalışma ağacı (HEAD `9803cde` + commit'lenmemiş değişiklikler), `Sources/QuickMD/*.swift`,
`Packaging/QuickMD.entitlements`, `scripts/build-app.sh`. Ortam: macOS 15.7.9 (arm64), Swift 6.1.2.
Yöntem: satır satır kod okuma + `/tmp`'de **kaynağın kopyasıyla** derlenen harness'larla davranış deneyleri ve
ölçümler; kaynak kod değiştirilmedi (bkz. §8).

## 0. Sonuç özeti

**Blocker bulunmadı.** NSDocument çekirdeği (autosave-in-place, safe-save/atomik yazma, çakışma yönetimi,
değişiklik takibi) fiilen doğrulandı ve çalışıyor; "kirli belge + dış değişiklik" senaryosunda **veri kaybı
yok** — standart çakışma sayfası çıkıyor. En yüksek riskler belge çekirdeğinde değil: kodlama/satır-sonu
dönüşümü (sessiz yeniden kodlama), dosya boyutu kapısının olmaması (ana thread'de saniyelerce/dakikalarca
dondurma → force-quit → kayıp) ve önizlemede uzak görsellerin varsayılan açık olması (gizlilik).

| # | Önem | Bulgu |
|---|------|-------|
| H1 | High | Mixed/CRLF satır sonları tüm dosyayı yeniden yazar (tek CRLF → tüm dosya CRLF) |
| H2 | High | `lossy` yok sayılıyor; geçersiz UTF-8/legacy kodlama → mojibake + sessiz UTF-8 transcode |
| H3 | High | Boyut sınırı yok; tam-belge restyle/render ana thread'de: 0,5 MB ≈ 5,7 s, 2 MB ≈ 40,7 s |
| H4 | High | İkili dosya kapısı yok: rastgele 300 B verinin %58'i "metin" olarak kabul edildi |
| H5 | High | Önizlemede uzak görseller varsayılan açık (`img-src *`); `srcset`/`style` sanitize edilmiyor |
| M1 | Medium | `FolderAccess.restore()` çözülemeyen bookmark'ı kalıcı olarak siliyor |
| M2 | Medium | `startAccessing`/`stopAccessing` dengesizliği + her izinde yinelenen bookmark kaydı |
| M3 | Medium | `canRead` yol-öneki karşılaştırması: symlink/harf duyarlılığı → izin verildiği hâlde "yok" |
| M4 | Medium | `autosavesInPlace` var; `browseDocumentVersions` menüde yok → sürüm tarayıcısı erişilemez |
| M5 | Medium | `PreviewScheme` `canRead` denetlemiyor: herhangi bir medya yolu web view'a servis ediliyor |
| M6 | Medium | Varsayılan dağıtım (`--install`/release) sandbox'sız; güvenlik profili MAS sürümünden farklı |
| L1 | Low | `presentedItemDidChange` mtime `>` kapısı eşit/eski mtime'lı değişiklikleri kaçırıyor |
| L2 | Low | `try? revert` hataları yutuluyor; kullanıcıya geri bildirim yok |
| L3 | Low | CRLF yapıştırmada async `insertText` + bayat `NSRange` (çökme olasılığı — doğrulanmadı) |
| L4 | Low | `load()` tüm undo geçmişini siliyor (dış değişiklik = undo kaybı) |
| L5 | Low | Şablonda `updateChangeCount(.changeDone)` undo kaydı olmadan — geri alınamaz |
| L6 | Low | CSP kaynak listesinde `file:` var (derinlemesine savunma deliği) |
| L7 | Low | `PreviewScheme.stopped` set'i hiç temizlenmiyor (sınırsız büyüme) |
| L8 | Low | `Settings` sürüm/migration yok (bozuk değerde çökme yok, sessiz varsayılana dönüş var) |
| L9 | Low | Özel KVC `drawsBackground` yalnız `#if !APPSTORE` ile korunuyor (kapı bozulursa red riski) |

## 1. NSDocument yaşam döngüsü

### 1.1 Çalışıyor (doğrulandı) — bu maddelere bulgu yazmayın

`autosavesInPlace = true` (MarkdownDocument.swift:17); `write(to:)` ezilmediği için AppKit'in coordinate'li
**safe-save** yolu (geçici dosya + yer değiştirme, izin/Finder bilgisi kopyalama, yedek/versiyon koruması)
devrede (introspection: `_coordinateReadingContentsAndWritingItemAtURL:`, `_checkFileModificationDateBeforeSavingToURL:`,
`_handleConflicts`). **Değişiklik takibi çalışıyor** (Edited rozeti; undo manager üzerinden otomatik — change-count
eksikliği bulgusu yoktur). **Autosave-in-place çalışıyor** (~10–30 s; deneyde 13–15 s). **Kirli belge + dış
değişiklik**: çakışma sayfası (Save Anyway / Revert / Save As…) çıkıyor, autosave kullanıcı kararına kadar
duruyor → veri kaybı yok (deneyde `window.attachedSheet` bir `_NSAlertPanel`'e bağlandı, `data(ofType:)`
çağrılmadı). **Temiz belge + dış değişiklik**: sessiz `revert(toContentsOf:)` (MarkdownDocument.swift:101–110 +
`!isDocumentEdited`) — doğru davranış; L1/L2 yalnız kenar durumları.

### 1.2 [M4][Medium] Sürüm tarayıcısı erişilemez

**Kanıt:** `MainMenu.swift:82` yalnız `Revert To Saved`; başka sürüm tarayıcı girişi yok. `autosavesInPlace = true`
(MarkdownDocument.swift:17) → `preservesVersions` `true` (SDK `NSDocument.h:448–452`), yani sürümler
**saklanıyor**, ama AppKit'in genel eylemi `NSDocument.browseDocumentVersions(_:)` (`NSDocument.h:454–456`,
"Browse Saved Versions" menü öğesi) hiçbir yere bağlanmamış.
**Etki:** Yanlış kaydetme/üzerine yazma sonrası eski sürüme dönmenin keşfedilebilir yolu yok.
**Düzeltme:** `menu.addItem(item("Browse Saved Versions…", #selector(NSDocument.browseDocumentVersions(_:))))`
(hedef First Responder); `revertDocumentToSaved:` öğesi kalsın.

### 1.3 [L1][Low] mtime `>` kapısı bazı dış değişiklikleri kaçırıyor

**Kanıt:** `MarkdownDocument.swift:104–108` — `... let known = self.fileModificationDate, modified > known else { return }; try? self.revert(toContentsOf: url, ...)`
**Doğrulandı (deney):** Dosya `git checkout`, `rsync -t`, bulut geri yükleme gibi **eşit veya daha eski** mtime
ile yazıldığında `modified > known` false kalıyor; editör eski içerikte, disk yeni içerikte kalıyor. Kullanıcı
ekranda gördüğü metni düzenleyip kaydederse hiç görmediği disk sürümünün üzerine yazar.
**Düzeltme:** `modified != known` ile çakışma say + kullanıcıya bildir (`.documentChangedOnDisk` post'u + bant).

### 1.4 [L2][Low] `try?` geri yükleme hatalarını yutuyor

**Kanıt:** `MarkdownDocument.swift:108` — `try? self.revert(...)`. Okuma başarısızsa (silinmiş dosya, sandbox
reddi, kodlama hatası) kullanıcı hiçbir şey görmez; editör eski içerikte kalır, sonraki otomatik kayıt bunu
diske yazabilir. **Düzeltme:** `do/catch` + `presentError`; hata sonrası belgeyi uyarı durumuna al.

### 1.5 Diğer notlar

- **L5:** `Starters.swift:299–304` şablon metnini `updateChangeCount(.changeDone)` ile kirli işaretliyor; undo
  kaydı olmadığı için şablon metni Cmd-Z ile geri alınamaz (deney: elle `changeDone` sonrası `undo()` sayacı
  sıfırlamıyor).
- `read(from data:)` yalnız veri tabanlı okuma (`MarkdownDocument.swift:72`) → dosya tamamen RAM'e alınır,
  `canConcurrentlyRead` varsayılan `false` (§3). Silme/taşıma için özel handler yok; NSDocument varsayılanları
  devrede, ayrıca sorun görülmedi.

## 2. Kodlama / satır sonu / BOM / ikili dosya

### 2.1 [H1][High] Satır sonu dönüşümü tüm dosyayı yeniden yazıyor

**Kanıt:** `MarkdownDocument.swift:88–94` (okuma) + `:63–70` (yazma):
`lineEnding = ... "\r\n" : "\r"`; `text.replacingOccurrences(of: "\r\n", ...)`; yazarken
`output = text.replacingOccurrences(of: "\n", with: lineEnding)`.
**Doğrulandı (bayt deneyi):** `a\r\nb\nc\rd` (8 B, karışık) hiç düzenlenmeden `a\r\nb\r\nc\r\nd` (10 B) oldu;
LF'lik dosyaya tek CRLF girmişse **tüm dosya CRLF'e** dönüyor. Koddaki yorum "CRLF dosyaları geldikleri gibi
yazılır" diyor; karışık dosyalar normalleştiriliyor.
**Etki:** Git deposundaki notta her satır değişmiş görünür (dev diff/merge çakışması); Windows `autocrlf`
ekiplerinde çift dönüşüm riski; kullanıcı hiçbir şey yapmadan içerik değişir.
**Düzeltme:** Karışık dosyayı normalleştirme; satır bazında orijinal sonları sakla (`originalLineEndings: [String]`),
yeni satırlarda baskın olanı kullan; en azından `lineEndingMixed` bayrağıyla uyar.

### 2.2 [H2][High] `lossy` yok sayılıyor; legacy/geçersiz UTF-8 dosyalar bozulabiliyor

**Kanıt:** `MarkdownDocument.swift:72–96`: `usedLossyConversion` çıktısı `lossy` değişkenine alınıyor ama hiç
okunmuyor (`:78–81`); BOM okurken siliniyor (`:87`) ve geri yazılmıyor; yazarken kodlama temsil edemezse
sessizce UTF-8'e geçiliyor (`:66–68`).
**Doğrulandı (deneyler):** (a) Geçerli UTF-8 + tek bozuk bayt (`0xFF`) → çözüm tek baytlık kodlamaya düşüyor,
metin mojibake ("TГјrkГ§e…"); düzenleme sonrası yeni karakter o kodlamada yoksa `data(using:)` nil → **tüm belge
UTF-8'e transcode edilir, mojibake kalıcılaşır** (çift kodlama). (b) Temiz CP1254 dosyası + `→`/emoji: kodlama
temsil edemiyor → sessiz UTF-8 fallback, dosyanın **tamamı** yeniden kodlanır (Türkçe baytları değişir).
(c) UTF-8 BOM: 12 B dosya 9 B olarak kaydedildi (BOM kayboldu). (d) UTF-16BE + BOM: `String.Encoding.utf16` ile
**LE + LE BOM** yazılıyor (geçerli ama bayt farklı).
**Etki:** Eski/bozuk dosyalarda sessiz içerik bozulması; başka araçlarda mojibake; BOM bekleyen Windows
araçlarında kodlama karışması.
**Düzeltme:** `hadBOM`/`lossy` sakla; `lossy` ise salt-okunur aç + uyarı; kodlama temsil edemiyorsa **yazmayı
reddet**:

```swift
private var hadBOM = false
if text.hasPrefix("\u{FEFF}") { text.removeFirst(); hadBOM = true }
var out = hadBOM ? Data([0xEF,0xBB,0xBF]) : Data()
guard let body = output.data(using: encoding) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
```

### 2.3 [H4][High] İkili/metin olmayan dosya kapısı yok

**Kanıt:** `MarkdownDocument.swift:72–85`: yalnız `String(data:, .utf8)` + `stringEncoding` sezgisi; NUL/control
karakter, yazdırılabilirlik oranı, UTI veya boyut kontrolü yok. `stripControls` (MarkdownHTML.swift:598–602)
yalnız önizleme metninde çalışıyor; dosyaya yazılan metinde NUL'lar kalır.
**Doğrulandı (deney):** Rastgele 300 B veri 200 denemenin **117'sinde** geçerli "metin" olarak çözüldü
(`stringEncoding` tek baytlık kodlama döndürdü). Bozuk/şifreli/yanlış adlandırılmış dosya (`.md`/`.txt` uzantılı
ikili, yarım indirme) editörde çöp metin olarak açılır; ilk düzenleme+kayıt ile içerik bozulur.
**Düzeltme:** Okuma sonrası sağlık kontrolü:

```swift
let bad = data.filter { $0 == 0 || $0 < 0x09 }.count
if bad > max(1, data.count / 100) { throw CocoaError(.fileReadCorruptFile) }  // "Bu bir metin dosyası değil"
```

## 3. Çok büyük dosya davranışı

### 3.1 [H3][High] Boyut sınırı yok; tam-belge işleri ana thread'de

**Kanıt:** `MarkdownDocument.swift:72` (tüm dosya tek `Data`/`String`); `EditorViewController.swift:115–134`
(`textView.string = text` + **tam belge** `MarkdownStyler.restyle`); `EditorViewController.swift:136–176` (her
düzenlemede blok-lokal restyle, ama `blockFenceLineStarts` ve `storage.string as NSString` tüm metin üzerinde);
`DocumentWindowController.swift:138–153` (önizleme açıkken her yazma duraklamasında tüm not yeniden render,
0,25 s debounce).
**Ölçüldü** (kaynağın kopyasıyla release harness, gerçek `MarkdownStyler`/`MarkdownHTML` kodu):

| Boyut | açılış: tam restyle | yazma: 1 düzenleme restyle | önizleme: tam render |
|---|---|---|---|
| 0,5 MB (524 KB) | **5,66 s** | 0,045 s | **7,10 s** |
| 2,0 MB (2,1 MB) | **40,69 s** | 0,156 s | (ölçüm tamamlanmadı) |
| 8 MB ve üzeri | 5 dk zaman aşımı — tamamlanmadı | — | — |

**Etki:** 1–2 MB'lık not açılışta ana thread'i saniyelerce kilitler; önizleme açıkken her duraklamada 7+ s
donma → kullanıcı force-quit eder ve autosave penceresindeki (≈10–30 s) değişiklikler kaybolur; >8 MB pratikte
açılamaz.
**Düzeltme:** (a) okuma öncesi boyut kapısı (>25 MB → salt-okunur + uyarı), (b) `read(from url:ofType:)` + arka
planda okuma/restyle, (c) önizlemede yalnız görünür bölümü render et, (d) `MarkdownHTML.render`'ı blok bazlı
artımlı hâle getir.

## 4. FolderAccess / App Sandbox

### 4.1 [M1][Medium] Çözülemeyen bookmark kalıcı olarak siliniyor

**Kanıt:** `FolderAccess.swift:18–26`: döngüde `guard ... url.startAccessingSecurityScopedResource() else { continue }`
ile atlanan kayıt `kept`'e eklenmiyor; döngü sonunda `UserDefaults.standard.set(kept, forKey: key)`.
**Doğrulanmadı (çalışma zamanında simüle edilemedi; kod kanıtı):** Harici disk çıkarılmış, ağ birimi bağlı
değil, iCloud dosyası inmemiş veya klasör taşınmışsa bookmark o açılışta çözülemez → atlanır ve
**UserDefaults'tan silinir**; izin kalıcı olarak kaybolur.
**Etki:** Kullanıcı verdiği klasör iznini kaybeder, tekrar izin vermek zorunda kalır.
**Düzeltme:** Çözülemeyen kaydı silme, sakla ve o oturumda atla:
`guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) else { kept.append(data); continue }`.

### 4.2 [M2][Medium] `startAccessing`/`stopAccessing` dengesi yok + yinelenen bookmark

**Kanıt:** `FolderAccess.swift:22` ve `:50` yalnız `startAccessingSecurityScopedResource()`; depoda
`stopAccessingSecurityScopedResource()` **hiç yok** (`grep` = 0). `request()` her izinde aynı bookmark'ı listeye
ekliyor (`:47–50`), tekrar/dedupe yok.
**Doğrulanmadı (sızıntı miktarı ölçülmedi; kod kanıtı):** Her start bir sandbox uzantısı ayırır ve uygulama
ömrü boyunca serbest bırakılmaz; izin yenilendikçe `granted`/UserDefaults büyür, `canRead` O(n) olur.
**Etki:** Uzun oturumda kaynak sızıntısı; aynı klasör için tekrar tekrar "Allow Access".
**Düzeltme:** `guard !granted.contains(where: { $0.standardizedFileURL == url.standardizedFileURL })` +
kapanışta `started.forEach { $0.stopAccessingSecurityScopedResource() }`.

### 4.3 [M3][Medium] `canRead` yol-öneki karşılaştırması

**Kanıt:** `FolderAccess.swift:29–33` — `path.hasPrefix($0.standardizedFileURL.path + "/")`.
`standardizedFileURL` symlink çözmez (`/var` ↔ `/private/var`, `/tmp` ↔ `/private/tmp`) ve karşılaştırma harf
duyarlıdır (APFS varsayılanı duyarsız).
**Etki:** İzin verilen klasör symlink üzerinden seçilmişse `NoteLinks.open` (`FolderAccess.swift:63–70`) paneli
açar, kullanıcı "Allow" der, `done(canRead(folder))` yine `false` döner → **bağlantıya tıklama sessizce hiçbir
şey yapmaz**; önizlemedeki "Allow Access" bandı kalıcı kalır.
**Düzeltme:** `resolvingSymlinksInPath()` + path bileşeni karşılaştırması
(`Array(c.prefix(p.count)) == p`).

### 4.4 [M5][Medium] `PreviewScheme` medya yolunu `canRead` denetlemeden servis ediyor

**Kanıt:** `SidePanes.swift:180–207`: `quickmd://local/<path>` isteğinde `..` kontrolü yalnız `/.quickmd-app/`
kaynakları için (`:186`); diğer yollarda uzantı medya listesindeyse (`:187–189`) `Data(contentsOf:)` ile okunup
web view'a veriliyor; `FolderAccess.canRead` burada hiç çağrılmıyor (yalnız `show()` içindeki uyarı bandında,
`:77`).
**Etki:** Sandbox'lı sürümde OS erişimi kestiği için içerik gelmez ama her denemede sandbox `deny` logu üretir;
sandbox'sız varsayılan dağıtımda not içine gömülü `quickmd://local/Users/.../x.png` gibi bir yol kullanıcının
diskindeki herhangi bir görseli önizlemeye taşıyabilir (dışa sızdırma kanalı yok: JS/CSP ve `on*` temizliği
kapalı — beklenmeyen okuma yolu).
**Düzeltme:** `guard FolderAccess.canRead(file.deletingLastPathComponent())`; yalnız notun klasörü + uygulama
kaynaklarına izin ver.

### 4.5 Sandbox doğrulamaları

- `isSandboxed` tespiti (`FolderAccess.swift:13`) **doğrulandı**: aynı entitlements ile ad-hoc imzalanmış test
  bundle'ında `APP_SANDBOX_CONTAINER_ID` set edildi; sandbox dışı dosya okuma reddedildi. → Sorun yok.
- `Packaging/QuickMD.entitlements`: app-sandbox, user-selected RW, app-scope bookmarks, print, network.client —
  makul; `network.client` uzak görseller yüzünden gerçekten gerekli (§5.1).
- **[M6][Medium]** `scripts/build-app.sh:143–147` düz mod yalnız ad-hoc imzalıyor (entitlements yok);
  `:150–157` `--install` bu sandbox'sız app'i `/Applications`'a kopyalıyor → normal indirme/kurulum yolunda
  `FolderAccess` tümüyle no-op; güvenlik profili MAS sürümünden farklı, testler MAS build'ini temsil etmiyor.
- `Info.plist` `NSSupportsSuddenTermination` (build-app.sh:82): NSDocument `_updateSuddenTermination` ile kirli
  belgede kapatıyor (introspection; davranış test edilmedi).

## 5. Önizleme güvenliği (MarkdownHTML + WKWebView)

### 5.1 [H5][High] Uzak görseller varsayılan açık (gizlilik)

**Kanıt:** `MarkdownHTML.swift:778–782`:

```swift
let local = "'self' quickmd: file:"
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)'; \
style-src 'unsafe-inline' \(local) https:; font-src \(local) data: https:; img-src * \(local) data: blob:; \
media-src * \(local); connect-src 'none'; ...
```

`img-src *` ve `media-src *` her host'a açık; WKWebView JS açık kuruluyor (`SidePanes.swift:28–35`) ve önizleme
her render'da yükleniyor. "Uzak görselleri yükleme" ayarı yok (`Settings.swift` tamamı okundu); `network.client`
entitlement'ı (`QuickMD.entitlements:14`) bu yüzden zorunlu.
**Doğrulandı (payload deneyi):** `<img src="https://evil.example/track.gif">` preview'e gidiyor; ayrıca sanitize
edilmeyen iki vektör kaldı: `urlAttributePattern` (`:625`) **`srcset`** içermiyor →
`<img srcset="https://evil.example/track.gif 1x">` aynen geçiyor; `style` attribute'u filtrelenmiyor
(`handlerPattern`, `:624` yalnız `on*`/`srcdoc`/… siler) → `<div style="background-image:url(https://evil.example/x.png)">` geçiyor.
**Etki:** İnternetten gelen bir `.md` önizlemede açıldığı anda IP, açma zamanı ve cihaz bilgisi üçüncü tarafa
gider (tracking pixel); "yerel not editörü" beklentisiyle ve App Store gizlilik beyanıyla çelişir.
**Düzeltme:** Varsayılan `img-src quickmd: data: blob:`; uzak görseller `Settings.loadRemoteImages` (varsayılan
`false`) ile açılsın; sanitize'a `srcset` ve `style` filtreleri eklensin.

### 5.2 Sanitizer: XSS bulunamadı (doğrulandı)

43 payload denendi: `<script>`, `<svg onload>`, `<iframe>`, `<object>`, `<meta refresh>`, `onerror` (boşluklu,
`/` ile ayrılmış, büyük harf), `javascript:` (entity/`&colon;`/`\t`/`\n` gizlemeli), `vbscript:`, `file:` link,
`data:text/html`, `<base>`, `<template>`, `<math><mtext>`, `<!--><script>` — hepsi temizlendi. CSP ayrıca
`script-src 'nonce-…'` + `default-src 'none'` + `connect-src 'none'` ile ikinci katman; Mermaid
`securityLevel: 'strict'` (`MarkdownHTML.swift:918`), KaTeX varsayılan `trust:false`. **Önizleme XSS'i için
Blocker/High yok.** Kalan tek zayıflık: `[x](<javascript:alert(1)>)` → `href="<javascript:alert(1)>"` üretiyor
(tarayıcıda çalışmaz; baştaki `<` şemayı bozar) — L6 ile birlikte sertleştirilmeli.

### 5.3 Küçük maddeler

- **[L6][Low]** `MarkdownHTML.swift:778` CSP'de `file:` kaynağı. Bugün sanitizer `file:` URL'lerini `#`'e
  çeviriyor (`:650`, `:663`); delik kapalı ama gereksiz → `local = "'self' quickmd:"` yeterli.
- **[L7][Low]** `SidePanes.swift:166`, `:194`, `:209–211`: `stopped` set'i yalnız geç gelen tamamlanmada
  siliniyor; iptal edilip tamamlanmayan task kimlikleri süresiz kalıyor.
- **[L9][Low]** `SidePanes.swift:37–42`: özel KVC `webView.setValue(false, forKey: "drawsBackground")` yalnız
  `#if !APPSTORE` içinde — doğru, ama `-DAPPSTORE` bayrağı (`build-app.sh:34–36`) unutulursa doğrudan red
  nedeni; teslim öncesi `strings`/`otool` ile doğrulanmalı.

## 6. Undo/Redo, ayarlar, çökme kurtarma

- **Undo bütünlüğü iyi.** Tüm metin mutasyonları tek yoldan geçiyor: `MarkdownTextView.replace()` (`:500–510`)
  `shouldChangeText(in:replacementString:)` + `textStorage.replaceCharacters` + `didChangeText()` → NSTextView
  undo kaydı oluşuyor. Önizlemeden görev işaretleme (`:228–244` → `replace`), checkbox tıklaması (`:324–334` →
  `replace`), tablo Tab/⇧Tab yeniden biçimlendirme (`:217–219`, `TableEditing.format` çıktısı `replace` ile) ve
  Format menüsü (`MarkdownWrap`, `Checkbox.toggling` sonuçları yine `replace` ile) aynı yolu kullanıyor →
  hepsi undo'ya kaydediliyor. Deney: undo → change count doğru güncellendi; 31.024 rastgele-girdi fuzz turunda
  çökme yok.
- **[L4][Low]** `EditorViewController.load()` (`:115–125`) `undoManager?.removeAllActions()` çağırıyor. Dış
  değişiklik/`revert`/sürüm geri yüklemede doğru; ama kullanıcının **tüm undo geçmişi** sessizce yok oluyor ve
  revert'in kendisi geri alınamıyor. Bildirim (L1/L2) eklendiğinde kullanıcıya söylenmeli.
- **[L3][Low]** `EditorViewController.swift:185–190`: `shouldChangeTextIn` `false` dönüp
  `DispatchQueue.main.async { textView.insertText(..., replacementRange: range) }` ile yazıyor; araya giren
  değişiklikte `range` bayatlar → `NSRangeException` riski. **Doğrulanmadı** (yarış penceresi dar); düzeltme:
  `shouldChangeTextIn` içinde `replaceCharacters` + `didChangeText()`.
- **[L8][Low] Ayarlar:** `Settings.swift` tüm okumalarda güvenli varsayılana düşüyor
  (`FontFace(rawValue:) ?? template.defaultFace`, enum fallback'ları), `fontSize` 11…32'ye kenetli (`:59–70`) →
  bozuk/eksik UserDefaults ile çökme yok. Sürüm/migration yok; anahtar değişirse eski değer sessizce varsayılana
  döner (kabul edilebilir). `showsOutline` varsayılanı `bool(forKey:)` = `false`, diğerlerinin `?? true` desenine
  aykırı (Info).
- **Çökme kurtarma:** `AppDelegate.applicationSupportsSecureRestorableState` = true (`:32`); untitled belgeler
  NSDocument tarafından "autosave elsewhere" ile taslak olarak saklanıyor (SDK `NSDocument.h:438`). Uygulama
  kendi çökme-kurtarma kodunu yazmıyor. **Doğrulanmadı:** gerçek çökme sonrası state restorasyonu test edilmedi
  (GUI otomasyonu gerekir); release öncesi "force quit → yeniden aç" testi önerilir.

## 7. App Store sandbox / red riskleri

Entitlement'lar makul ve gerekçeli (`Packaging/QuickMD.entitlements:1–15`); `application-identifier` `--appstore`
modunda ekleniyor (`build-app.sh:127–132`); `--render`/`--make-default` ve özel KVC `#if !APPSTORE` ile
dışlanmış (`main.swift:9`, `AppDelegate.swift:24–29`, `SidePanes.swift:37–42`); PrivacyInfo'da UserDefaults +
FileTimestamp beyanlı. Riskler: uzak görseller nedeniyle `network.client` (gizlilik soruşturması, §5.1), sandbox
dışı varsayılan dağıtım (§4.5), sürüm tarayıcısının kullanıcıya kapalı olması (§1.2).

## 8. Doğrulama yöntemi ve doğrulanmayanlar

**Deneyler (hepsi `/tmp`, kaynak DEĞİŞTİRİLMEDİ):** (1) `MarkdownDocument.read/data`'nın birebir kopyasıyla
kodlama/bayt deneyleri (UTF-8 BOM, UTF-16LE/BE, CP1254, tek baytlık legacy, bozuk UTF-8 `0xFF`, BOM'suz UTF-16,
karışık CRLF/LF/CR, rastgele ikili 200×300 B); (2) `NSDocument`+`NSWindowController`+`NSTextView` harness'ı
(change tracking, undo → change count, autosave zamanlaması, `presentedItemDidChange` + birebir revert mantığı,
temiz/kirli belge + dış yazma, çakışma `attachedSheet`'i); (3) kaynak kopyasıyla release perf harness'ı
(0,5/2 MB); (4) sanitizer payload harness'ı (43 payload) + 31.024 turluk fuzz; (5) ad-hoc imzalı test `.app`
bundle'ı ile sandbox ortam değişkeni ve erişim reddi.
**Doğrulanmadı:** M1 (kod kanıtı), M2 (sızıntı miktarı), M3 (symlink senaryosu), L3 (async yarış), §6 çökme
sonrası state restorasyonu. Bunlar için GUI/sandbox otomasyonu gerekir.

## 9. İlk 5 düzeltme (sırayla)

1. **Kodlama ve satır sonu güvenliği (H1 + H2)** — `MarkdownDocument.read/data`: `lossy` ve `hadBOM` sakla,
   karışık satır sonlarını normalleştirme, kodlama temsil edemiyorsa yazmayı reddet ("UTF-8'e dönüştür?" sor).
   En yüksek sessiz-bozulma riski burada; diff küçük ve test edilebilir.
2. **Dosya sağlık kapısı + boyut sınırı (H4 + H3)** — okuma öncesi boyut sınırı, NUL/kontrol karakter oranı
   kontrolü, >25 MB için salt-okunur + uyarı; büyük belgelerde restyle/render'ı arka plana al (2 MB tam restyle
   40,7 s — tek başına force-quit riskini açıklıyor).
3. **Uzak görsel gizliliği (H5)** — `Settings.loadRemoteImages` (varsayılan kapalı) + CSP'yi
   `img-src quickmd: data: blob:` yap; `srcset` ve `style` filtrelerini sanitize'a ekle.
4. **FolderAccess dayanıklılığı (M1 + M2 + M3)** — çözülemeyen bookmark'ı silme, `stopAccessing` dengesi +
   dedupe, `resolvingSymlinksInPath` + path-component karşılaştırması, grant sonrası doğrulama.
5. **Dış değişiklik görünürlüğü + sürüm erişimi (L1 + L2 + M4)** — `modified != known` ile çakışma say, revert
   hatalarını `presentError` ile göster, sessiz revert'i "dosya diskte değişti" bandıyla bildir; File menüsüne
   `NSDocument.browseDocumentVersions(_:)` öğesini ekle.
