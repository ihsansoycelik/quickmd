# Contributing to QuickMD

Thanks for helping. Bug reports, fixes, translations, docs and small features are all welcome.

## Before you start

- For a bug, open an issue with the bug report form. A small `.md` file that shows the problem helps most.
- For a feature, open an issue first so we can agree it fits. QuickMD keeps one quiet view on purpose (no sidebar, toolbar or preview pane), so some ideas will be a no; asking first saves you work.
- Issues labelled `good first issue` are small and well scoped. Comment on one to take it.

## Set up

You need macOS 13+ and the Swift toolchain (`xcode-select --install` is enough).

```sh
git clone https://github.com/<you>/quickmd.git
cd quickmd
swift test
./scripts/build-app.sh --install
```

## Making a change

1. Branch from `main`.
2. Keep the change focused: one fix or feature per pull request.
3. Add or update a test in `Tests/QuickMDTests/` when you fix a bug or change editor behaviour.
4. Put every new user-facing string through `L("…")` and add it to both `Resources/Localization/en.lproj/Localizable.strings` and `tr.lproj/Localizable.strings`. If you don't speak Turkish, copy the English text and say so in the pull request.
5. Run `swift test` and try the change in the built app.
6. Add a line under "Unreleased" in `CHANGELOG.md` if users will notice the change.
7. Open the pull request and fill in the template. Screenshots or a short screen recording help for anything visual.

The rules the code follows are in [AGENTS.md](AGENTS.md). The most important one: the file on disk stays exactly what the user wrote, plain Markdown.

## Translations

The interface strings are in `Resources/Localization/<language>.lproj/`. To add a language, copy `en.lproj` to a new folder named with the language code (for example `de.lproj`), translate the right-hand side of each line, and open a pull request.

## Using AI tools

Pull requests written with AI help are fine. You are responsible for the change: read it, test it, and make sure you can explain it.

## Code of Conduct

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing you agree that your work is released under the [MIT License](LICENSE).
