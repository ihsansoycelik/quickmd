# 08 — Yol haritası: App Store'a hazır, hafif ve hatasız QuickMD

**Tarih:** 2026-11-03 · Kaynak: audit/00–07. Hedef: hafif, hızlı, estetik, hatasız, App Store'da yayınlanabilir bir native Markdown editörü/okuyucusu.

İlke: her tur kendi başına yayınlanabilir; önce veri güvenliği, sonra görünür özellik, sonra cila ve dağıtım.

## Tur 1 — Güven + canlı önizleme (bitti, 2026-11-03; ekran görüntüsüyle doğrulandı, editör→önizleme kaydırma senkronu elle denenmedi)
1. Veri güvenliği: ikili dosya kapısı (P1-3), BOM korunur, kayıplı kodlama çözümü reddedilir (P1-2), karışık satır sonunda çoğunluk korunur (P1-1).
2. `PreviewScheme`: yalnız erişilebilir klasörden servis, `stopped` sızıntısı (P1-8).
3. Canlı önizleme paneli: Yalnız Editör ⌘1 / Yan Yana ⌘2 / Yalnız Önizleme ⌘3; render arka planda, sayfa yerinde güncellenir (kaydırma kaybolmaz); editör kaydırması önizlemeyi izler; önizlemedeki checkbox dosyayı günceller; Mermaid/KaTeX ekranda.
4. Testler, `swift test`, `build-app.sh --install`.

**Güncelleme (2026-11-06):** Canlı önizleme panosu, göz düğmesi ve ⌘1/⌘2/⌘3 düzen seçimi kullanıcı kararıyla kaldırıldı (`Preview.swift` silindi); tek görünüm = hibrit editör (okuma modu: imleç satırı markdown'ı gösterir). Önizleme yalnızca PDF/HTML dışa aktarma, yazdırma ve `--render` içinde yaşıyor (`PreviewScheme` + `MarkdownHTML`). Ekranda Mermaid/KaTeX artık yok. Tablo okuma modunda borular artık soluk ama görünür (ajansız dolgusuz tablolarda sütunlar kaybolmasın); delimiter satırının satır sonu artık sonraki satırın ilk borusuyla birleşmiyor. Sıradaki görünüm işi: editörde grid tablo çizimi — sütun hizalaması dosyayı değiştirmeden NSTextView'da mümkün değil (Tab ile hücre gezince `TableEditing.format` dolgusuyla hizalanıyor).

## Tur 2 — Performans
`os_signpost` ölçümü; görünür alan önce restyle; büyük dosya koruması (>5 MB düz metin modu); hedef tuş başı <1 ms, 1 MB açılış <500 ms.

## Tur 3 — Profesyonel Mac katmanı
Yerelleştirme altyapısı (EN+TR), Browse All Versions (P1-7), uzak görseller varsayılan kapalı + `srcset/style` temizliği (P1-5), FolderAccess dayanıklılığı (P1-6), kod bloğu kopyala düğmesi, Copy as Rich Text.

## Tur 4 — Fark yaratanlar
Quick Look eklentisi, Welcome notu + varsayılan uygulama sorusu, What's New, App Intents.

## Tur 5 — Dağıtım (Apple hesabı gerekli)
İmza + notarization, App Store build'i, gizlilik/destek sayfası, ekran görüntüleri.

## Sonra
Klasör modu (dosya ağacı, klasör araması, `[[wiki link]]`, backlink), frontmatter özellik kutusu.
