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

### Security

- Raw HTML in notes is sanitised; the export's Content-Security-Policy no longer allows every scheme for images and media.
