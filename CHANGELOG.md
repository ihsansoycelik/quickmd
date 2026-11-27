# Changelog

Notable changes to QuickMD. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/). The version number lives in `Packaging/version`.

## [Unreleased]

### Added

- First public release of the source.
- One live-styled view: the caret line shows its Markdown, the rest reads styled.
- Tables with Tab navigation, task checkboxes, GitHub callouts, KaTeX math and Mermaid diagrams in export and print.
- Live agent writing: changes another app writes into an open note type themselves in; `==text==` highlights.
- Autosave, versions (Browse All Versions…), tabs, find and replace, HTML and PDF export, print.
- English and Turkish interface, VoiceOver support.

### Changed

- Writing keeps the page styled with the caret on a line: headings, quotes, list bullets, task boxes and the marks of bold, italic, code, strikethrough, highlight and links stay hidden, so nothing shifts as the caret moves. View › Show Markdown Syntax shows every mark, dimmed.
- The caret steps over hidden marks and never lands inside a block's marker; Home and ⌘← go to the start of the text.
- Backspace at the start of a heading, quote or list item removes its marker in one step.
- Typing `> `, `# `, `[ ] `, `1. ` or another bullet into a fresh list item replaces its marker instead of nesting.
- `**`, a backtick and `~~` close themselves while typing; typing the closing mark steps over it, Backspace on an empty pair removes both.

### Added

- Word count and reading time in the window's subtitle (View › Show Word Count).
- View › Focus dims every paragraph but the current one; View › Typewriter keeps the caret's line in the middle of the window.
- Format › Footnote, Today’s Date and Clear Formatting; Footnote and Today’s Date in the / menu too.
- An optional file sidebar (View › Show Sidebar, ⌃⌘S, or the title bar button), off by default: the notes in the document's folder as a tree, a filter field, the current note highlighted, a click to open, live updates as files change, and Open in New Window, Show in Finder and New Note Here on right-click.
- A quiet formatting bar under the text: bold, italic, strikethrough, code, link, the block style of the caret's line, lists, quote, code block, table and an insert menu, with the word count and a Paper toggle. View › Show Formatting Bar hides it; while it's shown, the word count moves from the subtitle into the bar.
- View › Paper (or Paper in the bar) switches the page between Paper and White in light, the same setting as Settings › Appearance › page colour; dark goes back to Default.
- View › Go to Heading… (⌃⌘O): a small search over the note's headings; type to filter, ↑↓ and Return to jump.
- View › Fold Section (⌥⌘←), Unfold Section (⌥⌘→) and Unfold All: a section's text hides under its heading behind a `…`, only on screen; the file never changes. Editing in it or moving the caret into it opens it again.
- Format › Heading 5 and Heading 6 (⌥⌘5, ⌥⌘6), Promote Heading (⌃⌘↑) and Demote Heading (⌃⌘↓).
- Format › Move Line Up and Down (⌥⌘↑, ⌥⌘↓; a list item moves with its nested items) and Delete Line (⇧⌘K), each one undo step.
- Format › Check Selected and Uncheck Selected tick or clear every task in the selection.
- Format › Table: add, delete and move rows and columns, align a column left, centre or right, and tidy the table.
- Format › Highlight (⇧⌘H) toggles `==highlight==`.
- Format › Table of Contents (linked, nested by level) and Front Matter (title and date, only if the note has none); both in the / menu too.
- Edit › Copy Link to Heading copies `[Title](#anchor)` for the heading under the caret.
- Edit › Copy As › Markdown, HTML (⌥⌘C), Rich Text (⌥⇧⌘C) and Plain Text, for the selection or the whole note. Rich text pastes formatted into Mail, Pages and Notes.
- Edit › Paste as Markdown (⌥⌘V) turns copied HTML or rich text into Markdown; ⌘V does it too when the pasteboard has HTML but no plain text.
- Cells copied from Numbers, Excel or Sheets paste as a Markdown table; Edit › Paste as Table does the same for CSV or TSV text.
- File › Export as Word… (.docx) and Export as Rich Text… (.rtf). Images are left out (their alt text stays), so nothing is fetched.
- Edit › Check Links… lists missing files and images, `#anchors` with no heading and footnotes with no definition, by line; clicking one selects it. Web links are only counted, never fetched.
- Settings › Appearance: writing font (Mono, Duo, Sans, Serif; code stays monospaced), line width (Narrow, Normal, Wide) and page colour (Paper, White or Grey in light, Default or Black in dark). Export and print follow the font and width.
- Settings › Writing: Focus on the paragraph or the sentence; fade the title bar and tabs while typing; smart quotes and dashes (off by default, never in code); book paragraphs (indented first lines, no gap between paragraphs, display only); reading speed.
- View › Show Count As words, characters or lines; View › Writing Goal… sets a word target per note, kept on this Mac and not in the file, shown as “320 / 1,000 words”.
- View › Show Writing Aids: dotted underlines for long sentences, repeated words, fillers and hedges (English and Turkish), -ly adverbs and possible passives (English). On-device, never saved; each aid can be turned off in Settings.
- Settings is now four panes: Appearance, Writing, Writing Aids and General, with a short description under each switch.

### Fixed

- UTF-16 big-endian files are saved in their own byte order instead of the Mac's.
- Heading links (`#slug`) work in a note that starts with `---` and `key:` but never closes the front matter.
- Return at the start of a list line (or inside its number) no longer doubles the marker.
- Return on an empty nested item leaves the caret after the outdented marker.
- Tab on a line that starts with `|` but isn't in a table inserts a tab instead of reformatting the line.
- A wrapped line that starts with a number, like `2019. It rained.`, stays in its paragraph instead of starting a list.
- Live-writing playback stops when its window closes.

### Security

- HTML comments in notes are dropped, so a comment browsers close early (`<!-->`, `--!>`) can't carry unsanitised tags.
- Image alt and title text can't break out of their attributes; `<plaintext>` is dropped.
- Zero-padded character references and `[[wiki links]]` can't smuggle a `javascript:` URL.
- Raw HTML in notes is sanitised; the export's Content-Security-Policy no longer allows every scheme for images and media.
