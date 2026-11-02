# QuickMD — Paketleme, İmzalama, Notarization ve App Store Hazırlığı Denetimi

- **Denetim tarihi:** 2026-11-01
- **Depo:** `/Users/ihsan/Desktop/macOS_Dev/quickmd` (branch `main`, HEAD `9803cde`, **çalışma ağacı kirli:** 20 dosya değişmiş, `+2595/−438`, `scripts/build-app.sh` dahil). **Yalnızca 25 dosya git'te izleniyor**; `Packaging/`, `Resources/`, `Tests/` ve 6 Swift kaynak dosyası **untracked** — bu yüzden HEAD'den alınan klon güncel uygulamayı üretmiyor; **App Store paketleme akışı hiçbir commit'te yok** (bkz. **B-00**).
- **Ortam:** macOS 15.7.9 (24G830), **yalnızca Command Line Tools** (`xcode-select -p` → `/Library/Developer/CommandLineTools`), Swift 6.1.2, `xcodebuild` **yok**, `security find-identity -v -p codesigning` → **0 geçerli kimlik**
- **Kural:** kaynak kod değiştirilmedi; yalnızca bu rapor yazıldı. Tüm araç çıktıları salt-okunur çalıştırıldı (bazı testler `/tmp` kopyaları üzerinde).
- **Kısıt:** Bu makinede imza kimliği, provisioning profile ve Xcode olmadığı için **imzalı/notarize edilmiş akışlar uçtan uca çalıştırılamadı**; bu tür iddialar aşağıda açıkça "doğrulanmadı" olarak işaretlendi. macOS 26 (Tahoe) ortamı yok; Icon Composer beklentisi yalnızca Apple HIG belgesiyle karşılaştırıldı.

Denetimde kullanılan başlıca komutlar: `plutil -lint/-p`, `iconutil -c iconset`, `codesign -dv/-d --entitlements/--verify`, `spctl -a`, `pkgutil --check-signature`, `productbuild` (imzasız deneme), `swift build` (normal ve `-DAPPSTORE`), `swift test`, `dwarfdump -u`, `lipo -info/-thin`, `strip -x`, `otool -l` (minos), `lsregister -dump`, `UTType` sorgusu (Swift), `git rev-list --count`, `git clone --depth 1`, ad-hoc sandbox test uygulaması.

---

## 0. Yönetici özeti

| Önem | Adet | Konu |
|---|---|---|
| **Blocker** | 4 | **Release/paketleme girdileri git'te yok** (HEAD klonu 96 satırlık eski 0.1.0 script'ini üretiyor; `--appstore`/entitlements/Resources commit dışı); notarization/staple/DMG yok; App Store hattı hiç üretilmemiş + kimlik yok; `BUILD_NUMBER` tekillik garantisi yok |
| **High** | 5 | dSYM toplanmıyor; UTI çakışması; CI/release otomasyonu yok; `--appstore` doğrulaması yok; sürüm/plist tek kaynak değil |
| **Medium** | 7 | macOS 26 ikon beklentisi; güncelleme kanalı yok; artefakt kimliği karışıyor; PrivacyInfo gerekçe uyumu; ad-hoc kimlik/TCC; `altool` talimatı CLT'de çalışmıyor; App Store metadata yok |
| **Low** | 8 | `--deep`, Help Book/lokalizasyon/TCC usage string'leri, `PkgInfo`, `--install` hata yolu, pkg adı, `.build-universal` temizliği, çift `swift build`, `PlistBuddy Add` kırılganlığı |
| **Doğrulanmadı** | 9 | macOS 26 `.icon` zorunluluğu, TCC reset, bookmark geçersizliği, ASC red kuralı, reason-code semantiği, macOS'ta required-reason zorunluluğu, imzalı akışların hiçbiri (kimlik yok) |

**Olumlu/doğrulanan taraflar (bulgu değil):** uygulama evrensel (x86_64+arm64), `minos 13.0`; ikon `.icns` geçerli ve **16→1024 px, 10 temsil, Apple'ın 824/1024 ızgarasına tam oturuyor**; tüm plist'ler `plutil -lint` OK; kaynaklar imzayla mühürlü (`codesign --verify --strict` geçiyor); `PrivacyInfo.xcprivacy` paket içinde doğru yerde ve mühürlü; sandbox build ad-hoc olarak **çalışıyor**; `FolderAccess.isSandboxed` ortam değişkeni kontrolü sandbox'lı test uygulamasında **doğrulandı**; 38 test geçiyor; `-DAPPSTORE` varyantı temiz derleniyor ve geliştirici CLI'ı çalışma anında yok (GUI açılıyor); paket içinde üçüncü parti framework/helper/XPC yok.

---

## 1. BLOCKER

### B-00 — Release/paketleme işi git'te **yok**: HEAD'deki script 0.1.0 üretiyor, güncel paketleme akışı yalnızca commit edilmemiş çalışma ağacında

> Bu, denetimde bulunan **en kritik** sorundur: aşağıdaki diğer tüm düzeltmeler, önce bu giderilmeden anlamsızdır.

- **Kanıt**
  - `git ls-files | wc -l` → **25** izlenen dosya; `git rev-list --count HEAD` → 3. Çalışma ağacında ise 24 Swift kaynağı + `Packaging/` + `Resources/` + `Tests/` var, çünkü çoğu **hiç commit edilmemiş**.
  - `git status --porcelain | grep '^??'`:
    ```
    ?? Packaging/                      ← QuickMD.entitlements, PrivacyInfo.xcprivacy, Credits.rtf (tamamı)
    ?? Resources/                      ← Fonts, katex, mermaid (uygulamanın tüm çalışma zamanı varlıkları)
    ?? Sources/QuickMD/FolderAccess.swift
    ?? Sources/QuickMD/SettingsWindow.swift
    ?? Sources/QuickMD/Starters.swift
    ?? Sources/QuickMD/SyntaxHighlighter.swift
    ?? Sources/QuickMD/TableEditing.swift
    ?? Sources/QuickMD/Template.swift
    ?? Tests/                          ← 38 testin tamamı
    ?? WATCHDOG.yml
    ```
  - Temiz klon kanıtı: `git clone file:///Users/ihsan/Desktop/macOS_Dev/quickmd /tmp/qa-shallow2` sonrası
    - `ls` → yalnızca `.gitignore LICENSE Package.swift README.md Sources scripts` (**`Packaging/` ve `Resources/` yok**)
    - `Sources/QuickMD/*.swift`: klonda **18**, çalışma ağacında **24** (6 kaynak dosya eksik); `Tests/` dizini hiç yok
    - **`swift build` klonda BAŞARILI (exit 0, 144.43 s)** — çünkü HEAD, kendi içinde tutarlı **eski bir 0.1.0 sürümüdür**; eksik dosyalar yeni özelliklerdir. Yani sorun "klon derlenmiyor" değil, **klonun güncel uygulamayı üretmemesi**.
  - **Asıl kanıt — git'teki build script'i güncel değil:** klondaki `scripts/build-app.sh` **96 satır** ve içinde `--appstore`, `--sandbox`, `productbuild`, `PROVISIONING_PROFILE`, `BUILD_NUMBER`, entitlements/PrivacyInfo/Resources kopyalama **hiç yok**:
    - `grep -n "appstore|sandbox|productbuild|PROVISIONING" scripts/build-app.sh` (klon) → **hiç eşleşme**; `VERSION="${VERSION:-0.1.0}"` (satır 6); `CFBundleVersion` = `$VERSION`; `codesign --force --deep --sign -` (satır 86).
    - Çalışma ağacındaki script **157 satır** ve `--appstore` entitlement/profil/productbuild akışı, `BUILD_NUMBER`, `--sandbox` burada. `git diff --stat HEAD -- scripts/build-app.sh` → **+76/−15**. Yani **App Store paketleme yolu hiçbir commit'te yok**.
  - Build script'i bu dosyalara **doğrudan bağımlı** (güncel sürüm): `scripts/build-app.sh:25` (`$ROOT/Packaging/QuickMD.entitlements`), `:56` (`cp -R Resources/Fonts Resources/katex Resources/mermaid`), `:58` (`PrivacyInfo.xcprivacy`, `Credits.rtf`), `:53` (`scripts/AppIcon.icns` — bu izleniyor ✓), `:120` (`plutil -lint`).
