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
