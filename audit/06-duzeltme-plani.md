# 06 — Düzeltme planı (denetim yorumu, 2026-11-01)

Denetim kodda kontrol edildi. Katıldıklarım plana girdi; katılmadıklarım gerekçesiyle en altta.

## Faz 1 — Depo hijyeni (bitti, 2026-11-01)

Not: 4. madde gereksizdi (playback'teki `removeAllActions()` zaten yorumlu). README'deki "Quick Look" ifadesi Quick Look'un "Open with" düğmesini kastediyor, doğru; değişmedi.

1. Çalışma ağacını commit'le: 15 değişen dosya + `scripts/quickmd-agent-hook.sh` (README buna atıf yapıyor, git'te yok).
2. Karar: `audit/` ve `CLAUDE.md` commit'lensin; `.claude/` ve `WATCHDOG.yml` `.gitignore`'a.
3. `build-app.sh --appstore`: `git status --porcelain` boş değilse dur.
4. `removeAllActions()` (EditorViewController.swift:126, :211) yanına tek satır yorum: playback undo geçmişini bilerek siler.

## Faz 2 — Sürüm ve paketleme (bitti, 2026-11-01)

Not: sayaç `Packaging/version` dosyasında (`MARKETING_VERSION` + `BUILD_NUMBER`); tag kullanılmadı. Entitlements için `Set` yerine önce `Delete` sonra `Add`.

1. `BUILD_NUMBER`: `git rev-list --count` yerine `VERSION` tag'i + artan sayaç (`Packaging/build-number` dosyası, her `--appstore` build'inde +1 ve commit). Shallow clone ve tekrar build sorunu biter.
2. Info.plist heredoc'u `Packaging/Info.plist` şablonuna taşı; script yalnız `__VERSION__`/`__BUILD__`/`__BUNDLE_ID__` değiştirsin. `PlistBuddy Add` yerine `Set` (anahtar şablonda hazır).
3. dSYM: `--appstore` modunda `dsymutil` ile `build/QuickMD.app.dSYM` üret ve arşivle.
4. Basit CI (GitHub Actions, macOS runner): `swift build` + `swift test`. Release otomasyonu sonra.

## Faz 3 — Apple hesabı ve ilk App Store build'i (hesaba bağlı, kullanıcı adımı)

1. Apple Developer Program üyeliği → Mac App Distribution + Mac Installer Distribution sertifikaları + Mac App Store provisioning profile.
2. App Store Connect'te uygulama kaydı (bundle id `com.ursula.quickmd`).
3. İlk `--appstore` build → `xcrun altool`/Transporter ile TestFlight'a yükle. Hatalar burada gerçek listeyi verir.

## Faz 4 — Uygulama cilası (kısmen bitti, 2026-11-02)

Yapıldı: Help › QuickMD Help (⌘?) yardım notunu açıyor; Save elipsissiz; çift Open Recent giderildi (AppKit kendi menüsünü ekliyor); Show Sidebar ⌃⌘S; Hide Toolbar (⌥⌘T Table'a ait, kısayolsuz); gizli ⌘= Bigger; editöre "Note" AX etiketi; Increase Contrast yüksek kontrastlı görünümü seçiyor; Reduce Motion açıkken live-writing animasyonsuz.
Kalan: "Report an Issue…" (destek URL'si Faz 6'da), yerelleştirme (4. madde).
Gereksiz çıktı: footer zaten VoiceOver'da okunan bir etiket. Durum geri yükleme NSDocument'te hazır; çıkışta pencerelerin gelmemesi sistemin "Uygulamadan çıkarken pencereleri kapat" ayarından.

1. Help menüsü: "QuickMD Help" (README/web sayfasını açar, ⌘?) + "Report an Issue…". Help book şart değil.
2. Erişilebilirlik (dar kapsam): editör metin alanına ad, footer'a etiket, özel çizilen onay kutularına rol/etiket. `Increase Contrast`'ı ezen sabit pencere görünümünü düzelt; `Reduce Motion` açıksa live-writing playback animasyonunu atla.
3. Menü cilası: ikinci boş Open Recent'i kaldır, Show/Hide Sidebar (⌃⌘S) + Toolbar (⌥⌘T) ekle, ⌘= alternatifi ekle, "Save…" → "Save".
4. Yerelleştirme altyapısı: `Localizable.xcstrings` + `String(localized:)` geçişi, önce EN, sonra TR. (Uzun iş; App Store için zorunlu değil, yayından sonra da olur.)
5. Durum geri yükleme: NSDocument'in hazır restoration'ı açılsın (açık belgeler çıkışta geri gelsin).

## Faz 5 — Görsel doğrulama (bitti, 2026-11-02)

Düzeltildi: Reading Mode'da başlıklar gizli `# ` boşluğu kadar sağa kayıyordu; başlık üstü boşluk kayboluyordu (TextKit gizli glifleri önceki satıra asıyor); Settings örneği ham `**Bold**` gösteriyordu, artık editörün stiliyle çiziliyor.
Sorunsuz: Looq koyu (çamurlu değil), açık tema, Strong cam, live-writing (kaydırıyor, vurguluyor).
Kalan: Reading Mode'da tablo/`$$`/mermaid ham (tasarım kararı); slash menü gerçek tuş vuruşu gerektirdiği için arka planda denenemedi (testleri var). Settings'in son sekmede açılması macOS standardı, değişmedi.

1. Uygulamayı çalıştır: Reading Mode, Looq teması (koyu `#1e1e1e` + glass pencere), slash menü, live-writing. Ekran görüntüleri al.
2. `audit/05` editör maddeleri: Settings Appearance yerine General'da açılsın; Settings örneği render edilmiş görünsün. Tablo/`$$`/mermaid'in editörde ham kalması tasarım kararı — şimdilik bırak.

## Faz 6 — App Store metadata

Gizlilik politikası + destek URL'si (tek sayfa yeter), 3–5 ekran görüntüsü (Faz 5'ten), yaş derecelendirmesi, `network.client` inceleme notu: "Ağ yalnızca notlarda bağlantısı verilen uzak görselleri yüklemek için."

## Katılmadıklarım / ertelediklerim

- **WKWebView/PreviewScheme "kalıntı" değil.** `RenderedPrinter` (DocumentWindowController.swift:345) Print ve Export PDF için kullanıyor; `PreviewScheme` yerel görselleri yüklüyor. Silinmemeli.
- **UTI'yi yalnız `.md`'ye indirmek `.markdown` sorununu çözmez.** İthal beyan `net.daringfireball.markdown` için standart; başka uygulamanın beyanı kazanınca bu makineye özgü bir LaunchServices çakışması olur. Beyan aynen kalsın, App Store engeli değil.
- **Swift 6 geçişi:** App Store için gerekmiyor. Ertelendi.
- **Icon Composer `.icon`:** zorunlu değil; ikon yenilenirken yapılır.
- **Quick Look eklentisi, Spotlight, Services, Dock menüsü:** zorunlu değil. Yalnız README'deki "Quick Look" vaadi düzeltilsin (Faz 1'de).
- **Reduce Transparency:** `NSVisualEffectView` bunu sistemden kendisi uygular; ek iş yok.