- **Neden önemli:** Bugün var olan `build/QuickMD.app` ve planlanan `--appstore`/`--sandbox` çıktıları **hiçbir commit'ten yeniden üretilemez**; `git archive`/temiz klonla release alınamaz, CI kurulamaz, App Store'a gönderilecek ikilinin kaynağı kanıtlanamaz ve `--appstore` akışı bir `git clean`/kaza ile **tamamen kaybolabilir**. H-03'teki CI, B-03'teki commit-sayısı sürümlemesi ve H-01'deki dSYM eşleştirmesi de bu yüzden anlamsızlaşıyor. Bu hâliyle "depodan dağıtım" yok.
- **Somut düzeltme:**
  1. Eksik dosyaları ekle: `git add Packaging Resources Tests Sources/QuickMD/{FolderAccess,SettingsWindow,Starters,SyntaxHighlighter,TableEditing,Template}.swift` (ve `WATCHDOG.yml` için karar ver: ya ekle ya `.gitignore`'a).
  2. `.gitignore`'u gözden geçir: `build/` ve `*.app` (satır 24, 26) doğru; `Resources/`'ı dışlayan desen yok — sorun desen değil, **hiç eklenmemiş olması**.
  3. Release kapısı koy: `git status --porcelain` boş değilse ve `git ls-files --error-unmatch Packaging/QuickMD.entitlements Resources/Fonts/Inter.ttf Tests/QuickMDTests/EditorTests.swift` başarısızsa build script'i dursun; CI'da aynı kontrol.
  4. `LICENSE` dosyasındaki Wisp türevi içerik korunmalı (izleniyor ✓); sürüm numarası `HEAD`'den değil tag/sayaçtan gelsin (B-03).

---

### B-01 — App Store dışı dağıtım yolu hiç yok: notarization + staple + DMG/zip yok, Gatekeeper reddediyor

- **Kanıt**
  - `scripts/build-app.sh` yalnızca 4 mod içeriyor: `--appstore`, `--sandbox`, `--install`, varsayılan (satır 4–7, 124–157).
  - `grep -rni "notar|stapler|notarytool|\.dmg|create-dmg|ditto -c|hdiutil|sparkle" scripts/ README.md` → **hiç eşleşme yok**. Yani `notarytool`, `stapler`, `.zip`, `.dmg` üretimi depoda hiçbir yerde yok.
  - `spctl -a -vvv -t exec build/QuickMD.app` → `build/QuickMD.app: rejected` (exit 3).
  - `codesign -dv --verbose=4 build/QuickMD.app` → `Signature=adhoc`, `flags=0x2(adhoc)`, `TeamIdentifier=not set`.
  - `scripts/build-app.sh:122` `xattr -cr "$APP_DIR"` yalnızca **yerel** kopyadan karantinayı siliyor; indirilen bir kopya bu adımdan geçmez.
- **Neden önemli:** "Gerçek bir Apple macOS uygulaması" için iki dağıtım kanalı vardır: (1) Mac App Store, (2) Developer ID + **notarization + staple** ile doğrudan indirme (dmg/zip). Depoda (2) tamamen yok; üretilen her binary ad-hoc olduğu için indirilen kopya Gatekeeper tarafından reddedilir. Bugünkü hâliyle QuickMD yalnızca kendi makinesinde çalışan bir geliştirme çıktısıdır.
- **Somut düzeltme:** `--dist` modu ekle (Developer ID Application + hardened runtime + timestamp; zip/dmg üret; notarytool; staple; doğrula):

```bash
# scripts/build-app.sh içine yeni mod
--dist)
  : "${DEVELOPER_ID:?Developer ID Application kimliği gerekli (güvenlik açısından ayrı bir 'Developer ID Application' sertifikası)}"
  codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "$APP_DIR"
  codesign --verify --strict --verbose=2 "$APP_DIR"
  spctl -a -vvv -t exec "$APP_DIR"            # notarize öncesi yerel kabul testi

  VERSIONED="QuickMD-$VERSION-$BUILD_NUMBER"
  rm -rf "$ROOT/dist" && mkdir -p "$ROOT/dist"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ROOT/dist/$VERSIONED.zip"
  hdiutil create -volname "QuickMD" -srcfolder "$APP_DIR" -ov -format UDZO \
      "$ROOT/dist/$VERSIONED.dmg"

  xcrun notarytool submit "$ROOT/dist/$VERSIONED.dmg" \
      --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$ROOT/dist/$VERSIONED.dmg"
  xcrun stapler validate "$ROOT/dist/$VERSIONED.dmg"
  spctl -a -vvv -t open --context context:primary-signature "$ROOT/dist/$VERSIONED.dmg"
  ;;
```

  Ek olarak: `notarytool` için keychain profili (`xcrun notarytool store-credentials`) ve App Store Connect API anahtarı dokümante edilmeli; DMG'ye uygulama simgesi + `/Applications` kısayolu eklenmeli.

---

### B-02 — App Store gönderim hattı hiç uçtan uca üretilmemiş; kimlik/profil yok, upload aracı yok

- **Kanıt**
  - `security find-identity -v -p codesigning` → **`0 valid identities found`**. Yani `SIGN_IDENTITY`/`INSTALLER_IDENTITY` olarak kullanılabilecek hiçbir sertifika bu makinede yok.
  - `ls -la build/` → yalnızca `QuickMD.app`; **`build/QuickMD.pkg` hiç üretilmemiş** (README:29 ve script:134 pkg üretimini vaat ediyor).
  - `xcodebuild -version` → `requires Xcode, but active developer directory … is a command line tools instance`; `xcrun altool --version` → `unable to find utility "altool"`. `scripts/build-app.sh:136–137` ise kullanıcıya **`xcrun altool --validate-app … --apiKey … --apiIssuer …`** öneriyor — bu makinede çalışmaz.
  - `xcrun notarytool --version` → `1.0.0 (38)`, `xcrun stapler` çalışıyor (araç var, kimlik yok).
  - Build script'i `TEAM_ID`, `SIGN_IDENTITY`, `INSTALLER_IDENTITY`, `PROVISIONING_PROFILE` değişkenlerinin **yalnızca boş olup olmadığını** kontrol ediyor (satır 30–33); sertifika/profil geçerliliğini kontrol etmiyor.
- **Neden önemli:** App Store'a gönderim bugün imkânsız; README'deki "Mac App Store: …" ifadesi çalışmayan bir talimat. Üstelik ilk gerçek `--appstore` denemesi sertifika/profil aşamasında patlayacak ve o ana kadar yapılan iş (evrensel derleme, imza) çöpe gidecek.
- **Somut düzeltme:** Script başına preflight ekle; kimlik bilgisi yönetimini dokümante et (CI secrets):

```bash
# --appstore öncesi preflight
security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" \
  || { echo "error: $SIGN_IDENTITY keychain'de yok (Xcode > Settings > Accounts)"; exit 1; }
security find-identity -v -p codesigning | grep -q "$INSTALLER_IDENTITY" \
  || { echo "error: $INSTALLER_IDENTITY keychain'de yok"; exit 1; }
xcrun --find altool >/dev/null 2>&1 \
  || echo "warning: altool yok (Xcode gerekli); Transporter uygulamasıyla yükle"
# profil tipi/bundle id/team doğrulaması (H-04'teki snippet)
```

---

### B-03 — `CFBundleVersion` git commit sayısından üretiliyor: tekillik ve monotonluk garantisi yok

- **Kanıt**
  - `scripts/build-app.sh:23`: `BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"`; `:74–75` bu değer doğrudan `CFBundleShortVersionString`/`CFBundleVersion` oluyor.
  - Tam depoda `git rev-list --count HEAD` → **3**.
  - Shallow klon simülasyonu: `git clone --depth 1 file:///Users/ihsan/Desktop/macOS_Dev/quickmd /tmp/qa-shallow2` → `git rev-list --count HEAD` → **1** (`is-shallow-repository: true`). Yani CI'da tipik `actions/checkout` (depth 1) build numarasını **1**'e düşürür.
  - Git deposu olmayan bir tarball'da `git rev-list --count HEAD 2>/dev/null || echo 1` → **1** (script'in kendi fallback'i).
  - Çalışma ağacı kirli: 20 dosya değişmiş (`git diff --stat`: `+2595/−438`), `scripts/build-app.sh` dahil. Aynı commit numarasıyla **farklı binary** üretilebiliyor.
  - Hiçbir format/numara doğrulaması yok: `BUILD_NUMBER=abc` veya `VERSION=1.0.0-beta` sessizce plist'e yazılır (`plutil -lint` yalnızca XML geçerliliğini kontrol eder, App Store kurallarını değil).
- **Neden önemli:** App Store Connect, aynı `CFBundleShortVersionString` altında `CFBundleVersion`'ın **kesin artan** olmasını zorunlu kılar; düşen veya yinelenen bir numara upload'ı reddeder ("build number must be higher than the previous"). Shallow clone (1), fallback (1) ve aynı commit'ten tekrar build durumları bu reddi garanti eder; ayrıca farklı ikili aynı build numarasıyla gönderilemez. B-00 nedeniyle commit sayısı ile derlenen ikili arasında **hiçbir ilişki de yok**: 3 commit sayılıyor ama 6 kaynak dosya + `Packaging/` + `Resources/` commit edilmemiş.
- **Somut düzeltme:** Tek doğruluk kaynağı **git tag** olsun; build numarası ASC'den kontrol edilsin veya monoton bir sayaç dosyası/CI run number'dan gelsin; formatı doğrula:

```bash
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "error: VERSION geçersiz: $VERSION"; exit 1; }

# Kirli ağaçla release yok (veya en az uyarı)
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || {
  echo "error: çalışma ağacı kirli; release build sadece temiz commit'ten"; exit 1; }

# Sayaç dosyası (repo içinde, commit'li): her release'de +1
COUNTER="$ROOT/Packaging/build-number.txt"
BUILD_NUMBER="${BUILD_NUMBER:-$(( $(cat "$COUNTER" 2>/dev/null || echo 0) + 1 ))}"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "error: BUILD_NUMBER geçersiz"; exit 1; }
```

  Yayın öncesi ASC kontrolü (imza/anahtar varsa): `xcrun altool --list-builds …` / `notarytool` yerine App Store Connect API ile son build numarasını doğrula.

---

## 2. HIGH

### H-01 — dSYM üretiliyor ama toplanmıyor/arşivlenmiyor; crash raporları sembolize edilemez

> Görev tanımındaki "dSYM üretilmiyor" iddiası **düzeltildi**: SwiftPM release derlemesinde dSYM üretiyor. Sorun üretim değil, **toplanmaması**.

- **Kanıt**
  - `.build-universal/arm64-apple-macosx13.0/arm64-apple-macosx/release/QuickMD.dSYM` ve `.build-universal/x86_64-…/release/QuickMD.dSYM` **mevcut**.
  - UUID eşleşmesi doğrulandı: dSYM arm64 `UUID: 42AF9CE5-7151-313E-8D96-46847ADF44C1` = nihai binary'nin arm64 UUID'si; dSYM x86_64 `913B242D-1411-382B-A754-B6CDA92F8909` = nihai binary'nin x86_64 UUID'si. `strip -x` UUID'yi değiştirmiyor (test: aynı UUID, yalnızca kod imzası geçersizleşiyor — imza zaten sonradan atılıyor).
  - Ancak: `find build -name "*.dSYM"` → **boş**. `scripts/build-app.sh:41–48` iki mimariyi derliyor, `lipo` + `strip -x` yapıyor; **dSYM'leri `build/` veya `dist/` altına kopyalayan, birleştiren, arşivleyen tek satır yok**. App Store Connect'e dSYM yükleme adımı da yok.
- **Neden önemli:** `strip -x` sonrası crash raporu adresleri yalnızca dSYM ile çözülebilir. Bugün üretilen dSYM'ler `.build-universal/` içinde (gitignore'da) duruyor; her temizlikte kaybolur, sürümle eşleştirilemez. Sahada çökme olduğunda "hangi sürüm, hangi sembol" bilinemez — dağıtılabilir bir macOS uygulaması için kabul edilemez.
- **Somut düzeltme:**

