# QuickMD

[![MIT License](https://img.shields.io/github/license/ihsansoycelik/quickmd)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)
![Swift 6 toolchain](https://img.shields.io/badge/Swift-6-orange)

A native macOS Markdown editor. Opens `.md` files from Finder and Quick Look ("Open with QuickMD"). Written in Swift with AppKit, no Electron, no web view for editing.

When an AI agent writes a note you have open, QuickMD shows the change typing itself in. See [Watching an agent write](#watching-an-agent-write).

## Features

- Live-styled editing: headings, bold/italic/strike, code, quotes, lists, tasks, links, rules. The file stays plain Markdown.
- One look, after iA Writer: SF Mono in a 64-character column centred in the window, generous leading, a blue caret, Markdown marks in grey. Light, dark or system. No themes, fonts or transparency to pick.
- Tables (Tab / ⇧Tab moves between cells and lines up the columns; Tab past the end adds a row), real checkboxes for tasks, GitHub callouts (`> [!TIP]`), `$…$` / `$$…$$` math, Mermaid diagrams and syntax-coloured code blocks. Export and print typeset math (KaTeX) and diagrams (Mermaid) offline.
- One view for reading and writing: the note shows itself styled, and the line the caret is in shows its Markdown, ready to edit. No sidebar, no toolbar, no footer.
- Smart lists: Return continues a list, Tab/⇧Tab indents, click a `[ ]` to tick it.
- ⌘-click a link to open it; relative `.md` links open in QuickMD, `#anchor` links jump to the heading.
- Type `*`, `` ` ``, `[`, `(` … over a selection to wrap it; paste a URL over words to link them; drop files or images in to link them.
- Autosave, versions, tabs, find & replace, export HTML or PDF, copy as HTML, print the rendered note.
- CRLF files stay CRLF on disk. Raw HTML in notes is sanitised and never runs script from a note.
- Reloads quietly when another app changes the file and nothing is unsaved.
- Fonts, text size and light/dark/system theme in the Format and View menus.
- English and Turkish interface.

## Install

QuickMD is built from source for now. You need macOS 13 or later and the Swift toolchain (the Xcode Command Line Tools are enough: `xcode-select --install`).

```sh
git clone https://github.com/ihsansoycelik/quickmd.git
cd quickmd
./scripts/build-app.sh --install   # builds, copies to /Applications, makes it the default .md app
```

To update later:

```sh
git pull
./scripts/build-app.sh --install
```

Prebuilt downloads, when there are any, are on the [Releases](https://github.com/ihsansoycelik/quickmd/releases) page. Those builds are not notarized yet, so macOS will block the first launch: right-click QuickMD.app and choose Open, or run `xattr -dr com.apple.quarantine /Applications/QuickMD.app`.

## Watching an agent write

With **Settings › Watch agents write live** on (the default), when an agent or any other app writes a note that's open in QuickMD, the change types itself in: the window comes forward without taking the keyboard, follows the new text, and the part that arrived glows for a moment. A note opened within three seconds of being written plays in from empty. `==text==` is drawn highlighted, so an agent can mark what you should read first.

It works with any agent that writes files. The agent only has to open the note in QuickMD, before writing when the file exists:

```sh
open -g -a QuickMD notes/plan.md   # -g: shows the window, keeps your terminal focused
```

**Claude Code** does it with a hook. Add to `~/.claude/settings.json` (or a project's `.claude/settings.json`), with the path to this repo:

```json
{
  "hooks": {
    "PreToolUse":  [{ "matcher": "Write|Edit|MultiEdit", "hooks": [{ "type": "command", "command": "/path/to/quickmd/scripts/quickmd-agent-hook.sh" }] }],
    "PostToolUse": [{ "matcher": "Write|Edit|MultiEdit", "hooks": [{ "type": "command", "command": "/path/to/quickmd/scripts/quickmd-agent-hook.sh" }] }]
  }
}
```

**Other agents** (Codex, Cursor, Gemini CLI, Aider…): put this in their instructions file (`AGENTS.md`, `GEMINI.md`, `.cursorrules`):

> When you write or edit a Markdown file for me, run `open -g -a QuickMD <file>` first (after creating it, if it's new), then write it. Wrap the lines I must read or decide on in `==…==`.

## Build and test

```sh
./scripts/build-app.sh            # build/QuickMD.app (universal, ad-hoc signed)
./scripts/build-app.sh --install  # copy to /Applications and make it the default .md app
./scripts/build-app.sh --sandbox  # local build with the App Store sandbox, for testing
swift test                        # renderer and editor regression tests
```

`QuickMD --render file.md` prints a file as HTML (`--page [--dark]` for a whole page). Not in the App Store build.

Mac App Store: `TEAM_ID=… SIGN_IDENTITY="Apple Distribution: …" INSTALLER_IDENTITY="3rd Party Mac Developer Installer: …" PROVISIONING_PROFILE=… ./scripts/build-app.sh --appstore` makes a signed, sandboxed `build/QuickMD.pkg` (entitlements and privacy manifest in `Packaging/`). Upload with Transporter. The version lives in `Packaging/version`; each `--appstore` build bumps the build number there and commits it, and refuses to run on an uncommitted tree.

Releases on GitHub are made with `scripts/release.sh`; see [RELEASING.md](RELEASING.md).

## Project layout

| Path | What is there |
|---|---|
| `Sources/QuickMD/` | The app: document model, editor view, Markdown styler, HTML renderer, menus, settings |
| `Tests/QuickMDTests/` | `swift test` suites for the renderer, editor, file codec and safety rules |
| `Resources/` | Bundled KaTeX and Mermaid (each with its license) and the en/tr strings |
| `Packaging/` | Info.plist template, entitlements, privacy manifest, `version` |
| `scripts/` | Build, release, icon and agent hook scripts |
| `docs/` | The small support and privacy site |

## Contributing

Bug reports, fixes, translations and small features are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; issues marked [good first issue](https://github.com/ihsansoycelik/quickmd/labels/good%20first%20issue) are a good place to start. Plans are in [ROADMAP.md](ROADMAP.md), changes in [CHANGELOG.md](CHANGELOG.md).

Security problems: see [SECURITY.md](SECURITY.md). Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Credits

Started from the editor core of [Wisp](https://github.com/sulemaanhamza/wisp) by Suleman Hamza (MIT). See LICENSE.

Bundled: KaTeX (MIT), Mermaid (MIT), in `Resources/`, each with its license.

## License

[MIT](LICENSE).
