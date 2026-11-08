import AppKit

// `QuickMD --render file.md` prints the file as HTML and exits. Add
// `--page` for a whole page in the Invisible Details look (`--dark`
// for the dark one), with the app's own fonts, KaTeX and Mermaid
// copied in, so the page works offline and on any machine.
// A developer tool: the sandboxed App Store build can't read a path
// given on the command line, so it's left out there.
#if !APPSTORE
if let flag = CommandLine.arguments.firstIndex(of: "--render") {
    func fail(_ message: String, _ code: Int32) -> Never {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        exit(code)
    }
    let args = CommandLine.arguments
    guard flag + 1 < args.count, !args[flag + 1].hasPrefix("--") else {
        fail("usage: QuickMD --render <file.md> [--page [--dark]]", 2)
    }
    let path = args[flag + 1]
    guard let data = FileManager.default.contents(atPath: path) else { fail("Can't read \(path)", 1) }
    // Read as the app does: UTF-8, else whatever encoding the bytes suggest.
    var text: String
    if let utf8 = String(data: data, encoding: .utf8) {
        text = utf8
    } else {
        var converted: NSString?
        guard NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil) != 0,
              let converted else { fail("Can't read \(path)", 1) }
        text = converted as String
    }
    if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    if args.contains("--page") {
        let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        print(MarkdownHTML.page(
            body: MarkdownHTML.render(text), title: title, theme: args.contains("--dark") ? .dark : .light,
            template: .looq, fontFamily: FontFace.sanFrancisco.cssFamily, fontSize: 16, baseURL: nil, assets: .embedded
        ), terminator: "")
        exit(0)
    }
    print(MarkdownHTML.render(text), terminator: "")
    exit(0)
}
#endif

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