```bash
# lipo/strip'ten sonra, imzalamadan hemen sonra:
DSYM_DIR="$ROOT/build/dSYMs/$VERSION-$BUILD_NUMBER"
mkdir -p "$DSYM_DIR"
cp -R "$ARCH_DIR/arm64-apple-macosx13.0/arm64-apple-macosx/release/QuickMD.dSYM"   "$DSYM_DIR/QuickMD-arm64.dSYM"
cp -R "$ARCH_DIR/x86_64-apple-macosx13.0/x86_64-apple-macosx/release/QuickMD.dSYM" "$DSYM_DIR/QuickMD-x86_64.dSYM"
# veya tek evrensel dSYM:
# dsymutil "$APP_DIR/Contents/MacOS/QuickMD" -o "$DSYM_DIR/QuickMD.dSYM"
dwarfdump --uuid "$APP_DIR/Contents/MacOS/QuickMD" > "$DSYM_DIR/uuids.txt"
dwarfdump --uuid "$DSYM_DIR"/*.dSYM        >> "$DSYM_DIR/uuids.txt"   # eşleşmeyi kanıtla
```

  Ardından CI'da artefakt olarak sakla + crash raporlama kullanılıyorsa (Sentry/BugSentry/Apple) dSYM'leri otomatik yükle. App Store paketiyle birlikte dSYM'lerin de saklanması ve gerekirse App Store Connect'e yüklenmesi süreç adımı olarak eklenmeli.

---

### H-02 — `UTImportedTypeDeclarations` çakışması: mime/uzantı beyanları sistemdeki diğer beyanlarla çelişiyor, belgelenen uzantılar QuickMD'ye atanmıyor

- **Kanıt (depo)**
  - `scripts/build-app.sh:102–116`: `UTTypeIdentifier = net.daringfireball.markdown`, `UTTypeConformsTo = public.plain-text`, `public.mime-type = text/markdown`, uzantılar `md, markdown, mdown, mkd, mdwn`.
  - `scripts/build-app.sh:91`: `LSItemContentTypes = net.daringfireball.markdown`, `LSHandlerRank = Default`; `:98` düz metin için `Alternate` (bu kısım doğru).
- **Kanıt (sistem, bu makinenin LaunchServices veritabanı)**
  - `UTType(filenameExtension:)` sorgusu (Swift, `UniformTypeIdentifiers`):
    - `md → net.daringfireball.markdown` ✓
    - `markdown → com.looq.markdown`, `mdown → com.looq.markdown`, `mkd → com.looq.mkd`, `mdwn → com.looq.markdown` ✗
  - Yani QuickMD'nin `UTImportedTypeDeclarations` ile sahiplenmeye çalıştığı `markdown/mdown/mkd/mdwn` uzantıları **başka bir uygulamanın (Obsidian / `com.looq.*`) beyanına** bağlı; QuickMD `NoteLinks.noteExtensions` (`Sources/QuickMD/FolderAccess.swift:61`) ve `LSItemContentTypes` ile bu uzantıları bekliyor ama macOS onları QuickMD'ye açmıyor.
  - Aynı UTI'yi makinede **13+ bundle** import ediyor; Apple'ın kendi **Shortcuts** uygulaması da bunlardan biri ve tag seti farklı:
    - `lsregister -dump`: `type id: net.daringfireball.markdown`, `bundle: Shortcuts`, `flags: active apple-internal imported trusted`, `conforms to: public.plain-text`, `tags: .md, text/x-markdown`
    - QuickMD ise `tags: .md, .markdown, .mdown, .mkd, .mdwn, text/markdown` yazıyor.
  - CoreTypes/`/System/Library` içinde **sistem beyanı yok** (`grep -rl net.daringfireball.markdown /System/Library/CoreServices …` → boş; `/System/Library/CoreServices/CoreTypes.bundle/Contents/Info.plist` içinde markdown yok). Yani görev tanımındaki "sistemin zaten tanımladığı tip" ifadesi **kısmen doğru**: UTI'yi fiilen Apple'ın Shortcuts uygulaması (ve diğer uygulamalar) *import* ediyor; sistemin *export* ettiği bir tip değil.
