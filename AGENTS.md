# Working on QuickMD (for agents and people)

QuickMD is a native macOS Markdown editor in Swift and AppKit, built with SwiftPM. It needs macOS 13+ and builds with the Command Line Tools alone; there is no Xcode project.

## Commands

- `swift test`: run all tests. Run it before every commit.
- `./scripts/build-app.sh`: build `build/QuickMD.app` (universal, ad-hoc signed).
- `./scripts/build-app.sh --install`: build, install to /Applications, make it the default .md app. Use it to check a change in the real app.
- `QuickMD --render file.md [--page] [--dark]`: print the HTML renderer's output, handy for renderer bugs.

## Rules

- The file on disk is the source of truth and stays plain Markdown. Styling must never change the text that gets saved (line endings, BOM, encoding and padding included).
- One view: no preview pane or toolbar. The only side panel is the optional file sidebar (View › Show Sidebar), off by default; the only bar is the optional bottom formatting bar (View › Show Formatting Bar). New features fit into the editor, menus, settings or that bar.
- Notes are untrusted input. Raw HTML is sanitised and scripts from a note never run; keep the Content-Security-Policy in `MarkdownHTML.swift` tight.
- No network access from the app beyond what a note itself asks for (its links and https images in export and print).
- Every user-facing string goes through `L("…")`. English text is the key; add its translation to `Resources/Localization/tr.lproj/Localizable.strings`.
- Add or update a test in `Tests/QuickMDTests/` for each bug fix.
- Note user-visible changes under "Unreleased" in `CHANGELOG.md`.
- Bundled KaTeX and Mermaid in `Resources/` are third-party files; update them as a whole, with their licenses.
