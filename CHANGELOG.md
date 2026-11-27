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
- View › Paper gives the editor a warm paper background, in light and dark.

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