- **Neden önemli:** (a) `public.mime-type` çelişkisi (Apple Shortcuts `text/x-markdown` ↔ QuickMD `text/markdown`) LaunchServices'te belirsizlik/uyarı üretir; (b) QuickMD, sahibi olmadığı uzantıları ithal ederek başka uygulamaların dosya ilişkilendirmesini itmeye çalışıyor ve bu **fiilen çalışmıyor** (yukarıdaki sorgu); (c) `LSHandlerRank = Default` ile birlikte bu, kullanıcıya "QuickMD .markdown açar" vaadi verip açmaması demek. App Store incelemesinde doğrudan ret nedeni değil, ama "gerçek Apple uygulaması" uyum/UX sorunudur.
- **Somut düzeltme:** İthal beyanı **minimal** tut — tag çakışması yaratma; uzantı sahipliği iddia etme:

```xml
<!-- Öneri: yalnızca kimlik + uyum + Apple'ın kullandığı tag seti -->
<key>UTImportedTypeDeclarations</key>
<array><dict>
  <key>UTTypeIdentifier</key><string>net.daringfireball.markdown</string>
  <key>UTTypeDescription</key><string>Markdown Document</string>
  <key>UTTypeConformsTo</key><array><string>public.plain-text</string></array>
  <key>UTTypeTagSpecification</key><dict>
    <key>public.filename-extension</key><array><string>md</string></array>
    <key>public.mime-type</key><string>text/x-markdown</string>  <!-- Apple Shortcuts ile aynı -->
  </dict>
</dict></array>
```

  Alternatif (daha temiz): plist'te hiç tag spec vermeyip kodu `UTType(importedAs: "net.daringfireball.markdown")` kullanacak şekilde yaz; `.markdown/.mdown/.mkd/.mdwn` desteğini **kendi exported UTI'niz** olarak tanımlamak istiyorsanız ayrı `UTExportedTypeDeclarations` + `com.…quickmd.markdown` gibi kendi tanımlayıcınızla yapın ve `LSItemContentTypes`'a ekleyin. Ayrıca `NoteLinks.noteExtensions` listesini gerçekten açılabilen uzantılarla uyumlayın (çalışma anında `NSWorkspace.shared.urlForApplication(toOpen:)` ile doğrulama).

---

### H-03 — CI / release otomasyonu yok: test kapısı, artefakt arşivi, imzalama sırrı yönetimi, tag/changelog yok

- **Kanıt**
  - `.github/` dizini yok; `find . -maxdepth 3 -name "*.yml"` yalnızca `WATCHDOG.yml` (içeriği: `advisors: - name: Advisor 2 …`, yani AI danışman konfigürasyonu — CI değil).
  - `git tag` → **boş** (hiç release etiketi yok). `Makefile`, `fastlane/`, `*.xcodeproj`, `CHANGELOG*` yok.
  - `scripts/build-app.sh:16–148` test çalıştırmıyor; `swift test` ayrı ve manuel (`README:26`). Testler bu denetimde geçti: **38/38** (`swift test --scratch-path /tmp/qa-test-build`).
  - İmzalama sırları env değişkenleriyle elle veriliyor (satır 9–13, 30–33); saklama/yönetim/döndürme politikası yok.
- **Neden önemli:** Release adımları tamamen insan elinde; (a) test edilmemiş commit paketlenebilir, (b) hangi commit'in hangi artefaktı ürettiği izlenemez, (c) sırlar geliştirici makinesinde, (d) "her seferinde aynı" çıktı garantisi yok. Dahası bugün CI kurulsa bile **güncel paketleme akışı klonda yok** (B-00): izlenen dosya sayısı 25, `Tests/`/`Packaging/`/`Resources/` ve 6 Swift dosyası git'te yok; HEAD'in 96 satırlık script'i yalnızca 0.1.0 sürümünü üretiyor. App Store'a hazırlanan bir üründe bu, insan hatasıyla ret/kesinti demektir.
- **Somut düzeltme:** `.github/workflows/release.yml` taslağı:

```yaml
name: release
on:
  push: { tags: ['v*'] }
jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }          # rev-list --count için tam geçmiş
      - name: Test
        run: swift test
      - name: Import signing certificate
        env: { CERT_P12: ${{ secrets.BUILD_CERT_P12 }}, CERT_PASS: ${{ secrets.BUILD_CERT_PASS }} }
        run: |
          echo "$CERT_P12" | base64 -d > /tmp/cert.p12
          security create-keychain -p "$RUNNER_TEMP" build.keychain
          security import /tmp/cert.p12 -k build.keychain -P "$CERT_PASS" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "$RUNNER_TEMP" build.keychain
      - name: Build + package
        run: ./scripts/build-app.sh --appstore
        env:
          TEAM_ID: ${{ secrets.TEAM_ID }}
          SIGN_IDENTITY: ${{ secrets.SIGN_IDENTITY }}
          INSTALLER_IDENTITY: ${{ secrets.INSTALLER_IDENTITY }}
          PROVISIONING_PROFILE: ${{ runner.temp }}/profile.provisionprofile
      - uses: actions/upload-artifact@v4
        with: { name: QuickMD-${{ github.ref_name }}, path: "build/**" }   # app, pkg, dSYMs
```

---

### H-04 — `--appstore` akışında ön/son doğrulama yok: profil, bundle id, sandbox, pkg imzası, timestamp denetlenmiyor

- **Kanıt**
  - `scripts/build-app.sh:29–37`: yalnızca env değişkenlerinin dolu ve profilin dosya olarak var olup olmadığı kontrol ediliyor. **Profilin tipi** (Mac App Store mı, Development mı?), `application-identifier`'ın `$TEAM_ID.$BUNDLE_ID` ile eşleşmesi, `get-task-allow=false` olması, `provisionsAllDevices` **doğrulanmıyor**.
  - `:126` `cp "$PROVISIONING_PROFILE" "$APP_DIR/Contents/embedded.provisionprofile"` (konum doğru, imzadan önce — iyi). `:127–130` entitlements kopyasına `com.apple.application-identifier` / `com.apple.developer.team-identifier` ekleniyor; ancak `/usr/libexec/PlistBuddy -c "Add :…"` kullanılıyor — anahtar zaten varsa komut hata verir ve `set -euo pipefail` yüzünden script **yarıda ölür** (mevcut dosyada anahtarlar olmadığı için bugün çalışır; kırılgan).
  - `:131–133` app imzalanıp `codesign --verify --deep --strict` ediliyor; fakat **nihai imzanın sandbox entitlement'ını içerdiği** (`codesign -d --entitlements :-`), profile'ın app içine doğru konduğu, `get-task-allow` bulunmadığı doğrulanmıyor.
  - `:134` `productbuild … --sign "$INSTALLER_IDENTITY"` sonrası `pkgutil --check-signature`, `spctl -a -t install`, `--timestamp` **yok**. `man productbuild` (satır 464–469): trusted timestamp **yalnızca Developer ID kimliğinde varsayılan**; 3rd Party Mac Developer Installer ile imzalanan pkg'de timestamp yoktur (App Store için zorunlu değil, ama ileride notarize edilecek her pkg için gerekli).
  - App Store Connect build numarası kontrolü yok (bkz. B-03).
- **Neden önemli:** Yanlış tipte profil veya bundle-id uyuşmazlığı, saatler süren derleme + imzadan **sonra** Apple tarafında reddedilir; hata mesajı da genellikle belirsizdir. Sandbox entitlement'ının son imzada olup olmadığını doğrulamamak, App Store'un en temel reddi olan "app is not sandboxed" ile sonuçlanır.
- **Somut düzeltme:**

