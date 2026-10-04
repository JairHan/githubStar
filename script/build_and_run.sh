#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
APP_NAME="GitHubStar"
BUNDLE_ID="com.jair.githubstar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
BUILD_CONFIGURATION="debug"
OAUTH_CLIENT_ID="${GITHUBSTAR_OAUTH_CLIENT_ID:-}"
if [[ -z "$OAUTH_CLIENT_ID" && -f "$ROOT_DIR/Config/GitHubOAuthClientID.txt" ]]; then
  OAUTH_CLIENT_ID="$(tr -d '[:space:]' < "$ROOT_DIR/Config/GitHubOAuthClientID.txt")"
fi
if [[ -n "$OAUTH_CLIENT_ID" && ! "$OAUTH_CLIENT_ID" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "Invalid OAuth Client ID: use the public Client ID, not a secret or token." >&2
  exit 2
fi
if [[ "$MODE" == "--release" ]]; then
  if [[ -z "$OAUTH_CLIENT_ID" ]]; then
    echo "Release requires an OAuth Client ID. Set GITHUBSTAR_OAUTH_CLIENT_ID or Config/GitHubOAuthClientID.txt." >&2
    exit 2
  fi
  BUILD_CONFIGURATION="release"
fi
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/githubstar-app.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_BUNDLE="$STAGING_DIR/$APP_NAME.app"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build -c "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"
mkdir -p "$STAGED_BUNDLE/Contents/MacOS"
cp "$BUILD_BINARY" "$STAGED_BUNDLE/Contents/MacOS/$APP_NAME"
cat > "$STAGED_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>GitHub Star</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>GitHubOAuthClientID</key><string>$OAUTH_CLIENT_ID</string>
</dict></plist>
PLIST
# Sign outside Desktop's file provider, which may attach FinderInfo attributes.
codesign --force --sign - "$STAGED_BUNDLE" >/dev/null
mkdir -p "$ROOT_DIR/dist"
rm -rf "$APP_BUNDLE"
/usr/bin/ditto --norsrc --noextattr "$STAGED_BUNDLE" "$APP_BUNDLE"
case "$MODE" in
run) /usr/bin/open -n "$APP_BUNDLE" ;;
--verify|verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
--debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
--logs|logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
--telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
--build-only) ;;
--release) echo "Built $APP_BUNDLE (OAuth Client ID embedded; local ad-hoc signature)" ;;
*) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry|--build-only|--release]" >&2; exit 2 ;;
esac
