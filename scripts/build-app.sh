#!/usr/bin/env bash
# Builds build/QuickMD.app (universal).
#
#   ./scripts/build-app.sh             local build, ad-hoc signed
#   ./scripts/build-app.sh --sandbox   the same, sandboxed like the App Store build (for testing)
#   ./scripts/build-app.sh --install   local build, copied to /Applications and made the .md default
#   ./scripts/build-app.sh --appstore  Mac App Store build: signed .app and build/QuickMD.pkg
#
# --appstore needs, from the environment:
#   TEAM_ID                 your Apple Developer team ID
#   SIGN_IDENTITY           e.g. "Apple Distribution: Your Name (TEAMID)"
#   INSTALLER_IDENTITY      e.g. "3rd Party Mac Developer Installer: Your Name (TEAMID)"
#   PROVISIONING_PROFILE    path to the Mac App Store provisioning profile for BUNDLE_ID
# Optional: BUNDLE_ID (default com.ursula.quickmd).
#
# The version comes from Packaging/version. --appstore needs a clean working
# tree, then bumps BUILD_NUMBER there and commits it, so every upload is new.
# Info.plist is Packaging/Info.plist with the __PLACEHOLDERS__ filled in.
set -euo pipefail

MODE="${1:-}"
NAME="QuickMD"
BUNDLE_ID="${BUNDLE_ID:-com.ursula.quickmd}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT/Packaging/version"
# shellcheck source=../Packaging/version
source "$VERSION_FILE"
APP_DIR="$ROOT/build/$NAME.app"
ENTITLEMENTS="$ROOT/Packaging/QuickMD.entitlements"

SWIFT_FLAGS=()
ARCH_DIR="$ROOT/.build-universal"
if [[ "$MODE" == "--appstore" ]]; then
    for var in TEAM_ID SIGN_IDENTITY INSTALLER_IDENTITY PROVISIONING_PROFILE; do
        [[ -n "${!var:-}" ]] || { echo "error: --appstore needs $var (see the top of this script)" >&2; exit 1; }
    done
    [[ -f "$PROVISIONING_PROFILE" ]] || { echo "error: no profile at $PROVISIONING_PROFILE" >&2; exit 1; }
    # A release must be reproducible from a commit.
    [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "error: --appstore needs a clean working tree; commit first" >&2; exit 1; }
    BUILD_NUMBER=$((BUILD_NUMBER + 1))
    sed -i '' "s/^BUILD_NUMBER=.*/BUILD_NUMBER=$BUILD_NUMBER/" "$VERSION_FILE"
    git -C "$ROOT" commit -q -m "Build $MARKETING_VERSION ($BUILD_NUMBER)" -- "$VERSION_FILE"
    # Leaves out the developer-only command line (--render, --make-default).
    SWIFT_FLAGS=(-Xswiftc -DAPPSTORE)
    ARCH_DIR="$ROOT/.build-universal-appstore"
fi

# Two single-arch builds plus lipo: works with bare Command Line Tools.
SLICES=()
for TRIPLE in arm64-apple-macosx13.0 x86_64-apple-macosx13.0; do
    echo "Building $TRIPLE"
    swift build -c release --package-path "$ROOT" --triple "$TRIPLE" --scratch-path "$ARCH_DIR/$TRIPLE" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
    BIN_DIR="$(swift build -c release --package-path "$ROOT" --triple "$TRIPLE" --scratch-path "$ARCH_DIR/$TRIPLE" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --show-bin-path)"
    SLICES+=("$BIN_DIR/$NAME")
done
lipo -create "${SLICES[@]}" -output "$ARCH_DIR/$NAME"
# Symbols for crash reports, taken before stripping.
rm -rf "$ROOT/build/$NAME.app.dSYM"
dsymutil "$ARCH_DIR/$NAME" -o "$ROOT/build/$NAME.app.dSYM"
strip -x "$ARCH_DIR/$NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ARCH_DIR/$NAME" "$APP_DIR/Contents/MacOS/$NAME"
cp "$ROOT/scripts/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
# Bundled fonts (Inter, QuickMD Myeongjo), KaTeX and Mermaid, each with
# its license; the app's own license and credits for the About panel.
cp -R "$ROOT/Resources/Fonts" "$ROOT/Resources/katex" "$ROOT/Resources/mermaid" "$APP_DIR/Contents/Resources/"
cp "$ROOT/LICENSE" "$APP_DIR/Contents/Resources/LICENSE.txt"
cp "$ROOT/Packaging/Credits.rtf" "$ROOT/Packaging/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/"
find "$APP_DIR" -name .DS_Store -delete

sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$MARKETING_VERSION/" -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/" \
    "$ROOT/Packaging/Info.plist" > "$APP_DIR/Contents/Info.plist"
! grep -q '__[A-Z_]*__' "$APP_DIR/Contents/Info.plist" || { echo "error: unfilled placeholder in Info.plist" >&2; exit 1; }
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
# Uploads must not carry quarantine (or any other) extended attributes.
xattr -cr "$APP_DIR"

case "$MODE" in
--appstore)
    cp "$PROVISIONING_PROFILE" "$APP_DIR/Contents/embedded.provisionprofile"
    SIGNED_ENTITLEMENTS="$ROOT/build/QuickMD.appstore.entitlements"
    cp "$ENTITLEMENTS" "$SIGNED_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "$SIGNED_ENTITLEMENTS" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "$SIGNED_ENTITLEMENTS" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$SIGNED_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$SIGNED_ENTITLEMENTS"
    codesign --force --timestamp --options runtime --generate-entitlement-der \
        --entitlements "$SIGNED_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
    productbuild --component "$APP_DIR" /Applications --sign "$INSTALLER_IDENTITY" "$ROOT/build/$NAME.pkg"
    echo "Built $ROOT/build/$NAME.pkg ($MARKETING_VERSION, build $BUILD_NUMBER)"
    echo "Check and upload it with Transporter, or:"
    echo "  xcrun altool --validate-app -f build/$NAME.pkg -t macos --apiKey … --apiIssuer …"
    ;;
--sandbox)
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR"
    echo "Built $APP_DIR (sandboxed, ad-hoc)"
    ;;
*)
    # Ad-hoc sign so macOS runs it locally without complaint.
    codesign --force --sign - "$APP_DIR"
    echo "Built $APP_DIR"
    ;;
esac

if [[ "$MODE" == "--install" ]]; then
    pkill -x "$NAME" 2>/dev/null || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP_DIR" "/Applications/$NAME.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$NAME.app"
    open -a "/Applications/$NAME.app" --args --make-default
    echo "Installed /Applications/$NAME.app"
fi