```bash
# --appstore içinde, imza sonrası:
PLIST=$(mktemp /tmp/profile.XXXX.plist)
security cms -D -i "$PROVISIONING_PROFILE" > "$PLIST"
/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$PLIST" \
  | grep -qx "$TEAM_ID.$BUNDLE_ID" || { echo "error: profil bundle id uyuşmuyor"; exit 1; }
/usr/libexec/PlistBuddy -c "Print :Entitlements:get-task-allow" "$PLIST" 2>/dev/null \
  | grep -qx false || { echo "error: App Store dışı (development) profil"; exit 1; }

codesign -d --entitlements :- "$APP_DIR" 2>/dev/null | plutil -extract com.apple.security.app-sandbox raw - \
  | grep -qx true || { echo "error: sandbox entitlement imzada yok"; exit 1; }
codesign -d --entitlements :- "$APP_DIR" 2>/dev/null | grep -q get-task-allow \
  && { echo "error: get-task-allow imzada olmamalı"; exit 1; }

pkgutil --check-signature "$ROOT/build/$NAME.pkg" | grep -q "signed by a developer certificate" \
  || { echo "error: pkg imzası doğrulanamadı"; exit 1; }
spctl -a -vvv -t install "$ROOT/build/$NAME.pkg"
# productbuild çağrısına --timestamp ekle (ileride notarize edilecekse):
#   productbuild --component "$APP_DIR" /Applications --timestamp --sign "$INSTALLER_IDENTITY" …
```

  `PlistBuddy -c "Add"` yerine önce sil sonra ekle: `PlistBuddy -c "Delete :com.apple.application-identifier" … 2>/dev/null || true` + `Add`.

---

### H-05 — Info.plist tek doğruluk kaynağı değil (script içinde heredoc) ve sürüm alanları doğrulanmıyor

- **Kanıt**
  - Info.plist `scripts/build-app.sh:61–119` içinde **heredoc** olarak üretiliyor; depoda `Packaging/Info.plist` şablonu **yok**. 21 anahtar elle yazılmış; tek doğrulama `plutil -lint` (satır 120) — yani "XML bozuk değil" kontrolü, "App Store için doğru anahtarlar/format" kontrolü değil.
  - Sürüm alanları env'den geliyor (`:19`, `:23`, `:74–75`) ve **format doğrulanmıyor**: `VERSION="1.0.0 & beta"` geçersiz plist üretir (script ancak build bittikten sonra, satır 120'de patlar); `VERSION="1.0.0-beta"` ise `CFBundleShortVersionString` için App Store kuralına aykırıdır.
  - `CFBundleVersion` = commit sayısı (B-03). `BUNDLE_ID` varsayılanı `com.ursula.quickmd` (satır 21) — Wisp türevi bir isim; ASC'de kayıtlı kimlikle eşleştiğini doğrulayan hiçbir adım yok.
  - İkon tarafı: `CFBundleIconFile=AppIcon` var (`:68`), `CFBundleIconName`/`Assets.car` yok (şimdiki `.icns` yolu için gerekmez; macOS 26 katmanlı ikon yoluna geçilirse gerekir — bkz. M-01).
- **Neden önemli:** Sürüm/anahtar hataları en pahalı hatalardır: App Store Connect, `CFBundleShortVersionString` formatını ve `CFBundleVersion` tekilliğini reddeder; hata ancak upload sırasında görülür. Heredoc yaklaşımı ayrıca plist'i kodla birlikte diff'lenemez, gözden geçirilemez hâle getiriyor.
- **Somut düzeltme:** `Packaging/Info.plist` şablonunu depoya koy; build sırasında **değerleri enjekte et**, dosyayı lint'le:

```bash
cp "$ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER"             "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID"             "$APP_DIR/Contents/Info.plist"
plutil -lint "$APP_DIR/Contents/Info.plist"
# ek doğrulama: App Store'un istediği anahtarlar mevcut mu?
for k in CFBundleIdentifier CFBundleExecutable CFBundleShortVersionString CFBundleVersion \
         LSMinimumSystemVersion LSApplicationCategoryType ITSAppUsesNonExemptEncryption NSPrincipalClass; do
  /usr/libexec/PlistBuddy -c "Print :$k" "$APP_DIR/Contents/Info.plist" >/dev/null || \
    { echo "error: eksik anahtar $k"; exit 1; }
done
```

---

## 3. MEDIUM

### M-01 — macOS 26 (Liquid Glass) ikon beklentisi karşılanmıyor: ön-maskelenmiş bitmap + gömülü gölge, Icon Composer/.icon ve `Assets.car` yok

