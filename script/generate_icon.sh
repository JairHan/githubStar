#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.png"
ICON_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/githubstar-icon.XXXXXX")"
trap 'rm -rf "$ICON_STAGE"' EXIT
ICONSET="$ICON_STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT_DIR/Assets/AppIcon.icns"
echo "Generated Assets/AppIcon.icns"
