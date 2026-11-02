# QuickMD

A native macOS Markdown editor. Opens `.md` files from Finder and Quick Look ("Open with QuickMD").

- Live-styled editing: headings, bold/italic/strike, code, quotes, lists, tasks, links, rules. The file stays plain Markdown.
- Invisible Details template (default, Format › Template): Inter body in grey at 160% leading, Myeongjo serif headings, 16pt paragraph gaps, after invisibledetails.com. Classic keeps the old look and the Font menu.
- Tables (Tab / ⇧Tab moves between cells and lines up the columns; Tab past the end adds a row), real checkboxes for tasks, GitHub callouts (`> [!TIP]`), `$…$` / `$$…$$` math, Mermaid diagrams and syntax-coloured code blocks. The preview typesets math (KaTeX) and diagrams (Mermaid) offline, and its checkboxes edit the file.
- A unified toolbar: outline toggle over the sidebar, a Format menu, preview and Share. Customise it from View › Customize Toolbar.
- Reading mode (⌥⌘P) that shows the note without Markdown marks, outline sidebar (⌃⌘S), a footer that counts words, characters or reading time (click it).
- Smart lists: Return continues a list, Tab/⇧Tab indents, click a `[ ]` to tick it.
- ⌘-click a link to open it; relative `.md` links open in QuickMD, `#anchor` links jump to the heading.
- Type `*`, `` ` ``, `[`, `(` … over a selection to wrap it; paste a URL over words to link them; drop files or images in to link them.
- Autosave, versions, tabs, find & replace, export HTML or PDF, copy as HTML, print the rendered note.
- CRLF files stay CRLF on disk. Raw HTML in notes is sanitised and the preview runs no script from a note.
- Reloads quietly when another app changes the file and nothing is unsaved.
- Fonts, text size and light/dark/system theme in the Format and View menus.

## Watching an agent write

With **Settings › General › Watch agents write live** on (the default), when an agent or any other app writes a note that's open in QuickMD, the change types itself in: the window comes forward without taking the keyboard, follows the new text, and the part that arrived glows for a moment. A note opened within three seconds of being written plays in from empty. `==text==` is drawn highlighted, so an agent can mark what you should read first.

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

## Build

Requires macOS 13+ and the Swift toolchain (Command Line Tools are enough).

```sh
./scripts/build-app.sh            # build/QuickMD.app
./scripts/build-app.sh --install  # copy to /Applications and make it the default .md app
./scripts/build-app.sh --sandbox  # local build with the App Store sandbox, for testing
swift test                        # renderer and editor regression tests
```

Mac App Store: `TEAM_ID=… SIGN_IDENTITY="Apple Distribution: …" INSTALLER_IDENTITY="3rd Party Mac Developer Installer: …" PROVISIONING_PROFILE=… ./scripts/build-app.sh --appstore` makes a signed, sandboxed `build/QuickMD.pkg` (entitlements and privacy manifest in `Packaging/`). Upload with Transporter. The version lives in `Packaging/version`; each `--appstore` build bumps the build number there and commits it, and refuses to run on an uncommitted tree.

`QuickMD --render file.md` prints a file as HTML (`--page [--dark]` for a whole page). Not in the App Store build.

Bundled: Inter (OFL), QuickMD Myeongjo (OFL; a renamed Latin subset of Nanum Myeongjo), KaTeX (MIT), Mermaid (MIT), in `Resources/`, each with its license.

## Credits

Started from the editor core of [Wisp](https://github.com/sulemaanhamza/wisp) by Suleman Hamza (MIT). See LICENSE.