- **Kanıt**
  - İkon **geçerli**: `iconutil -c iconset scripts/AppIcon.icns` → exit 0; 10 temsil: 16/32/64/128/256/512/1024 px; 1024 `icon_512x512@2x.png` doğrulandı. Geometri Apple'ın macOS ızgarasına **tam oturuyor**: `alpha≥128` sınır kutusu `(100,100,924,924)` → 824×824 karo, 100 px kenar boşluğu; `scripts/generate-icon.swift:70–73` bunu açıkça hedefliyor.
  - Ancak ikon **bitmap ve ön-maskelenmiş**: `generate-icon.swift:73–84` squircle'ı kendisi çizip **gölgeyi de pişiriyor** (`setShadow`, `blur: 26 * unit`); `.icon`/Icon Composer dosyası, `Assets.car`, `CFBundleIconName` yok.
  - Apple HIG "App icons" (güncelleme **28 Ekim 2026**): iOS/iPadOS/**macOS** için iki format — bitmap veya **katmanlı Icon Composer** dosyası; "Provide your icon in the Icon Composer format for more flexibility and control"; "Produce appropriately shaped, **unmasked** layers. The system masks all layer edges"; "Let the system handle … drop shadows … there's no need to include specular highlights, drop shadows, beveled edges, blurs, glows". Bitmap seçilirse sistem ikonu segmentleyip katmanlaştırır.
- **Neden önemli:** macOS 26'da Liquid Glass ikonları katman/specular efektiyle çizilir; ön-maskelenmiş + gömülü gölgeli bitmap, sistem maskesiyle birleşince kenarlarda çift maske/jagged specular ve diğer simgelerle orantısız görünüm üretir. App Store incelemesi için **doğrulanmadı** (zorunluluk belgesi bu ortamda teyit edilemedi), ancak "gerçek Apple uygulaması" beklentisi ve gelecek macOS sürümleri için Medium.
- **Somut düzeltme:** Xcode 26 + Icon Composer ile katmanlı `.icon` üret (arka plan + `md` ön katmanı); asset catalog'a ekle, `CFBundleIconName` kullan. Gömülü gölgeyi üreticiden kaldır (sistem ekliyor), squircle maskelemeyi bırak (sistem maskeliyor) — bitmap fallback'i yine 824/1024 ızgarasıyla üret. `scripts/generate-icon.swift` bu iki modu destekleyecek şekilde ayrıştırılmalı.

---

### M-02 — App Store dışı dağıtımda güncelleme kanalı yok (Sparkle/feed yok)

- **Kanıt:** `grep -rni "sparkle|SUFeedURL|SUUpdater"` (kaynak, script, README) → **hiç eşleşme**. App Store kanalı seçilirse güncellemeleri sistem yönetir (sorun değil); ancak B-01'deki doğrudan dağıtım yolu açıldığında kullanıcıya güncelleme ulaştırmanın yolu yok.
- **Neden önemli:** Doğrudan indirme dağıtımında güvenlik düzeltmelerini iletememek, imzalı/notarize paketlemenin faydasını büyük ölçüde götürür.
- **Somut düzeltme:** Sparkle 2 (EdDSA imzalı appcast) + `SUFeedURL`/`SUPublicEDKey`; appcast güncellemesi CI'da release sonrası otomatik. Yalnızca App Store hedefleniyorsa bunu README'de net yaz ve `--dist` modunu hiç ekleme (B-01 kapsamını daralt).

---

### M-03 — Artefakt kimliği/provenance karışıyor: `build/` tüm modlarca paylaşılıyor, stale kopya testleri maskeliyor

- **Kanıt**
  - `scripts/build-app.sh:24` tek `APP_DIR="$ROOT/build/QuickMD.app"`; `:50` her modda `rm -rf`; `--sandbox` (`:139–142`) ve varsayılan (`:143–147`) **aynı dizine** yazıyor.
  - Denetim sırasında `build/QuickMD.app` **sandbox entitlement'lı** çıktı (`codesign -d --entitlements -` → `com.apple.security.app-sandbox=true`), yani son çalıştırılan mod `--sandbox` olmuş; varsayılan modun çıktısı değil. Aynı binary `--render` çağrısında `/tmp` dosyasını okuyamadı (sandbox), yeniden imzalanınca okudu.
  - `/Applications/QuickMD.app` hâlâ **0.1.0** (LaunchServices: `versionString: 0.1.0`, copyright "Based on Wisp…", 31 Ekim) ve varsayılan `.md` handler o (`LSCopyDefaultApplicationURLForContentType` → `/Applications/QuickMD.app`). Yani kullanıcı/denetçi eski sürümü test edebilir.
  - `build/` ve `*.app` `.gitignore`'da (satır 23–26), `.build-universal/` satır 29 → artefaktlar sürümle izlenemiyor.
- **Neden önemli:** "Hangi binary test edildi / hangi moddan çıktı" sorusu cevapsız kalıyor; sandbox'lı artefaktı sandbox'sız sanıp davranış testi yapmak kolay. Release artefaktı ile test edilen artefakt ayrışabilir.
- **Somut düzeltme:** Mod bazlı çıktı dizinleri (`build/local/QuickMD.app`, `build/appstore/QuickMD.app`, `dist/…`) veya `--output`; her çıktıya `Contents/Resources/build-info.json` (version, build, git SHA, mod, kanal, tarih) ekle; test öncesi `lsregister -u /Applications/QuickMD.app; rm -rf /Applications/QuickMD.app` uyarısı/`--uninstall` modu.

---

### M-04 — `PrivacyInfo.xcprivacy`: beyan edilen `FileTimestamp` gerekçelerinden biri kodla uyuşmuyor olabilir; reason-code semantiği doğrulanamadı

- **Kanıt**
  - `Packaging/PrivacyInfo.xcprivacy:8–18`: `NSPrivacyAccessedAPICategoryUserDefaults` → `CA92.1`; `NSPrivacyAccessedAPICategoryFileTimestamp` → `3B52.1` + `C617.1`.
  - Koddaki required-reason API kullanımı (grep): yalnızca `UserDefaults` (`Sources/QuickMD/FolderAccess.swift:19,26,47,49`, `Settings.swift:12`) ve **tek** dosya zaman damgası okuması `MarkdownDocument.swift:105–106` (`url.resourceValues(forKeys: [.contentModificationDateKey])` — kullanıcının açtığı not). `creationDate`, `attributesOfItem`, `systemUptime`, `mach_absolute_time`, `volumeAvailableCapacity`, `NSFileSystemFreeSize`, `CGEventSource`/klavye API'leri → **yok**. Yani **eksik kategori bulunmadı**; beyanlar kodla büyük ölçüde uyumlu.
  - Konum doğru: `scripts/build-app.sh:58` → `Contents/Resources/PrivacyInfo.xcprivacy`; imzayla mühürlü (`_CodeSignature/CodeResources` içinde `Resources/PrivacyInfo.xcprivacy`); `plutil -lint` OK.
  - Ancak: `C617.1` Apple'ın kodu "app container/app group/CloudKit container içindeki dosyaların zaman damgaları" içindir; QuickMD container'da not tutmuyor, kullanıcının dosyalarını okuyor → `3B52.1` doğru olan; `C617.1` gereksiz/yanlış olabilir. **Doğrulanmadı:** reason-code metinleri bu oturumda Apple dokümanından teyit edilemedi (doküman JSON'ları erişilemedi). Ayrıca Apple'ın "Describing use of required reason API" belgesi zorunluluğu **iOS/iPadOS/tvOS/visionOS/watchOS** için sayıyor; **macOS listede yok** → macOS-only QuickMD için beyan zorunlu olmayabilir (fazladan beyan zararsız).
- **Neden önemli:** Yanlış reason kodu, App Store Connect'in otomatik uyarılarına ve gizlilik beyanı ile manifest uyuşmazlığına yol açabilir; eksik olmadığı için kritik değil.
- **Somut düzeltme:** `C617.1`'i kaldırıp yalnızca `3B52.1` bırak (kullanıcı seçimli dosyalar); App Store Connect gizlilik yanıtlarıyla ("veri toplanmıyor") eşle; macOS 26 hedefi için manifesti koru ve her iki platformda Apple'ın güncel reason-code listesine karşı gözden geçir.

---

### M-05 — Yerel build ad-hoc: kimlik her derlemede değişir; TCC/security-scoped bookmark sürekliliği riski (doğrulanmadı) ve `--install` sandbox'sız app kuruyor

- **Kanıt**
  - `scripts/build-app.sh:143–147` varsayılan/`--install` modunda `codesign --force --sign -` (ad-hoc); `codesign -dv` → `TeamIdentifier=not set`, `Signature=adhoc`.
  - `--sandbox` modu (`:139–142`) App Store entitlement'larıyla ad-hoc imzalıyor; ad-hoc sandbox app **çalışıyor** (denetimde `/tmp` kopyası 3 sn çalıştı) ve `FolderAccess.isSandboxed` (`FolderAccess.swift:13`, `APP_SANDBOX_CONTAINER_ID`) sandbox'lı test uygulamasında **doğrulandı** (`APP_SANDBOX_CONTAINER_ID=com.qa.sbtest`, `HOME=…/Containers/…`, container dışı dosya okunamadı).
  - `--install` (`:150–157`) `/Applications`'a **sandbox'sız** ad-hoc app kopyalıyor, `lsregister -f` + `open --args --make-default`; App Store build'i ise sandbox'lı. Yerelde test edilen davranış (sandbox'sız, bookmarksız doğrudan dosya erişimi) ile mağazadaki davranış (sandbox + bookmark) farklı.
  - **Doğrulanmadı:** ad-hoc imza her derlemede farklı cdhash ürettiği için TCC kayıtlarının ve `app-scope` bookmark'ların geçersizleşmesi bu makinede ölçülmedi (TCC prompt'ları otomatik test edilemez).
- **Neden önemli:** Sandbox'lı sürümde dosya/klasör erişimi tamamen bookmark mekanizmasına bağlı; ad-hoc kimlikle yapılan testlerde her rebuild sonrası izinlerin yeniden istenmesi geliştiriciyi yanıltır ve "sandbox'ta çalışıyor" güvenini zedeler.
- **Somut düzeltme:** Yerel geliştirme/test için sabit kimlik kullan: `--sandbox --identity "Apple Development: …"` (veya ücretsiz Personal Team) seçeneği ekle; README'de ad-hoc'un TCC/bookmark saklamadığını yaz; `--install` varsayılanını sandbox'sız bırak ama `--install --sandbox` varyantı ekle.

---

### M-06 — README/script talimatı bu ortamda çalışmıyor: `xcrun altool` yok, notarization aracı var ama kimlik yok

- **Kanıt:** `scripts/build-app.sh:136–137` `xcrun altool --validate-app … --apiKey … --apiIssuer …` öneriyor; `xcrun altool` → `unable to find utility "altool"` (bu makine yalnızca CLT). `xcrun notarytool --version` → 1.0.0, `xcrun stapler` çalışıyor. `README:29` "Upload with Transporter" diyor (doğru) ama script echo'su yanıltıcı; `README:20` "Command Line Tools are enough" yalnızca **build** için doğru, App Store gönderimi için değil.
- **Neden önemli:** Yeni bir geliştirici/CI, script'in önerdiği komutu çalıştırıp "araç yok" hatası alır; App Store adımı belgelenmemiş olur.
- **Somut düzeltme:** Echo'ları düzelt (`xcrun --find altool || echo "Xcode gerekli; Transporter kullan"`); README'ye "App Store gönderimi: Xcode veya Transporter + App Store Connect API anahtarı" notu; CI'da `notarytool`/Transporter kullan.

---

### M-07 — App Store metadata / release checklist yok (privacy policy, destek URL'si, review notes, ekran görüntüleri)

- **Kanıt:** Depoda `fastlane/metadata`, `docs/release*`, `appstore/` vb. **yok**; README yalnızca build anlatıyor (`README:18–33`). Entitlements'ta `network.client` gerekçesi yalnızca kod yorumu (`Packaging/QuickMD.entitlements:13–14`); App Review'a verilecek gerekçe metni yok. `LSApplicationCategoryType = public.app-category.productivity` doğru (build-app.sh:78).
- **Neden önemli:** App Store gönderimi kod dışı zorunlu metadata ister: gizlilik politikası URL'si, destek URL'si, kategori, yaş derecelendirmesi, ekran görüntüleri, inceleme notları (özellikle **network.client** gerekçesi: "önizlemede uzak görseller"). Bunlar hazır değilse gönderim gecikir/reddedilir.
- **Somut düzeltme:** `docs/appstore/` altında checklist + gizlilik politikası taslağı + review notes ("QuickMD not toplamaz; ağ erişimi yalnızca kullanıcı notlarındaki uzak görselleri göstermek için, `img-src *` CSP'si altında; uygulama kendi başına istek atmaz"); ekran görüntüleri için release script'i.

---

## 4. LOW

### L-01 — `--appstore` akışındaki `--deep` gereksiz ve yanlış yerde; paket içinde nested kod yok
- **Kanıt:** `scripts/build-app.sh:133` `codesign --verify --deep --strict --verbose=2`. `man codesign` (satır 80+): `--deep` **imzalama** için macOS 13.0 itibarıyla deprecated; burada **verify** için kullanılmış (teknik olarak destekli). Ancak paket içinde nested kod **yok**: `find build/QuickMD.app -maxdepth 3` → `Contents/{Info.plist, MacOS/QuickMD, Resources/…, _CodeSignature/}`; `Frameworks/`, `PlugIns/`, `Helpers/` yok (App Store build'de yalnızca `embedded.provisionprofile` ekleniyor, satır 126).
- **Neden önemli:** İşlevsel risk düşük (nested kod olmadığı için `--deep` bir şeyi değiştirmiyor), fakat Apple `--deep`'i önermiyor ve ileride Sparkle/XPC helper eklenirse yanlış güven verir.
- **Düzeltme:** `codesign --verify --strict --verbose=2`; nested içerik eklendiğinde `find` ile açıkça doğrula/sign et.

### L-02 — Info.plist cilası eksik: Help Book yok, lokalizasyon anahtarları yok (şu an gerekmiyor), TCC usage string'leri yok
- **Kanıt:** `packaging`/build plist'te `CFBundleHelpBookFolder`/`CFBundleHelpBookName` yok; `grep -rn "NSLocalizedString|\.lproj|CFBundleLocalizations"` → boş (lokalizasyon yok, `CFBundleLocalizations`/`CFBundleAllowMixedLocalizations` bu yüzden **gerekmiyor** — bulgu değil); `NSDocumentsFolderUsageDescription` vb. yok (sandbox'sız yerel build'de bağlantılı notları okurken TCC metni varsayılan kalır).
- **Düzeltme:** Apple Help Book (`Help > QuickMD Help`) ekle — "gerçek uygulama" cilası; sandbox'sız yerel build için `NSDocumentsFolderUsageDescription`/`NSDesktopFolderUsageDescription` ekle; lokalizasyon eklenirse `CFBundleLocalizations` ekle.

### L-03 — `PkgInfo` dosyası yok
- **Kanıt:** `ls build/QuickMD.app/Contents/` → `Info.plist MacOS Resources _CodeSignature` (PkgInfo yok). Modern uygulamalarda gerekmez (Xcode üretir, `CFBundlePackageType=APPL` plist'te var).
- **Düzeltme:** Gerek yok; istenirse `printf 'APPL????' > Contents/PkgInfo`.

### L-04 — `--install` hata yolu: önce `rm -rf /Applications/QuickMD.app`, sonra kopyalama; hata olursa app'siz kalınır, `open --args` çalışan app'te yok sayılır
- **Kanıt:** `scripts/build-app.sh:152–155` (`pkill`, `rm -rf`, `cp -R`, `lsregister`, `open --args --make-default`).
- **Düzeltme:** Hedefe atomik kopyala (`ditto` geçici dizine + `mv`), `open -n --args` veya `--make-default`'ı LS API üzerinden çalıştır; başarısızlıkta eski kopyayı koru.

### L-05 — pkg/zip artefaktlarında xattr temizliği ve sürümlü ad yok
- **Kanıt:** `xattr -cr` yalnızca app için (satır 122); çıktı adı `build/QuickMD.pkg` sabit (satır 134, 135) — sürüm/build içermiyor.
- **Düzeltme:** `--appstore` çıktısını `build/QuickMD-$VERSION-$BUILD_NUMBER.pkg` yap; pkg üretiminden sonra `xattr -cr`; arşiv adlarını standartlaştır.

### L-06 — `.build-universal/` temizlenmiyor; release'de temiz/taze scratch yok (deterministik build riski)
- **Kanıt:** `scripts/build-app.sh:28,36,41–48`; `.build-universal` gitignore'da; SDK/toolchain değiştiğinde eski slice'larla lipo riski. Denetimde scratch'lerin dSYM'leri mevcut (H-01).
- **Düzeltme:** Release modunda `--scratch-path` geçici dizin (`mktemp -d`), `lipo -verify_arch arm64 x86_64`, `--clean` seçeneği.

### L-07 — `swift build` her mimari için iki kez çağrılıyor
- **Kanıt:** `scripts/build-app.sh:43` (build) ve `:44` (tekrar build + `--show-bin-path`) — ikinci çağrı no-op ama süre maliyeti var.
- **Düzeltme:** BIN_DIR'i tek seferde `--show-bin-path` ile al, ya da `swift build --arch`/`xcodebuild -arch` ile tek komutta çok mimari.

### L-08 — `PlistBuddy -c "Add"` kırılgan (anahtar varsa `set -e` ile script ölür)
- **Kanıt:** `scripts/build-app.sh:129–130`; mevcut entitlement dosyasında anahtarlar yok, bu yüzden bugün çalışır. `--appstore` iki kez veya değiştirilmiş entitlement ile çalıştırılırsa `Add` hatası verir.
- **Düzeltme:** `Delete … || true` + `Add`; veya `plutil -replace`/`-insert` (idempotent).

---

## 5. Doğrulanmadı (ortam/kimlik/erişim kısıtı — iddia edilmedi)

1. **macOS 26 `.icon`/Icon Composer zorunluluğu** — macOS 15.7.9 ve Xcode yok; yalnızca HIG (28 Ekim 2026) "öneri" olarak teyit edildi, App Store zorunluluğu doğrulanamadı.
2. **Ad-hoc imzada TCC izinlerinin her build'de sıfırlanması** — TCC prompt'ları otomatik ölçülemez; mekanizma (sabit TeamIdentifier/DR yok: `TeamIdentifier=not set`) doğrulandı, davranış ölçülmedi.
3. **`app-scope` bookmark'ların ad-hoc yeniden imzada geçersizleşmesi** — ölçülmedi.
4. **App Store Connect'in `CFBundleVersion` artış kuralı** — ASC erişimi yok; kural Apple dokümanlarından biliniyor, bu makinede test edilmedi.
5. **Required-reason reason-code semantiği (`C617.1`, `3B52.1`, `CA92.1`)** — Apple doküman JSON'ları bu oturumda alınamadı; kod metinleri teyit edilemedi (bkz. M-04).
6. **macOS'ta required-reason API beyan zorunluluğu** — Apple belgesi zorunluluğu iOS/iPadOS/tvOS/visionOS/watchOS için sayıyor, macOS listede yok; macOS App Store'da uygulanıp uygulanmadığı doğrulanamadı.
7. **`--appstore` imzalı build'in gerçekten sandbox'lı olduğu** — 0 imza kimliği/profil yok; akış hiç çalıştırılmadı. Script mantığı incelendi (entitlements + application-identifier ekleniyor), sonuç doğrulanmadı.
8. **İmzalı `.pkg` / notarization / staple sonucu, Gatekeeper'ın indirilmiş kopyada kullanıcı deneyimi** — kimlik yok; yalnızca ad-hoc app'in `spctl` ile reddedildiği kanıtlandı.
9. **Win/CI ortamında (GitHub Actions macos runner) imzalama sırlarıyla uçtan uca release** — CI yok; taslak öneri verildi.

---

## 6. İlk 5 düzeltme, sırayla

1. **Depoyu kendi kendine yeter hâle getir (B-00) ve sürümü tek kaynağa bağla (B-03, H-05).** `Packaging/`, `Resources/`, `Tests/` ve eksik 6 Swift dosyasını commit'le; `git status` temiz değilse build'i durdur. `VERSION` git tag'inden, `BUILD_NUMBER` commit'li sayaç/CI run number'dan gelsin; format regex + ASC'de son build numarası doğrulaması. Bugünkü hâliyle temiz klon yalnızca **eski 0.1.0** uygulamasını üretir (HEAD script'i 96 satır; `--appstore`/`--sandbox`/entitlements yok); shallow clone build numarasını 1'e düşürüp upload'ı reddettirir.
2. **Notarization + DMG/zip dağıtım yolunu ekle (B-01).** `--dist` modu: `Developer ID Application` + `--options runtime` + `--timestamp` → `ditto` zip / `hdiutil` dmg → `notarytool submit --wait` → `stapler staple` → `spctl -a -t open --context context:primary-signature`. Bu olmadan üretilen hiçbir kopya indirilebilir değil. (App Store-only karar verilirse bu madde yerine README'de kapsam netleştirilmeli.)
3. **CI/release otomasyonunu kur (H-03) ve dSYM'leri arşivle (H-01).** `swift test` kapısı + sertifika import + `build-app.sh --appstore` + artefakt (app, pkg, `build/dSYMs/<version>-<build>/`) + `dwarfdump --uuid` eşleşmesi. `strip -x` doğru sırada kalsın; dSYM kaybolmasın, crash raporlamaya yüklensin.
4. **App Store kimliğini ve `--appstore` doğrulamalarını tamamla (B-02, H-04).** Apple Distribution + 3rd Party Mac Developer Installer sertifikaları, Mac App Store profili; profilin tipi/bundle-id/`get-task-allow=false` olması, imzada sandbox entitlement'ı, `pkgutil --check-signature`/`spctl -a -t install` ve `--timestamp` script'e girsin. `altool` talimatını Xcode/Transporter ile değiştir.
5. **UTI beyanını temizle, Info.plist'i şablona taşı (H-02, H-05).** İthal UTI'de Apple Shortcuts ile aynı tag seti (`text/x-markdown`, yalnız `.md`) ya da hiç tag spec; `.markdown/.mdown/.mkd/.mdwn` iddiasını bırak, `NoteLinks.noteExtensions`'i gerçek handler'larla uyumla. Info.plist'i `Packaging/Info.plist` şablonundan enjekte et, zorunlu anahtarları ve sürüm formatını lint'le.

---

## Ek A — Doğrulanan teknik çıktılar (özet)

```
$ file scripts/AppIcon.icns            → Mac OS X icon, 422044 bytes, "ic12"
$ iconutil -c iconset …                → exit 0; 10 temsil: 16,32,64,128,256,512,1024 px
$ sips (1024 png)                      → pixelWidth 1024 pixelHeight 1024
$ alpha≥128 bbox (1024 canvas)         → (100,100,924,924) = 824×824 karo, Apple ızgarası ✓
$ plutil -lint Info.plist/PrivacyInfo/entitlements → OK / OK / OK
$ codesign -dv build/QuickMD.app       → adhoc, TeamIdentifier=not set, universal (x86_64 arm64)
$ codesign --verify --deep --strict    → valid on disk; satisfies its Designated Requirement
$ spctl -a -vvv -t exec build/QuickMD.app → rejected (exit 3)
$ lipo -info                           → x86_64 arm64
$ otool -l | LC_BUILD_VERSION          → minos 13.0 / sdk 15.5 (her iki slice)
$ dwarfdump -u (binary vs dSYM)        → arm64 42AF9CE5…, x86_64 913B242D… (eşleşiyor)
$ find build -name '*.dSYM'            → (boş)  ← dSYM paketlenmiyor
$ swift build … -DAPPSTORE             → Build complete (exit 0)
$ swift test                           → 38 test, hepsi geçti (exit 0)
$ productbuild --component app /Applications /tmp/x.pkg → exit 0; pkgutil: "no signature" (imzasız deneme)
$ security find-identity -v -p codesigning → 0 valid identities found
$ xcodebuild -version                  → hata (yalnız CLT); xcrun altool → "unable to find utility"
$ git ls-files | wc -l                 → 25 izlenen dosya (Packaging/, Resources/, Tests/, 6 Swift dosyası yok)
$ git status --porcelain | grep '^??'  → Packaging/ Resources/ Tests/ + 6 Swift dosyası + WATCHDOG.yml
$ git clone file://…/quickmd /tmp/qa-shallow2 && ls → Packaging/ ve Resources/ yok
$ (klon) swift build                   → Build complete (exit 0, 144.43 s) — HEAD tutarlı eski 0.1.0 sürümü
$ (klon) Sources/QuickMD/*.swift       → 18 dosya (çalışma ağacında 24); Tests/ yok
$ (klon) scripts/build-app.sh          → 96 satır; appstore/sandbox/productbuild/PROVISIONING yok
$ git diff --stat HEAD -- scripts/build-app.sh → +76/−15 (güncel paketleme akışı commit dışı)
$ git rev-list --count HEAD            → 3; shallow clone → 1; non-git fallback → 1
$ git status --short | wc -l           → 20 değişik dosya (dirty tree)
$ git tag                              → (boş)
$ ls .github                           → yok (yalnız WATCHDOG.yml)
$ UTType(filenameExtension:)           → md→net.daringfireball.markdown; markdown/mdown/mkd/mdwn→com.looq.*
$ lsregister -dump (Shortcuts)         → net.daringfireball.markdown, imported, tags .md, text/x-markdown
$ codesign -d --entitlements build/…   → app-sandbox, user-selected.read-write, bookmarks.app-scope, print, network.client
$ sandbox test app                     → APP_SANDBOX_CONTAINER_ID=com.qa.sbtest; container dışı dosya okunamadı
```

## Ek B — Dosya envanteri (denetlenen paketleme yüzeyi)

`scripts/build-app.sh` (157 satır), `scripts/generate-icon.swift`, `scripts/AppIcon.icns`, `Packaging/QuickMD.entitlements`, `Packaging/PrivacyInfo.xcprivacy`, `Packaging/Credits.rtf`, `Package.swift` (`platforms: [.macOS(.v13)]`), `README.md` (18–33), `.gitignore`, `WATCHDOG.yml`, `build/QuickMD.app/Contents/**`, `Resources/{Fonts,katex,mermaid}`. Kaynak kodda paketlemeyi etkileyen yerler: `Sources/QuickMD/main.swift:9` (`#if !APPSTORE`), `AppDelegate.swift:24–28,43`, `SidePanes.swift:37–42,56–60`, `FolderAccess.swift:13,19,26,47,49,61`, `MarkdownDocument.swift:105–106`. Kaynak kod **değiştirilmedi**.

**Git izleme durumu (B-00 kanıtı):** `git ls-files` yalnızca 25 dosya döndürüyor: `.gitignore`, `LICENSE`, `Package.swift`, `README.md`, 18 `Sources/QuickMD/*.swift`, `scripts/{AppIcon.icns,build-app.sh,generate-icon.swift}`. **İzlenmeyen (??):** `Packaging/`, `Resources/`, `Tests/`, `Sources/QuickMD/{FolderAccess,SettingsWindow,Starters,SyntaxHighlighter,TableEditing,Template}.swift`, `WATCHDOG.yml`, `audit/`. Yani depo, uygulamayı üretmek için gereken paketleme girdilerinin **hiçbirini** içermiyor.
