#!/usr/bin/env bash
set -euo pipefail
MODE="${1:---release}"
APP_NAME="GitHubStar"
BUNDLE_ID="com.jair.githubstar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
usage() {
  echo "usage: $0 [--build-only|--release]"
  echo "Builds release artifacts: dist/$APP_NAME.app and dist/$APP_NAME.dmg."
  echo "Does not launch, debug, or stop the app."
}
case "$MODE" in
--build-only|--release) ;;
--help|-h) usage; exit 0 ;;
*) usage >&2; exit 2 ;;
esac
BUILD_CONFIGURATION="release"
OAUTH_CLIENT_ID="${GITHUBSTAR_OAUTH_CLIENT_ID:-}"
if [[ -z "$OAUTH_CLIENT_ID" && -f "$ROOT_DIR/Config/GitHubOAuthClientID.txt" ]]; then
  OAUTH_CLIENT_ID="$(tr -d '[:space:]' < "$ROOT_DIR/Config/GitHubOAuthClientID.txt")"
fi
if [[ -n "$OAUTH_CLIENT_ID" && ! "$OAUTH_CLIENT_ID" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "Invalid OAuth Client ID: use the public Client ID, not a secret or token." >&2
  exit 2
fi
if [[ -z "$OAUTH_CLIENT_ID" ]]; then
  echo "Release requires an OAuth Client ID. Set GITHUBSTAR_OAUTH_CLIENT_ID or Config/GitHubOAuthClientID.txt." >&2
  exit 2
fi
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/githubstar-app.XXXXXX")"
DMG_MOUNT=""
cleanup() {
  if [[ -n "$DMG_MOUNT" ]]; then
    # Keep staging intact if the image cannot be detached safely.
    /usr/bin/hdiutil detach "$DMG_MOUNT" >/dev/null || return
  fi
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
STAGED_BUNDLE="$STAGING_DIR/$APP_NAME.app"
swift build -c "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"
mkdir -p "$STAGED_BUNDLE/Contents/MacOS"
cp "$BUILD_BINARY" "$STAGED_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ ! -f "$ROOT_DIR/Assets/AppIcon.icns" ]]; then
  "$ROOT_DIR/script/generate_icon.sh"
fi
mkdir -p "$STAGED_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$STAGED_BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$STAGED_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>GitHub Star</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>GitHubOAuthClientID</key><string>$OAUTH_CLIENT_ID</string>
</dict></plist>
PLIST
# Sign outside Desktop's file provider, which may attach FinderInfo attributes.
codesign --force --sign - "$STAGED_BUNDLE" >/dev/null
codesign --verify --strict "$STAGED_BUNDLE"

# Package the validated staging bundle, before Desktop's file provider can add metadata.
DMG_CONTENTS="$STAGING_DIR/dmg-contents"
STAGED_DMG="$STAGING_DIR/$APP_NAME.dmg"
WRITABLE_DMG="$STAGING_DIR/installer-writable.dmg"
mkdir -p "$DMG_CONTENTS/.background"
/usr/bin/ditto --norsrc --noextattr "$STAGED_BUNDLE" "$DMG_CONTENTS/$APP_NAME.app"
ln -s /Applications "$DMG_CONTENTS/Applications"
swift "$ROOT_DIR/script/generate_dmg_background.swift" "$STAGING_DIR/design"
/usr/bin/tiffutil -cathidpicheck "$STAGING_DIR/design/DMGBackground-preview.png" \
  "$STAGING_DIR/design/DMGBackground@2x.png" -out "$STAGING_DIR/design/DMGBackground.tiff"
cp "$STAGING_DIR/design/DMGBackground.tiff" "$DMG_CONTENTS/.background/DMGBackground.tiff"
/usr/bin/hdiutil create -volname "GitHub Star" -srcfolder "$DMG_CONTENTS" \
  -format UDRW -fs HFS+ "$WRITABLE_DMG"
mkdir -p "$STAGING_DIR/mount"
/usr/bin/hdiutil attach -nobrowse -mountpoint "$STAGING_DIR/mount" "$WRITABLE_DMG"
DMG_MOUNT="$STAGING_DIR/mount"
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT_DIR/script/configure_dmg.py" "$DMG_MOUNT" "$APP_NAME"
/usr/bin/hdiutil detach "$DMG_MOUNT"
DMG_MOUNT=""
/usr/bin/hdiutil convert "$WRITABLE_DMG" -format UDZO -o "$STAGED_DMG"
/usr/bin/hdiutil verify "$STAGED_DMG"

mkdir -p "$ROOT_DIR/dist"
rm -rf "$APP_BUNDLE"
/usr/bin/ditto --norsrc --noextattr "$STAGED_BUNDLE" "$APP_BUNDLE"
/usr/bin/ditto --norsrc --noextattr "$STAGED_DMG" "$DMG_PATH"
echo "Built $APP_BUNDLE"
echo "Built $DMG_PATH (compressed drag-to-Applications installer)"
echo "Release build: OAuth Client ID embedded; local ad-hoc signature (not notarized)."
