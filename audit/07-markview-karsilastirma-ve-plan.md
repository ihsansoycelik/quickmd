# 07 — MarkView ile karşılaştırma ve QuickMD geliştirme planı

**Tarih:** 2026-11-03 · **Karşılaştırılan:** `/Applications/MarkView.app` 1.5 (build 280, Codecake, App Store) ile QuickMD (`main`, 9855b45).
**Yöntem:** MarkView paketi okundu (Info.plist, `Guide.md`, `bootstrap.js`, `markview.css`, 282 arayüz metni). QuickMD kaynak kodu, menüleri ve `audit/00–06` okundu. İki uygulama aynı dosyayla açılıp ölçüldü.

---

## 1. Kısa hüküm

İki uygulama farklı işler yapıyor:

- **MarkView bir okuyucu + not defteri.** Ana deneyim render edilmiş önizleme. Klasör açınca Obsidian'a benzeyen bir "vault" oluyor: dosya ağacı, `[[wiki link]]`, backlink, grafik, klasör çapında arama/değiştirme, YAML özellikleri. Gelir modeli Pro abonelik.
- **QuickMD bir yazma aracı.** Ana deneyim canlı stillenen editör (işaretler yerinde, dosya düz Markdown). Tek dosya odaklı. Rakipsiz özelliği: **ajanın yazışını canlı izleme**.

**Eksiğimiz iki büyük blok:** (1) zengin blokları editörde göstermek (tablo, matematik, Mermaid, görsel editörde hâlâ ham), (2) klasör/vault modu. Geri kalanı cila ve dağıtım işi.

