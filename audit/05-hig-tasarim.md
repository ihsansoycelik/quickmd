# 05 — Görsel tasarım, macOS HIG'e göre

**Tarih:** 2026-11-01 · Build: `build/QuickMD.app` (çalışma ağacı) · Örnek belge: başlık, görev listesi, tablo, KaTeX, Mermaid, kod.
Menü, erişilebilirlik ve yerelleştirme bulguları `02-platform.md` içinde. Bu rapor yalnızca **görünüş ve etkileşim**.

## Yüksek öncelik

1. **Tablo, formül ve diyagram editörde ham kalıyor.** Tablo, boru (`|`) işaretleriyle monospace yazılıyor. Dar sütunda satırlar kırılıp okunmaz oluyor. `$$…$$` ve ```` ```mermaid ```` sadece renkli kod olarak görünüyor. Referans görseldeki "olduğu yerde çizilmiş" görünüm için şu yapılmalı: imleç bloğun dışındayken blok render edilmiş bir ek (attachment) olarak gösterilsin, imleç içine girince kaynağa dönsün. Tabloyla başlanmalı (TableEditing.swift zaten var).
2. **Mermaid önizlemede çok küçük.** Diyagram panelin genişliğine sığsın diye küçültülüyor ve 8–9 pt'ye kadar düşüyor (`pre.mermaid svg { max-width: 100% }`, MarkdownHTML.swift:901). Yazı en az gövde metni boyutunda kalmalı. Sığmazsa yatay kaydırma olmalı, tıklayınca büyütme açılmalı.
3. **Koyu tema "sistem koyusu" gibi görünmüyor.** `.fullScreenUI` materyalinin üstüne siyah renk (%50/%22) konuyor. Sonuç: bulanık, gri ve çamurlu bir zemin. Sekme çubuğu ise sistem koyusu olduğu için zeminden belirgin şekilde koyu kalıyor ve iki farklı renk yan yana duruyor. HIG'e uygun çözüm: editör alanı için `.textBackgroundColor` / `.windowBackgroundColor` (veya `.underWindowBackground`) kullanmak, saydamlığı isteğe bağlı bir efekt yapmak ve varsayılanı **Off** yapmak.
4. **Sistem renk ve kontrast ayarları eziliyor.** Palette sabit sRGB değerleri kullanıyor (Theme.swift:111+). Increase Contrast ve Reduce Transparency açıkken de aynı renkler çiziliyor. `NSColor.labelColor`, `secondaryLabelColor`, `separatorColor`, `quaternaryLabelColor` gibi dinamik renklere geçilmeli. Reduce Transparency açıkken glass kapanmalı.

## Orta öncelik

5. **Kenar çubuğu (Outline) bir "source list" değil.** Başlıklar düz metin. Seçili/bulunulan bölüm vurgulanmıyor ve klavyeyle gezilemiyor. `NSOutlineView` + `.sourceList` stili, seçim vurgusu ve imlecin bulunduğu başlığın vurgusu eklenmeli (Notes ve Xcode'daki gibi).
6. **Başlıkta `.md` uzantısı görünüyor, proxy ikonu gizli.** HIG'e göre uzantı Finder ayarına uymalı (`displayName` bunu zaten yapıyor; uzantı dosya adından geliyor olabilir, kontrol edilmeli). Proxy ikonu da geri gelmeli: sürükleme ve ⌘-tık ile yol menüsü bu ikona bağlı.
7. **Ayarlar penceresi uygulamanın görünümüne uymuyor.** Uygulama Light'tayken Settings koyu açıldı. Örnek metin ham markdown (`**Bold**`). Sabit 520 pt genişlik var. Örnek, render edilmiş halde ve seçili temayla gösterilmeli.
8. **Toolbar'da "Aa" Format menüsü.** "Aa" sembolü macOS'ta yazı tipi/görünüm demek (Safari ve Books'ta öyle). Başlık/liste/blok menüsü için `textformat` yerine `paragraphsign` veya `list.bullet.indent` daha doğru olur. Alternatif olarak sık kullanılan B/I/U doğrudan toolbar'a konabilir (referanstaki gibi).
9. **Önizleme ayırıcısı başlık çubuğunu ikiye bölüyor.** Önizleme açıkken bölme çizgisi toolbar'ın içinden yukarı kadar uzanıyor. Toolbar butonları da önizleme tarafına itiliyor. Önizleme bir "inspector" gibi davranmalı (`NSSplitViewItem(inspectorWithViewController:)`, macOS 14+) ya da ayırıcı toolbar'ın altında bitmeli.

## Düşük öncelik

10. **Footer'daki kelime sayısı** 10–11 pt ve çok soluk (kontrastı düşük). `secondaryLabelColor` ve 11 pt minimum kullanılmalı. Tıklanınca karakter ve okuma süresi gösterebilir.
11. **Kod bloğunda yatay kaydırma çubuğu sürekli görünüyor** (önizleme). Sistemin "kaydırırken göster" ayarına uyulmalı (`overflow: auto` + WebKit varsayılanı) ya da satır kaydırılmalı.
12. **Görev listesinde `-` işareti ve onay kutusu yan yana.** Hem işaret hem kutu gösteriliyor. Kutu varken `- [ ]` işaretleri daha da soluklaştırılmalı ya da gizlenmeli.
13. **Callout'ta `[!TIP]` ham görünüyor** (editör). Sol çizgi ve renk doğru. Etiket "Tip" diye, ikon ile gösterilebilir.

## Yeni özellik: slash (/) menüsü

Satır başında `/` yazınca imlecin altında küçük bir liste açılsın: Heading 1–3, Bulleted/Numbered/Task List, Quote, Code Block, Table, Callout, Math Block, Mermaid Diagram, Horizontal Rule.
- Görünüm: `NSPanel` (non-activating), `.menu` materyali, 13 pt sistem fontu, solda SF Symbol. Format menüsündeki ikonlar kullanılsın.
- Davranış: yazdıkça filtrelensin. ↑↓ ile seçilsin, ↩ ile uygulansın. Esc veya boşlukla kapansın. `/` metin olarak kalsın, menü kapanınca silinmesin.
- Komutlar, Format menüsündeki selector'ları kullansın (MarkdownTextView'daki mevcut `insert…`/`toggle…` metotları).

## İyi olanlar (korunmalı)

- Unified toolbar, tracking separator, SF Symbols, sistem sekmeleri, dinamik Show/Hide menü başlıkları.
- Light tema temiz: sidebar materyali, okunabilir satır genişliği, serif başlıklar iyi bir hiyerarşi kuruyor.
- KaTeX önizlemede düzgün. Mermaid tema renklerini alıyor (sadece boyutu sorun).
- Seçim rengi `controlAccentColor`'u takip ediyor.
