# App Store Connect metinleri (taslak)

Tarih: 2026-11-10. Adım 1.6 için. Kopyala-yapıştır hazır.

## İsim (dikkat)

"QuickMD" mağazada **alınmış**: başka bir geliştiricinin ücretsiz Markdown görüntüleyicisi (apps.apple.com/app/quickmd/id6757681819). Mağaza adı benzersiz olmalı. Öneri: **"QuickMD Editor"** ya da yeni bir ad. Bundle id (`com.ursula.quickmd`) değişmez; sadece App Store Connect'teki ad ve istersen `CFBundleDisplayName`. Karar senin.

## URL'ler

- Destek: https://ihsansoycelik.github.io/quickmd/support.html
- Gizlilik: https://ihsansoycelik.github.io/quickmd/privacy.html
- Sayfalar `docs/` klasöründe. Yayın için: repo Settings › Pages › "Deploy from branch: main /docs". Repo özel olduğu için Pages ücretli plan ister; olmazsa `docs/`'u ayrı, herkese açık küçük bir repoya koy ve `Help.supportURL` / `Help.privacyURL`'ı güncelle.
- Destek sayfasındaki GitHub issues linki de özel repoda çalışmaz; herkese açık bir issues yeri ya da e-posta koy.

## Alt başlık (30 karakter)

EN: Quiet Markdown, plain files
TR: Sade Markdown, düz dosya

## Tanıtım metni (170 karakter)

EN: A native Mac editor for Markdown. Your note reads styled; the line you're on shows its Markdown. Files stay plain text.
TR: Mac için yerel Markdown editörü. Not biçimli okunur, üzerinde olduğunuz satır Markdown'unu gösterir. Dosyalar düz metin kalır.

## Açıklama (EN)

QuickMD is a calm, native Markdown editor for the Mac.

One view does both reading and writing. Headings, lists, tables, task boxes, code and pictures show themselves styled, and the line the caret is on shows its Markdown, ready to edit. What's on disk stays plain Markdown that any app can open.

• Tables drawn as real grids; Tab moves between cells
• Click a task box to tick it
• Local pictures shown inline; paste a screenshot to save it beside the note
• Type / for headings, lists, tables, callouts, math and diagrams
• Export as HTML or PDF, print, share
• Notes save themselves, with Versions, tabs and Find & Replace
• Watch an agent or another app write into an open note, live
• Light and dark, VoiceOver, English and Turkish

No accounts, no tracking, no data collected.

## Açıklama (TR)

QuickMD, Mac için sakin, yerel bir Markdown editörü.

Tek görünüm hem okur hem yazar. Başlıklar, listeler, tablolar, görev kutuları, kod ve görseller biçimli görünür; imlecin olduğu satır Markdown'unu gösterir, düzenlemeye hazır. Diskte kalan şey her uygulamanın açabildiği düz Markdown'dur.

• Tablolar gerçek ızgara olarak çizilir; Tab hücreler arasında gezer
• Görev kutusuna tıklayıp işaretle
• Yerel görseller satır içinde; ekran görüntüsünü yapıştır, notun yanına kaydedilsin
• / yaz: başlık, liste, tablo, not kutusu, matematik, diyagram
• HTML veya PDF dışa aktar, yazdır, paylaş
• Notlar kendini kaydeder; Sürümler, sekmeler, Bul ve Değiştir
• Bir ajanın ya da başka bir uygulamanın açık nota yazışını canlı izle
• Açık ve koyu, VoiceOver, İngilizce ve Türkçe

Hesap yok, takip yok, veri toplanmaz.

## Anahtar kelimeler (100 karakter)

EN: markdown,editor,md,notes,writer,text,plain text,tables,tasks,export,pdf,html,agent
TR: markdown,editör,md,not,yazı,metin,düz metin,tablo,görev,dışa aktar,pdf,html

## Diğer alanlar

- Kategori: Productivity (ikincil: Developer Tools)
- Yaş derecesi: 4+ (tüm sorulara "Hayır")
- Fiyat: karar senin
- App Privacy: "Data Not Collected"
- Telif: © 2026 Ursula

## İnceleme notu (App Review)

QuickMD is a document-based Markdown editor. No account or sign-in is needed. To test: File › New, type Markdown, or open any .md file.
The com.apple.security.network.client entitlement is only needed because WebKit (used for Print and Export as PDF) does not start in the sandbox without it. The app itself makes no network requests.
"Default App for Markdown" uses NSWorkspace.setDefaultApplication; macOS asks the user to confirm.

## Ekran görüntüleri (1280×800 veya 2880×1800)

1. Tablo + görev listesi olan bir not, açık tema
2. Aynı not, koyu tema
3. Satır içi görsel + kod bloğu
4. Slash menüsü açık
5. Dışa aktarılmış PDF/Yazdır önizlemesi