**Önümüzde olduğumuz yerler:** canlı WYSIWYG-benzeri yazma, ajan entegrasyonu, slash menü, tablo düzenleme, gizlilik (MarkView'da Firebase Analytics + Crashlytics var), büyük dosya açma hızı.

---

## 2. Ölçüm (aynı makine, aynı dosyalar)

| Test | QuickMD | MarkView | Not |
|---|---|---|---|
| Paket boyutu | 6,9 MB | 8,7 MB | MarkView'ın ~2 MB'ı Firebase/Google çerçeveleri |
| 400 KB not açma (CPU boşalana kadar) | ~5 s, 1,85 s CPU | ~10 s, 6,20 s CPU | Kaba ölçüm (ps ile). QuickMD ~3× az CPU |
| Bellek (ana süreç, 400 KB) | 46 MB | 34 MB + WebContent süreçleri | MarkView'ın asıl yükü WebKit süreçlerinde |
| Telemetri | Yok | Firebase (opt-in sorulur) | Pazarlamada kullanılabilir fark |
| Minimum macOS | 13 | 14 (Pro: 15) | Bizde daha geniş kitle |

Not: Pencere açılış süresi ölçümü (`osascript` ile) güvenilir çıkmadı, ikisi de ~2,8 s gösterdi; bu sayı kullanılmamalı. Doğru ölçüm için uygulama içine `os_signpost` konmalı (Faz D).

---

## 3. Özellik karşılaştırması

✅ var · ⚠️ kısmen · ❌ yok

### 3.1 Okuma / render

| Özellik | MarkView | QuickMD | Öncelik |
|---|---|---|---|
| Canlı render önizleme | ✅ (ana görünüm) | ⚠️ Reading Mode işaretleri gizler, ama tablo/`$$`/Mermaid ham kalır; WKWebView yalnız Print/Export'ta | **P0** |
| Editör + önizleme yan yana, senkron kaydırma (⌘1/⌘2/⌘3) | ✅ | ❌ | **P0** |
| Mermaid diyagramları ekranda | ✅ (temaya uygun renkler, metin boyuyla ölçeklenir) | ⚠️ yalnız export/print | **P0** |
| KaTeX matematik ekranda | ✅ (`$5` fiyatı matematik sanılmaz) | ⚠️ yalnız export/print | **P0** |
| Kod renklendirme | ✅ Shiki, 15 dil, dil etiketi + kopyala düğmesi | ⚠️ kendi highlighter'ımız, ~8 dil, kopyala yok | P1 |
| GitHub callout'ları | ✅ 5 tür | ✅ | — |
| Görsellerin editörde görünmesi | ✅ (önizlemede) | ❌ yalnız link | P1 |
| Geniş tablo kendi kutusunda yatay kayar | ✅ | ❌ | P1 |
| Okuma genişliği önayarları (640…1280, tam) + Aa popover | ✅ | ⚠️ yalnız "Readable Line Width" açık/kapalı | P1 |
| Pinch ile yakınlaştırma | ✅ | ❌ | P2 |
| Emoji kısa kodları (`:tada:`) | ✅ | ❌ | P2 |
| Başlık çapaları `#kod` | ✅ | ✅ | — |
| Önizlemede checkbox dosyayı değiştirir | ✅ | ✅ (editörde) | — |
| Önizlemede paragrafa tıklayıp yerinde düzenleme + kilit | ✅ | — (editör zaten canlı; gerek yok) | — |
| YAML frontmatter → düzenlenebilir özellik tablosu (tarih seçici, etiket chip'leri) | ✅ | ❌ (ham metin) | P1 |

### 3.2 Klasör / not defteri (vault)

| Özellik | MarkView | QuickMD | Öncelik |
|---|---|---|---|
| Klasör aç (⇧⌘O), dosya ağacı kenar çubuğu | ✅ | ❌ (kenar çubuğu yalnız outline) | **P0** |
| Yeni not / klasör, yeniden adlandır, taşı, çöpe at, Finder'da göster, yol kopyala | ✅ | ⚠️ tek belge için Rename/Move To | **P0** (ağaçla gelir) |
| Sıralama (ad, oluşturma, değişim) | ✅ | ❌ | P1 |
| Son workspace'ler | ✅ | ❌ | P1 |
| `[[wiki link]]` + yazarken tamamlama | ✅ | ❌ (göreli `.md` linkleri açılıyor) | P1 |
| Backlink'ler ("bu nota bağlananlar") | ✅ | ❌ | P1 |
| Yeniden adlandırınca tüm linkler güncellenir | ✅ | ❌ | P1 |
| Klasör çapında arama | ✅ | ❌ | **P0** |
| Klasör çapında bul-değiştir (önizlemeli) | ✅ (Pro) | ❌ | P2 |
| Özellik/etiketle filtreleme | ✅ (Pro) | ❌ | P2 |
| Not grafiği | ✅ (Pro) | ❌ | P3 (göz alıcı ama az kullanılır) |

### 3.3 Yazma / editör (bizim güçlü alanımız)

| Özellik | MarkView | QuickMD |
|---|---|---|
| Canlı stillenen editör (işaretler yerinde) | ❌ düz kaynak + önizleme | ✅ |
| Slash menü (`/` ile blok ekleme) | ❌ | ✅ |
| Tablo: Tab/⇧Tab ile hücre gezme, sütun hizalama, satır ekleme | ❌ | ✅ |
| Akıllı listeler, girinti, checkbox tıklama | ⚠️ | ✅ |
| Seçimi `*`, `` ` ``, `[` ile sarma; URL yapıştırınca link | ❌ | ✅ |
| Sürükle-bırak dosya/görsel → göreli link | ? | ✅ |
| Şablonlar (New from Template) | ❌ | ✅ |
| `==vurgu==` | ? | ✅ |
| Sekmeler, Versions, autosave | ⚠️ | ✅ |
| **Ajanın yazışını canlı izleme** | ❌ | ✅ (tek) |
| Satır kaydırma aç/kapa | ✅ | ⚠️ |
| Dosya diskte değişti: "Benim sürümüm / Dış sürüm" | ✅ | ✅ (NSDocument sayfası) |

### 3.4 Dışa aktarma ve paylaşım

| Özellik | MarkView | QuickMD | Öncelik |
|---|---|---|---|
| PDF, HTML (stil gömülü) | ✅ | ✅ | — |
| Zengin metin olarak kopyala (Mail/Pages'e yapıştır) | ✅ | ⚠️ "Copy as HTML" | P1 |
| Markdown kopyala ⌘⇧C | ✅ | ❌ | P2 |
| Yazdırma: beyaz kâğıt, kod bloğu bölünmez, tablo sayfaya sığar | ✅ | ⚠️ render basılıyor, sığdırma yok | P1 |
| Dış linki açmadan önce onay | ✅ | ❌ | P2 |

### 3.5 "Profesyonel Mac uygulaması" katmanı

| Özellik | MarkView | QuickMD | Öncelik |
|---|---|---|---|
| Yerelleştirme | ✅ ~40 dil (Türkçe dahil) | ❌ yalnız İngilizce | **P0** (önce TR+EN, sonra top 10) |
| İlk açılış: rehber not + "varsayılan uygulama yapılsın mı?" | ✅ | ⚠️ menüde "Make Default" | P1 |
| "What's new" ekranı | ✅ | ❌ | P1 |
| Kısayolları Settings'te değiştirme | ✅ | ❌ | P2 |
| Contact Support / Rate / Feedback menüleri | ✅ | ⚠️ Help var, destek yok | P1 |
| Uygulama dili seçimi | ✅ | ❌ | P3 (sistem ayarı yeter) |
| App Store'da yayında, imzalı | ✅ | ❌ (ad-hoc imza) | **P0** |
| Quick Look önizleme eklentisi | ❌ | ❌ | P1 — **ikisinde de yok, fark yaratır** |
| Spotlight / Shortcuts (App Intents) / Services | ❌ | ❌ | P2 — fark yaratır |
| Erişilebilirlik (VoiceOver etiketleri, kontrast) | ? | ⚠️ temel düzeyde | P1 |
| Çökme raporu | Firebase Crashlytics | ❌ | P1 — **MetricKit** ile, üçüncü taraf olmadan |
| Monetizasyon | Pro: aylık/yıllık/ömür boyu, deneme, promo kod | ❌ | Karar gerekiyor (bkz. §6) |

---

## 4. Nasıl daha iyi ve daha hızlı oluruz — konumlandırma

MarkView'ı kendi oyununda (vault + grafik) geçmeye çalışmak Obsidian'la da yarışmak demek. Daha iyi yol:

**"Ajanların yazdığı Markdown için native Mac editörü."**

1. **Ajan çağı özelliği tek başına pazarlanabilir.** Claude Code, Codex, Cursor kullanan herkes her gün `.md` plan/rapor okuyor. "Ajan yazarken izle, `==…==` ile önemli yeri gör, tek tıkla düzelt" başka hiçbir uygulamada yok. Bunu ana sayfanın ilk cümlesi yap.
2. **Gizlilik:** "Sıfır izleyici, sıfır hesap, çevrimdışı." MarkView'da Google Firebase var; biz bunu karşılaştırma tablosunda gösterebiliriz.
3. **Hız, ölçülebilir iddiayla:** "400 KB'lık notu 3× daha az CPU ile açar." Ölçümü otomatik benchmark'a bağla (Faz D), sayıları sitede yayınla.
4. **Yazma deneyimi:** canlı stil + slash menü + tablo düzenleme. "Önizleme penceresine bakmadan yaz."
5. **Daha geniş macOS desteği:** macOS 13+.

Vault özelliklerinden yalnız gerekenleri al: dosya ağacı, klasör araması, `[[link]]` + backlink. Grafik sonra.

---

## 5. Geliştirme planı

Her faz kendi başına yayınlanabilir. Süreler tek kişi, kaba tahmin.

### Faz A — Rendering açığını kapat (P0, ~1,5–2 hafta)

En görünür eksik bu. Kullanıcı Mermaid/matematik/tablo yazınca ekranda göremiyor.

1. **Canlı önizleme paneli:** `NSSplitViewController`'a üçüncü öğe olarak WKWebView (zaten `MarkdownHTML` + `PreviewScheme` + KaTeX/Mermaid paketli). Düzenler: Yalnız editör (⌘1), Yan yana (⌘2), Yalnız önizleme (⌘3). Toolbar'da segment.
2. **Artımlı güncelleme:** her tuşta tüm sayfayı yeniden yüklemek yerine `body` değişimi (MarkView'ın `__markview` deseni gibi), debounce 150 ms, render arka plan kuyruğunda.
3. **Senkron kaydırma:** blok başına kaynak satırı `data-line` özniteliği → iki yönlü eşleme.
4. **Editör içi zengin bloklar (Reading Mode için):** Mermaid ve `$$` bloklarını `NSTextAttachment` olarak çiz (WKWebView snapshot → görsel, önbellekli). Tabloları hizalı ızgara olarak çiz. Görselleri satır içinde göster.
5. Mermaid temasını uygulama renklerine bağla; diyagramı metin boyuyla ölçekle.
6. Kod blokları: kopyala düğmesi + dil etiketi; highlighter'a eksik diller (swift, js/ts, rust, json, css, dockerfile, markdown). Shiki büyük (MarkView 4,3 MB tembel yüklüyor); kendi highlighter'ımızı genişletmek daha hızlı ve hafif.
7. Geniş tablolar kendi kutusunda yatay kaysın; yazdırmada sayfaya sığsın; kod blokları sayfa arasında bölünmesin.

### Faz B — Klasör modu (P0/P1, ~2–3 hafta)

1. **Open Folder… (⇧⌘O):** kenar çubuğunda Outline / Files sekmesi. `NSOutlineView` dosya ağacı, FSEvents ile canlı. Sandbox için güvenlik kapsamlı bookmark (`FolderAccess` genişletilir).
2. Bağlam menüsü: New Note, New Folder, Rename, Move to…, Move to Trash, Reveal in Finder, Copy Path. Sıralama seçenekleri. Recent Folders.
3. **Klasör araması (⇧⌘F):** arka plan indeksi (basit ters indeks, bellekte), sonuçta satır önizlemesi.
4. **`[[wiki link]]`:** yazarken tamamlama (slash menü altyapısı yeniden kullanılır), ⌘-tık ile açma, olmayan nota tıklayınca oluşturma.
5. **Backlink'ler:** belge altında veya kenar çubuğunda "Buraya bağlananlar (n)".
6. Yeniden adlandırınca linkleri güncelle (onay sayfasıyla: "12 notta 18 link güncellenecek").
7. Sonra (P2): klasör çapında bul-değiştir, etiket/özellik filtresi. P3: grafik.

### Faz C — Frontmatter ve küçük render işleri (P1, ~1 hafta)

1. YAML frontmatter'ı editörde soluk bir "Properties" kutusu olarak stille; önizlemede tablo. Tarih → tarih seçici, liste → chip. Dosyada düz YAML kalır.
2. Emoji kısa kodları, okuma genişliği önayarları + Aa popover (boyut + genişlik), pinch-zoom.
3. Copy as Rich Text (RTF + HTML panoya birlikte), Copy Markdown.
4. Dış link onayı (ayarla kapatılabilir).

### Faz D — Hız: ölçülebilir ve pazarlanabilir (P1, sürekli)

Mevcut ölçümler (audit/00 §5): 259 KB'de tam restyle 1.005 ms, render 565–624 ms, tuş başına 7,3 ms.

1. `os_signpost` ile ölç: açılış → ilk çizim, tuş → stil, tuş → önizleme. Hedef: soğuk açılış < 300 ms, tuş başı < 1 ms, 1 MB not açma < 500 ms.
2. Restyle'ı görünür alan önce, kalanı arka planda yap (viewport-first). Fence indeksini artımlı tut.
3. Render'ı arka plan kuyruğuna taşı; önizlemede yalnız değişen blokları değiştir.
4. Büyük dosya koruması: > 5 MB'de uyarı + düz metin modu; ikili dosya kapısı (audit P1-3).
5. CI'da benchmark: aynı dosya setiyle her commit'te sayılar; gerilerse kırmızı. Sitede "MarkView/Typora/Obsidian ile karşılaştırma" sayfası.

### Faz E — Profesyonel Mac katmanı (P0/P1, ~2 hafta)

1. **Yerelleştirme:** `Localizable.xcstrings` + `String(localized:)`. Önce EN + TR, sonra DE, FR, ES, JA, ZH-Hans, KO, PT-BR, IT.
2. **İlk açılış:** "Welcome" notu (MarkView'ın Guide.md'si gibi, her şeyi canlı gösteren bir not; bizde ajan bölümü de olsun) + varsayılan uygulama sorusu + Settings'te ajan hook'unu tek tıkla kurma.
3. What's New ekranı (sürüm başına bir kez), Help ▸ Contact Support…, Rate QuickMD…, Report an Issue….
4. **Quick Look eklentisi:** Finder'da Space'e basınca render edilmiş not. MarkView'da yok, Mac kullanıcısının her gün gördüğü bir fark.
5. **Shortcuts / App Intents:** "Yeni not oluştur", "Nota ekle", "Markdown'ı HTML/PDF'e çevir". Services menüsü: "Seçimi QuickMD'de yeni not yap".
6. Spotlight: klasör modundaki notları `CSSearchableIndex` ile indeksle.
7. Erişilebilirlik: checkbox'lara rol/etiket, VoiceOver gezintisi, Increase Contrast testi.
8. Çökme ve performans raporu: **MetricKit** (üçüncü taraf yok, gizlilik iddiası korunur).
9. Settings ▸ Shortcuts: kısayolları değiştirme (P2).

### Faz F — Dağıtım ve iş modeli (P0, hesaba bağlı)

1. Apple Developer hesabı, imza, notarization; App Store (audit/06 Faz 3) **ve** web'den doğrudan DMG + Sparkle güncelleme (ajan kullanan geliştiriciler genelde siteden indirir).
2. Web sitesi: tek sayfa, ilk ekranda ajan canlı yazma videosu, karşılaştırma tablosu, gizlilik ve hız sayıları.
3. Kanallar: Claude Code / Codex topluluğu, Hacker News "Show HN", Product Hunt, r/macapps, Homebrew cask.
4. Fiyat (karar gerekiyor): öneri — temel editör ücretsiz; **tek seferlik "Pro"** (klasör modu, klasör araması, backlink, Quick Look dışı gelişmiş export). MarkView abonelik istiyor; "abonelik yok" bir satış argümanı.

---

## 6. Önerilen sıra

1. **Faz A** (önizleme + zengin bloklar) — en görünür açık.
2. **Faz E 1–4** (TR/EN, ilk açılış, Quick Look) — profesyonel his ve fark.
3. **Faz F 1–2** (imza + site) — dağıtılabilir olsun, ajan özelliğiyle duyur.
4. **Faz B** (klasör modu) — Pro'nun omurgası.
5. **Faz D** sürekli, **Faz C** aralarda.

## 7. Bilinçli olarak almadıklarımız

- Önizlemede paragrafa tıklayıp düzenleme: editörümüz zaten canlı; iki düzenleme yüzeyi karışıklık getirir.
- Firebase/Google Analytics: gizlilik iddiamızı bozar.
- Shiki: 4 MB+; kendi highlighter'ımızı genişletmek daha hafif.
- 40 dil bir anda: önce 10 dil; çeviri kalitesi sayıdan önemli.
- Uygulama içi dil seçici: macOS'un kendi uygulama başına dil ayarı var.
