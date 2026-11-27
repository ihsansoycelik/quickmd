# QuickMD

[![MIT License](https://img.shields.io/github/license/ihsansoycelik/quickmd)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)

A Markdown editor for macOS, written in Swift and AppKit.

QuickMD edits plain `.md` files in a single styled view. The line under the caret shows its
Markdown; everything else is rendered. When another program writes to an open file, the change
is shown as it arrives, which is handy when an AI agent is writing your notes.

## Features

- Live styling for headings, emphasis, code, quotes, lists, task lists and links
- Tables with Tab navigation and column alignment
- Math (`$…$`, `$$…$$`), Mermaid diagrams, GitHub callouts, highlighted code blocks
- Export to HTML or PDF, print, copy as HTML (KaTeX and Mermaid bundled, works offline)
- Autosave, versions, tabs, find and replace
- Reloads files changed by other apps
- English and Turkish

## Install

Requires macOS 13 or later and the Swift toolchain (`xcode-select --install` is enough).

```sh
git clone https://github.com/ihsansoycelik/quickmd.git
cd quickmd
./scripts/build-app.sh --install
```

This builds the app, copies it to `/Applications` and sets it as the default app for `.md` files.
To update, `git pull` and run the same script again.

Builds on the [Releases](https://github.com/ihsansoycelik/quickmd/releases) page are not
notarized. On first launch, right-click QuickMD.app and choose Open.

## Agent integration

With Settings › Watch agents write live turned on (the default), QuickMD follows changes to an
open note and highlights the new text. The writer only needs to open the file in QuickMD first:

```sh
open -g -a QuickMD notes/plan.md
```

For Claude Code, add the bundled hook to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse":  [{ "matcher": "Write|Edit|MultiEdit", "hooks": [{ "type": "command", "command": "/path/to/quickmd/scripts/quickmd-agent-hook.sh" }] }],
    "PostToolUse": [{ "matcher": "Write|Edit|MultiEdit", "hooks": [{ "type": "command", "command": "/path/to/quickmd/scripts/quickmd-agent-hook.sh" }] }]
  }
}
```

Other agents (Codex, Cursor, Gemini CLI, Aider) can be told the same thing in their instructions
file: run `open -g -a QuickMD <file>` before writing a Markdown file. Text wrapped in `==…==` is
drawn highlighted.

## Development

```sh
./scripts/build-app.sh            # build/QuickMD.app
./scripts/build-app.sh --sandbox  # with the App Store sandbox
swift test
```

`QuickMD --render file.md` prints a file as HTML. App Store and GitHub release builds are
described in [RELEASING.md](RELEASING.md).

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Security issues:
[SECURITY.md](SECURITY.md).

## Credits

Based on the editor core of [Wisp](https://github.com/sulemaanhamza/wisp) by Suleman Hamza (MIT).
Bundles KaTeX and Mermaid (both MIT).

## License

[MIT](LICENSE)
