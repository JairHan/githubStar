#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/githubstar-rendering.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
APP="$TEST_DIR/ReadmeRenderingValidation.app"
OUTPUT_DIR="$ROOT_DIR/.build/readme-rendering"
mkdir -p "$APP/Contents/MacOS" "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/result.json"
swiftc -parse-as-library Sources/GitHubStar/Support/ViewState.swift Sources/GitHubStar/Models/ReadmeDocument.swift \
  Sources/GitHubStar/Services/ReadmeHTMLRenderer.swift Sources/GitHubStar/Views/ReadmeWebView.swift \
  Tests/Rendering/ReadmeRenderingValidation.swift -o "$APP/Contents/MacOS/ReadmeRenderingValidation"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ReadmeRenderingValidation</string>
<key>CFBundleIdentifier</key><string>com.jair.githubstar.readme-validation</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
/usr/bin/open -W -n "$APP" --args "$OUTPUT_DIR/result.json" "$@"
python3 - "$OUTPUT_DIR/result.json" <<'PY'
import json
import sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
for check in result['checks']:
    print('PASS:', check)
if not result['passed']:
    raise SystemExit('FAIL: ' + result['error'])
print('Rendering snapshots:', Path(sys.argv[1]).parent)
PY
