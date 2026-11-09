# QuickMD — Mac App Store'a hazırlık planı

**Tarih:** 2026-11-08 · **İlke:** sadelik korunur. Yeni panel, kenar çubuğu, şablon, TOC yok. Sadece macOS'un zaten beklediği şeyler.

Bugün tamam olanlar (dokunma): NSDocument + otomatik kayıt, Kaydet / Çoğalt / **Farklı Kaydet (⌥⌘S, yeni)** / Yeniden Adlandır / Taşı / Sürümlere Dön, sekmeler, Bul-Değiştir, Paylaş, HTML/PDF dışa aktarma, yazdırma, Help menüsü, About + Credits.rtf, sandbox entitlement'ları, PrivacyInfo.xcprivacy, kategori (productivity), sürüm dosyası, `--appstore` derleme yolu, CI, dSYM, dosya kodlama güvenliği (BOM, satır sonu, ikili dosya kapısı).

---

## Adım 1 — Mağaza engelleri (bunlar olmadan gönderilemez)

1. ✅ **Sandbox'lı uçtan uca test (2026-11-08: aç, Farklı Kaydet, HTML ve PDF dışa aktarma geçti).** `./scripts/build-app.sh --sandbox` ile kur; aç, kaydet, Farklı Kaydet, Taşı, dışa aktar, yazdır, klasördeki görseller, sürükle-bırak. App Store kopyası sandbox'ta çalışır; bugünkü kurulu sürüm değil.
2. ✅ **Varsayılan uygulama ayarı sorun değil.** `NSWorkspace.setDefaultApplication` kullanıyor; sistem kullanıcıya onay soruyor, mağazada izinli. Otomatik ayar sadece geliştirici kurulumunda (`--make-default`, APPSTORE dışı).
3. ✅ **`network.client` kalıyor.** Test edildi: sandbox'ta WebKit bu izin olmadan hiç yüklenmiyor, Yazdır ve PDF kilitleniyordu. İnceleme notu: "Yalnızca WebKit (yazdırma/PDF) için; uygulama hiçbir istek yapmaz."
4. ✅ **Önizleme güvenliği:** `srcset` adayları tek tek denetleniyor (test: srcsetCandidatesAreChecked).
5. ⏳ **Hesap ve imza** (senin yapman gerekir, Apple hesabı): Apple Developer Program, App ID `com.ursula.quickmd`, Mac App Store provisioning profile, Distribution + Installer sertifikaları. Sonra `--appstore` → Transporter → TestFlight (Mac).
6. ⏳ **App Store Connect metinleri** (2026-11-10: taslaklar `audit/10-app-store-metinleri.md`, destek/gizlilik sayfaları `docs/`; mağaza adı "QuickMD Editor" (QuickMD alınmış); Pages yayını ve ekran görüntüleri kaldı): gizlilik politikası URL'si ("veri toplanmaz" bile olsa zorunlu), destek URL'si, açıklama, anahtar kelimeler, yaş derecesi, 1280×800+ ekran görüntüleri (açık/koyu). İsim çakışması kontrolü: "QuickMD" mağazada alınmış olabilir, önce bak.

## Adım 2 — macOS standartları (görünmez ama "profesyonel" hissi bunlar verir)

1. ✅ **Yerelleştirme: İngilizce + Türkçe (2026-11-10: `L()` + `Resources/Localization/tr.lproj`, menüler, ayarlar, uyarılar, slash menüsü, Yardım; Info.plist `CFBundleLocalizations`).** String Catalog (`Localizable.xcstrings`), Package.swift'e `defaultLocalization: "en"`. Standart menü öğeleri (Undo, Cut, Kaydet…) sistem tarafından çevrilir, sadece bizim metinler çevrilmeli.
2. ✅ **Erişilebilirlik (VoiceOver)** (2026-11-10: `Accessibility.swift`; görev kutuları basılabilir checkbox, tablolar "Tablo, N satır, M sütun" + hücreler, görseller alt metniyle. Gerçek VoiceOver ile elle deneme kaldı). Çizilen tablolar, checkbox'lar ve satır içi görseller şu an ekran okuyucuya görünmüyor. Bunlara AX metni ver; sadece klavyeyle tam kullanım testi yap.
3. ✅ **Büyük dosya koruması (zaten var: 2,5M karakter üstü düz metin, 150K üstü parça parça biçim; yerel görseller 25 MB üstü çizilmez).** Örn. 2 MB üstünde biçimlendirmeyi kapat, düz metin modunda aç (sessizce, tek satırlık bilgiyle). Donma bugün açık risk.
4. ✅ **Pencere durumu geri yükleme (2026-11-09: not başına imleç + kaydırma, `Positions.swift`; çıkış ani sonlandırma olduğu için 1 sn gecikmeli kaydediliyor).** Yeniden açılışta imleç ve kaydırma konumu aynı yerde olsun (`encodeRestorableState`). Apple'ın kendi editörleri böyle.
5. ✅ **Yazım ve Writing Tools (2026-11-09: Transformations, Speech, Writing Tools eklendi).** Edit › Spelling and Grammar, Substitutions, Speech, Writing Tools (macOS 15+) menüde ve çalışır olsun. NSTextView zaten destekliyor, menüye bağlamak yeter.
6. ✅ **Help › "Report an Issue…"** (2026-11-10, `Help.supportURL`) — destek URL'sine giden tek satır. İnceleme için de iyi.

7. ✅ **Panodan görsel yapıştırma (2026-11-09):** ekran görüntüsü notun klasörüne `Pasted image <tarih>.png` olarak kaydedilir, `![…](…)` eklenir; Finder'dan kopyalanan dosyalar link olur. Adsız notta bip.

**Güvenlik (2026-11-10):** ⌘-tık artık uygulama/betik çalıştırmaz (Finder'da gösterir), http/https/mailto dışındaki şemalar onay ister.

## Adım 3 — İsteğe bağlı, sadeliği bozmayan (sonra)

1. **Quick Look eklentisi:** Finder'da boşluk tuşuyla .md önizleme. En çok değer katan ek. Not: SwiftPM appex üretmez, bunun için küçük bir Xcode projesi gerekir — bu yüzden 1.0 sonrasına.
2. ✅ **Services (2026-11-10):** "Seçili metinle yeni QuickMD notu". Sıfır arayüz, tek Info.plist girdisi + bir fonksiyon.
3. ✅ **Bilgi penceresi (2026-11-10: Görüntü › Kelime Sayısı ⌥⌘I, sayfa olarak):** kelime/karakter sayısı. Kalıcı alt çubuk değil, sadece açınca görünür.

---

## Önerilen sıra

Adım 1.1–1.4 (kod, ~1 gün) → Adım 2.3 ve 2.4 (veri/his, ~1 gün) → Adım 2.1–2.2 (yerelleştirme + erişilebilirlik, ~2–3 gün) → Adım 1.5–1.6 (hesap, metinler, TestFlight) → gönderim. Adım 3 sürüm 1.1.

Yapılmayacaklar: Sparkle (mağazada yasak), içindekiler/outline, şablon sistemi, ek kenar çubukları.
