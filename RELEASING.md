# Releasing and updating QuickMD

The repository is public, so `main` is what people see and clone. Day-to-day work and releases both happen on a Mac.

## Everyday changes

```sh
git checkout -b fix/short-name     # or work on main for small changes
# edit
swift test
./scripts/build-app.sh --install   # try it in the real app
```

Add a line under `## [Unreleased]` in `CHANGELOG.md` for anything users will notice, commit, and push. For a branch, open a pull request and merge it on GitHub.

Merged pull requests from other people: pull them before you start new work (`git pull`).

## Publishing a version

1. Pick the number: `X.Y.Z` with Semantic Versioning (fix: Z+1, feature: Y+1, breaking change: X+1).
2. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add a fresh empty `## [Unreleased]` above it. Commit and push.
3. Run:

   ```sh
   ./scripts/release.sh X.Y.Z            # add --draft to check the release page before it goes public
   ```

   It runs the tests, writes the version into `Packaging/version`, builds `build/QuickMD.app`, zips it, tags `vX.Y.Z`, pushes, and creates the GitHub release with the changelog section as notes.

These downloads are ad-hoc signed, not notarized, and the release notes say how to open them. Notarized builds need an Apple Developer ID; when there is one, add `codesign` with the Developer ID and `xcrun notarytool submit --wait` to `release.sh` before the zip step.

## Mac App Store

The App Store build is separate: `./scripts/build-app.sh --appstore` (see the README). It bumps `BUILD_NUMBER` in `Packaging/version` and commits it, so push after each upload.

## Repository settings

- Issues and private vulnerability reporting are on. Security and conduct reports arrive under Security › Advisories.
- The `docs/` folder is served by GitHub Pages at https://ihsansoycelik.github.io/quickmd/ (the app's Help menu links to its support and privacy pages).
- Labels used for triage: `bug`, `enhancement`, `good first issue`, `help wanted`, `translation`, `question`.
