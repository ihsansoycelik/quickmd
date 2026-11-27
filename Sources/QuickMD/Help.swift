import Foundation

/// Help › QuickMD Help opens this as an untitled note: the guide is
/// written in the format it explains, and needs no help book.
enum Help {
    /// The support page (also the App Store's support URL).
    static let supportURL = URL(string: "https://ihsansoycelik.github.io/quickmd/support.html")!
    /// The privacy policy (App Store Connect asks for one).
    static let privacyURL = URL(string: "https://ihsansoycelik.github.io/quickmd/privacy.html")!

    static var text: String { isTurkish ? turkish : english }

    static let english = """
    # QuickMD Help

    QuickMD edits plain Markdown files. What you see styled is still plain text on disk.

    ## Writing

    - Type `/` at the start of a line for blocks: headings, lists, tables, callouts, math, diagrams.
    - Format menu: **Bold** ⌘B, *Italic* ⌘I, Link ⌘K, Heading ⌥⌘1–4, Body Text ⌥⌘0.
    - Type `*`, `` ` ``, `[` or `(` over a selection to wrap it. Paste a URL over words to link them.
    - Return continues a list; Tab and ⇧Tab indent. Click a `[ ]` box to tick it.
    - In a table, Tab and ⇧Tab move between cells; Tab past the last cell adds a row.
    - ⌘-click a link to open it. Links to other `.md` files open in QuickMD; apps and scripts are only shown in Finder, never run.
    - Paste a screenshot to save it beside the note and link it in. Files copied in Finder paste as links.

    ## Reading

    - One view does both: the note shows itself styled — headings, lists, tables, code — and the line the caret is in shows its Markdown, ready to edit.

    ## Look

    - One look, after iA Writer: a monospaced face in a centred column, Markdown's marks in grey.
    - View › Appearance picks light, dark or the system setting.
    - View › Bigger (⌘+ or ⌘=) and Smaller (⌘−) change the text size.
    - View › Word Count (⌥⌘I) shows words, characters and reading time, for the selection too.

    ## Files

    - Notes save themselves. File › Browse All Versions… goes back to earlier versions; File › Revert To Saved returns to the last saved copy.
    - File › Export as HTML, PDF, Word or Rich Text, Edit › Copy As (Markdown, HTML, Rich Text, Plain Text), File › Print.
    - Edit › Paste as Markdown (⌥⌘V) turns copied web or rich text into Markdown; cells copied from a spreadsheet paste as a table, and Edit › Paste as Table does the same for CSV.
    - Edit › Check Links… lists missing files and images, unknown #anchors and footnotes without a definition, without going online.
    - When another app changes an open note and nothing is unsaved, QuickMD reloads it.
    - Reopened notes come back with the caret and the view where you left them.
    - In any app, select text and choose Services › New QuickMD Note With Selection.

    ## Watching an agent write

    With Settings › Watch agents write live on, a change another app or an agent writes into an open note types itself in, and the new part glows for a moment. With Reduce Motion on, the change appears at once.

    ## VoiceOver and keyboard

    - VoiceOver reads task boxes as checkboxes (VO-Space ticks them), tables by size and cells, and pictures by their alt text.
    - Format › Mark Task Done (⌘Return) ticks the tasks in the selection without the mouse.

    ## Problems

    Help › Report an Issue… opens the support page.

    """

    static let turkish = """
    # QuickMD Yardım

    QuickMD düz Markdown dosyalarını düzenler. Biçimli gördüğünüz her şey diskte hâlâ düz metindir.

    ## Yazmak

    - Satır başında `/` yazın: başlıklar, listeler, tablolar, bilgi kutuları, matematik, diyagramlar.
    - Biçim menüsü: **Kalın** ⌘B, *İtalik* ⌘I, Bağlantı ⌘K, Başlık ⌥⌘1–4, Gövde Metni ⌥⌘0.
    - Seçili metnin üzerine `*`, `` ` ``, `[` ya da `(` yazınca metin sarılır. Seçili sözcüklerin üzerine URL yapıştırınca bağlantı olur.
    - Return listeyi sürdürür; Tab ve ⇧Tab girintiyi değiştirir. `[ ]` kutusuna tıklayınca işaretlenir.
    - Tabloda Tab ve ⇧Tab hücreler arasında gezer; son hücrede Tab yeni satır ekler.
    - Bağlantıyı açmak için ⌘-tıklayın. Başka `.md` dosyaları QuickMD’de açılır; uygulamalar ve betikler hiç çalıştırılmaz, yalnızca Finder’da gösterilir.
    - Ekran görüntüsü yapıştırınca notun yanına kaydedilir ve bağlantısı eklenir. Finder’da kopyalanan dosyalar bağlantı olarak yapışır.

    ## Okumak

    - Tek görünüm ikisini birden yapar: not biçimli görünür, imlecin olduğu satır ise düzenlemeye hazır Markdown’ını gösterir.

    ## Görünüm

    - Tek görünüm: ortalanmış bir sütunda eş aralıklı yazı, Markdown işaretleri gri.
    - Görüntü › Görünüm açık, koyu ya da sistem ayarını seçer.
    - Görüntü › Büyüt (⌘+ ya da ⌘=) ve Küçült (⌘−) yazı boyutunu değiştirir.
    - Görüntü › Kelime Sayısı (⌥⌘I) kelime, karakter ve okuma süresini gösterir; seçim için de.

    ## Dosyalar

    - Notlar kendiliğinden kaydedilir. Dosya › Tüm Sürümlere Göz At… eski sürümlere götürür; Dosya › Kaydedilmiş Sürüme Dön son kaydedilen kopyaya döner.
    - Dosya › HTML, PDF, Word ya da Zengin Metin olarak dışa aktar, Düzen › Farklı Kopyala (Markdown, HTML, Zengin Metin, Düz Metin), Dosya › Yazdır.
    - Düzen › Markdown Olarak Yapıştır (⌥⌘V) kopyalanan web ya da zengin metni Markdown'a çevirir; bir tablodan kopyalanan hücreler tablo olarak yapışır, Düzen › Tablo Olarak Yapıştır CSV için de aynısını yapar.
    - Düzen › Bağlantıları Denetle… eksik dosya ve görselleri, bilinmeyen #bağlantıları ve tanımı olmayan dipnotları internete çıkmadan listeler.
    - Açık bir notu başka bir uygulama değiştirirse ve kaydedilmemiş bir şey yoksa QuickMD onu yeniden yükler.
    - Yeniden açılan not, imleç ve görünüm bıraktığınız yerde açılır.
    - Herhangi bir uygulamada metin seçip Servisler › Seçimle Yeni QuickMD Notu’nu seçebilirsiniz.

    ## Bir ajanın yazışını izlemek

    Ayarlar › Ajanların yazışını canlı izle açıkken, başka bir uygulamanın ya da bir ajanın açık nota yazdığı değişiklik kendini yazar ve yeni kısım bir an parlar. Hareketi Azalt açıkken değişiklik hemen görünür.

    ## VoiceOver ve klavye

    - VoiceOver görev kutularını onay kutusu olarak okur (VO-Boşluk işaretler), tabloları boyut ve hücreleriyle, görselleri alt metinleriyle okur.
    - Biçim › Görevi Tamamla (⌘Return) seçimdeki görevleri faresiz işaretler.

    ## Sorunlar

    Yardım › Sorun Bildir… destek sayfasını açar.

    """
}
