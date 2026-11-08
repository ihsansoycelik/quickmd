import Foundation

/// Help › QuickMD Help opens this as an untitled note: the guide is
/// written in the format it explains, and needs no help book.
enum Help {
    static let text = """
    # QuickMD Help

    QuickMD edits plain Markdown files. What you see styled is still plain text on disk.

    ## Writing

    - Type `/` at the start of a line for blocks: headings, lists, tables, callouts, math, diagrams.
    - Format menu: **Bold** ⌘B, *Italic* ⌘I, Link ⌘K, Heading ⌥⌘1–4, Body Text ⌥⌘0.
    - Type `*`, `` ` ``, `[` or `(` over a selection to wrap it. Paste a URL over words to link them.
    - Return continues a list; Tab and ⇧Tab indent. Click a `[ ]` box to tick it.
    - In a table, Tab and ⇧Tab move between cells; Tab past the last cell adds a row.
    - ⌘-click a link to open it. Links to other `.md` files open in QuickMD.

    ## Reading

    - One view does both: the note shows itself styled — headings, lists, tables, code — and the line the caret is in shows its Markdown, ready to edit.

    ## Look

    - One look, after iA Writer: a monospaced face in a centred column, Markdown's marks in grey.
    - View › Appearance picks light, dark or the system setting.
    - View › Bigger (⌘+ or ⌘=) and Smaller (⌘−) change the text size.

    ## Files

    - Notes save themselves. File › Revert To Saved goes back to any earlier version.
    - File › Export as HTML or PDF, Edit › Copy as HTML, File › Print.
    - When another app changes an open note and nothing is unsaved, QuickMD reloads it.

    ## Watching an agent write

    With Settings › General › Watch agents write live on, a change another app or an agent writes into an open note types itself in, and the new part glows for a moment. With Reduce Motion on, the change appears at once.

    """
}
