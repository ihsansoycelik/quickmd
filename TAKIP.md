# TAKIP - quickmd
> Son guncelleme: 2026-11-18 · Bu dosya projenin canli durum kaydidir. Her calisma oturumu sonunda guncellenir.

## Ozet tablo

| Tur | Asama | Canli mi | Karar onerisi | Son aktivite tarihi | Stack |
|---|---|---|---|---|---|
| urun (macOS uygulamasi) | calisiyor (yerelde kurulu, magazada degil) | hayir (App Store'a gonderilmedi; GitHub Pages kapali) | devam | 2026-11-10 | Swift 6 toolchain (dil modu 5), AppKit, SwiftPM, macOS 13+, KaTeX + Mermaid (gomulu) |

## 1. Ne ise yarar, kimin icin
- Native macOS Markdown editoru. Finder / Quick Look'tan `.md` acar, varsayilan `.md` uygulamasi olabilir.
- Tek gorunum (iA Writer tarzi): not bicimli gorunur, imlecin oldugu satir ham Markdown'u gosterir. Dosya duz Markdown kalir.
- Tablolar (izgara), gorev kutulari, callout, matematik, Mermaid, kod renklendirme; HTML/PDF disa aktarma, yazdirma.
- "Ajan yazarken izle": baska uygulama/ajan acik notu degistirince degisiklik canli yazilir (`scripts/quickmd-agent-hook.sh` Claude Code hook'u).
- Kitle: once sahibinin kendi gunluk kullanimi; hedef Mac App Store'da genel kullanici ("QuickMD Editor").

## 2. Hedef ve "bitti" tanimi
- Hedef (audit/08, audit/09): hafif, hizli, hatasiz, Mac App Store'da yayinlanmis native Markdown editoru.
- "Bitti" = 1.0.0 App Store'da onayli ve yayinda; destek + gizlilik URL'leri calisiyor; CI yesil.
- 1.1 hedefi: Quick Look eklentisi (Xcode projesi gerektirir).

## 3. Mevcut asama
Calisan (belgelere gore; bu incelemede derleme/test CALISTIRILMADI = dogrulanmadi):
- Editor cekirdegi, NSDocument (otomatik kayit, surumler, sekmeler), bul-degistir, disa aktarma, yazdirma.
- Sandbox entitlement'lari, PrivacyInfo, surum dosyasi (`Packaging/version` = 1.0.0 / build 1), `--appstore` derleme yolu.
- Yerellestirme EN + TR, VoiceOver etiketleri, pencere/imlec konumu geri yukleme, panodan gorsel yapistirma, Services.
- Dosya guvenligi: BOM, satir sonu, ikili dosya kapisi, buyuk dosya korumasi.
- 87 test fonksiyonu (10 dosya, ~1170 satir); kaynak ~7300 satir Swift, 31 dosya.
- `/Applications/QuickMD.app` bu Mac'te kurulu.

Eksik:
- Apple Developer hesabi / sertifikalar / provisioning profile (audit/09 Adim 1.5, bekliyor).
- App Store Connect kaydi, ekran goruntuleri (1280x800+, acik/koyu), TestFlight.
- Destek ve gizlilik sayfalari yayinda degil (GitHub Pages kapali, repo private).
- Gercek VoiceOver ile elle deneme yapilmadi.
- CI hic calismadi (bkz. bolum 6).

## 4. Hedefe giden engeller
1. Apple Developer Program uyeligi + imza kimlikleri yok (sadece sahibi yapabilir).
2. `docs/` yayinlanmadi: private repoda Pages ucretli plan ister. Uygulamadaki `Help.supportURL` / `Help.privacyURL` su an var olmayan adrese gidiyor.
3. Destek sayfasi private repo'nun issues linkine yonlendiriyor; disaridan kullanici acamaz.
4. CI her push'ta `startup_failure` veriyor; test kapisi fiilen yok.
5. Magaza adi "QuickMD" baska uygulamada alinmis; "QuickMD Editor" secildi, kesin kayit App Store Connect'te dogrulanmadi.

## 5. Acik isler ve verilmemis kararlar
- Karar: `docs/` nerede yayinlanacak? (repo public yapmak / ayri public repo / Cloudflare Pages).
- Karar: destek kanali (public issues reposu mu, e-posta mi).
- Karar: App Store disi dagitim (Developer ID + notarization + DMG) olacak mi? Su an yol yok; plan sadece magaza.
- Karar: ucretli mi ucretsiz mi? Belgelerde fiyat yok (bilinmiyor).
- Is: ekran goruntuleri, TestFlight turu, inceleme notu (`network.client` gerekcesi).
- Is: Quick Look eklentisi (1.1), editorde satir ici Mermaid/KaTeX (onizleme paneli kaldirildigindan beri ekranda yok).
- Is: `audit/00-06` eski durumu anlatiyor (25 dosya, 3 commit vb.); guncel durum `audit/09`. Eski raporlara "tarihsel" notu dusulmeli.

## 6. Kritik buglar
- CI: `.github/workflows/ci.yml` icin GitHub'daki 4 calistirmanin hepsi `startup_failure` (0 sn, 2026-11-02 .. 2026-11-09). Sebep dogrulanmadi (muhtemel: private repoda Actions/macOS runner faturalama ya da izin ayari).
- Uygulama ici Yardim > "Report an Issue" ve gizlilik linki 404'e gider (Pages kapali: `has_pages=false`). `Sources/QuickMD/Help.swift`.
- `scripts/build-app.sh --appstore` calistirildiginda kendi kendine `git commit` atar (build numarasi). Bilincli tasarim, ama beklenmedik commit uretir; push'u unutma.
- Kod icinde TODO/FIXME yok. Islevsel bug kaydi (issue) yok. Calisma zamani buglari bu incelemede test edilmedi.

## 7. Kritik guvenlik bulgulari
- Commit edilmis gizli anahtar / token / .env: bulunamadi (grep ile tarandi).
- `Packaging/QuickMD.entitlements`: `com.apple.security.network.client` acik. Gerekce belgelenmis (WebKit sandbox'ta bu izin olmadan yuklenmiyor; uygulama istek yapmiyor). Uzak gorsel yukleme davranisi bu incelemede dogrulanmadi; inceleme notunda aciklanmali.
- Onizleme/disa aktarma: ham HTML temizleniyor, nonce'lu CSP, ozel URL semasi (`Sources/QuickMD/PreviewScheme.swift`, `MarkdownHTML.swift`); audit'e gore 43 XSS yuku temiz. Yeniden calistirilmadi.
- Cmd-tik: uygulama/betik calistirmaz, http/https/mailto disi semalar onay ister (audit/09, 2026-11-10). `Tests/QuickMDTests/SafetyTests.swift` var.
- `Resources/katex`: 0.16.11 (2024). Sonraki surumlerde guvenlik duzeltmeleri var (ozellikle `trust` secenegi acikken). Dusuk risk; guncellenmesi onerilir. Mermaid surumu: bilinmiyor (min dosyadan okunamadi).
- `scripts/quickmd-agent-hook.sh`: sadece `.md` dosyasini `open -g` ile acar; komut enjeksiyonu gorulmedi (yol tirnak icinde).
- Kritik bulgu: yok.

## 8. Gelecek ve potansiyel
- Farklilastirici: "ajan yazarken canli izle" + `==vurgu==`. Claude Code / Codex / Cursor kullanicilarina dogrudan hitap ediyor; magaza metninde one cikarilabilir.
- Yol haritasi (audit/08): Quick Look eklentisi, Welcome notu, What's New, App Intents; sonra klasor modu (dosya agaci, `[[wiki link]]`, backlink).
- Kardes arac: Imark (markdown yorum bloklari) ile birlikte kullanim mumkun; bu repoda entegrasyon yok.

## 9. Tur ve sahiplik
- Tur: urun (kendi urunu, tek gelistirici).
- Sahip: ihsansoycelik. Bundle id: `com.ursula.quickmd`.
- Koken: Wisp editor cekirdegi (Suleman Hamza, MIT) uzerine kurulu.
- Musteri isi degil.

## 10. Canli ortam ve maliyet
- Canli ortam: yok. Sunucu, backend, veritabani yok; tamamen yerel uygulama.
- GitHub Pages: kapali. App Store: gonderilmedi.
- Mevcut maliyet: 0. Beklenen: Apple Developer Program (yillik uyelik); private repoda Pages istenirse ucretli GitHub plani; private repoda macOS Actions dakikalari ucretli olabilir.

## 11. Kopya / ortusen repolar
- Kopya yok. Asil repo bu.
- Yakin ama farkli: `stash-marks` (yer imi kutuphanesi), `mind` (hafiza deposu, .md dosyalari), `saha-notlari` — islev ortusmesi yok.

## 12. Nasil calistirilir, build/test durumu
```sh
./scripts/build-app.sh            # build/QuickMD.app
./scripts/build-app.sh --install  # /Applications'a kopyalar, varsayilan .md uygulamasi yapar
./scripts/build-app.sh --sandbox  # App Store sandbox'i ile yerel test
swift test                        # testler
TEAM_ID=... SIGN_IDENTITY=... INSTALLER_IDENTITY=... PROVISIONING_PROFILE=... ./scripts/build-app.sh --appstore
```
- Gereksinim: macOS 13+, Swift toolchain (Command Line Tools yeterli). Dis paket bagimliligi yok.
- Bu incelemede `swift build` / `swift test` calistirilmadi (disk dar) = dogrulanmadi.
- CI: tanimli (macos-15: build, test, build-app) ama hic basariyla calismadi.

## 13. Yarim kalan is
- Branch: sadece `main`. Acik PR: yok. Acik issue: yok. Tag/release: yok.
- Yerel kopya (`/Users/ihsan/Desktop/macOS_Dev/quickmd`): HEAD = origin/main (`eb20171`), push edilmemis commit yok.
- Yerelde commit edilmemis: `.zcode/plans/plan-sess_...md` silinmis (staged degil). Dosya repoda hala duruyor; silme commit'lenmeli ya da `.zcode/` `.gitignore`'a eklenmeli.
- Yerelde stash: `stash@{0}: Ledger deneyi (adim 1-7) - yedek` — 15 dosya, +687/-62. Artik repoda olmayan dosyalara dokunuyor (`SidePanes.swift`, `Outline.swift`, `Template.swift`, `FontFace.swift`), yani eski tasarima ait; buyuk olasilikla uygulanamaz. Karar: at ya da arsivle.
- Yerelde izlenmeyen (ignore'lu): `WATCHDOG.yml`, `.claude/`, `build/`, `.build/`, `.build-universal/`.
- Bekleyen plan maddeleri: audit/09 Adim 1.5 (hesap/imza), 1.6 (Pages yayini + ekran goruntuleri), Adim 3.1 (Quick Look).

## 14. Dis bagimliliklar ve lisans
- Lisans: MIT (Wisp telif satiri + QuickMD contributors). `LICENSE`.
- Gomulu: KaTeX 0.16.11 (MIT), Mermaid (MIT), lisans dosyalari `Resources/` altinda; `Packaging/Credits.rtf`.
- SwiftPM paket bagimliligi: yok. Sistem: AppKit, WebKit.
- Dis servis: yok (hesap, analitik, ag istegi yok).

## 15. Gelir / musteri baglantisi
- Su an gelir yok, musteri yok.
- Potansiyel: Mac App Store satisi. Fiyat modeli belirlenmemis (bilinmiyor).

## 16. Karar onerisi
**devam.** Gerekce: en aktif repolardan biri (son commit 2026-11-10), kod tarafi App Store icin neredeyse hazir, kalan isler cogunlukla hesap/idari (Apple uyeligi, Pages, ekran goruntuleri). Az eforla yayinlanabilir ilk urun olma ihtimali yuksek.

## 17. Siradaki 3 adim
1. Destek/gizlilik sayfalarini yayinla ve linkleri duzelt: `docs/`'u public bir yere koy, `Help.swift` + `docs/support.html` icindeki adresleri guncelle, destek kanali sec. (~1-2 saat)
2. CI'yi calistir: `startup_failure` sebebini bul (Actions ayari / faturalama), bir yesil kosu al; ayni anda yerelde `swift test` ile dogrula. (~1 saat)
3. Apple Developer hesabi + sertifikalar + profil, `--appstore` ile pkg, Transporter, TestFlight, ekran goruntuleri, gonderim. (~1-2 gun is + Apple bekleme suresi)

## 18. Agent gunlugu
En yeni kayit en ustte. Her oturum sonunda bir kayit ekle: tarih, agent, ne yapildi, nerede kalindi, siradaki plan, onemli bulgular.

### 2026-11-18 - Claude (UI/UX revizyonu)
- Yapilan: ursula-estetik + universal-principles-ux ile editor incelendi; tek gorunum (iA Writer cizgisi) korunarak cilalandi. Baslik olcegi 1.5/1.25/1.08 + ustte nefes; palet hafif sicak kagit (#F8F7F4 / #1A1918, saf siyah yok); imlec 2px; gorev kutusu tek vurgu rengiyle (imlec mavisi), madde ve gorev metni ayni hizada; callout alt boslugu duzeldi (metin kenara yapisiyordu), kendi renginde hafif zemin; satir ici kod ve ==vurgu== satiri dolduran blok yerine yuvarlak cip; bos notta "Yazmaya basla. Blok eklemek icin / yaz." ipucu (EN/TR).
- Kalinan yer: 87 test gecti, /Applications'a kuruldu. Bos not ipucu ve 2px imlec canli uygulamada gozle dogrulanmadi (snapshot'ta yok).
- Siradaki plan: bolum 17 degismedi.
- Onemli bulgular: callout'un son satiri panelin altina yapisiyordu (bug, duzeldi). Disa aktarma CSS'i paleti paylasiyor; renk degisikligi oraya da yansir.

### 2026-11-14 - Claude (ilk inceleme)
- Yapilan: repo incelendi, bu dosya olusturuldu. Derleme/test calistirilmadi; README, audit/, git gecmisi, gh (PR/issue/Actions/Pages), yerel kopya durumu okundu.
- Kalinan yer: kod App Store'a hazir gorunuyor; audit/09 Adim 1.5 ve 1.6 acik.
- Siradaki plan: bolum 17'deki 3 adim (Pages/linkler, CI, Apple hesabi + gonderim).
- Onemli bulgular: (1) CI'nin 4 kosusu da `startup_failure`, test kapisi yok. (2) Uygulamadaki destek/gizlilik URL'leri yayinda degil (Pages kapali). (3) Yerelde eski tasarima ait bir stash ve commit'lenmemis bir dosya silme var. (4) Gizli anahtar bulunmadi, kritik guvenlik acigi gorulmedi. (5) KaTeX 0.16.11 guncellenmeli (dusuk oncelik).
