# Security policy

## Supported versions

Only the latest release and `main` get security fixes.

## Reporting a vulnerability

Please don't open a public issue. Report it privately through GitHub: [open a private security report](https://github.com/ihsansoycelik/quickmd/security/advisories/new).

Include what you found, the macOS and QuickMD versions, and a Markdown file or steps that show it. You will get a reply within 7 days. Once a fix is out, the report is published with credit to you unless you'd rather stay anonymous.

## What counts

QuickMD treats every note as untrusted input. These are in scope:

- Script or HTML in a note that runs, or escapes the sanitiser, in the editor, export, print or `--render` output.
- A note that reads or links files outside the folders the user gave access to.
- A note that makes the app load anything over the network other than its own https images and links.
- Any way a note or a crafted file corrupts or loses data on save.
