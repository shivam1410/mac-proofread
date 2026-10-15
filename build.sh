#!/bin/bash
# Builds build/SelectEdit.app, runs the self-test, and signs it ad hoc.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SelectEdit.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O main.swift SelectionWatcher.swift -o "$APP/Contents/MacOS/SelectEdit"
"$APP/Contents/MacOS/SelectEdit" --selftest

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.selectedit</string>
  <key>CFBundleName</key><string>SelectEdit</string>
  <key>CFBundleExecutable</key><string>SelectEdit</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# A real (even self-signed) identity keeps the signature stable across rebuilds, so macOS
# remembers the Accessibility and Keychain grants. Ad-hoc ("-") changes every build.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' 'NR==1 && NF>1 {print $2}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc}"
echo "Built $APP"

# Install over the copy that Login Items launches, then restart it.
INSTALLED=/Applications/SelectEdit.app
pkill -x SelectEdit || true
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
open "$INSTALLED"
echo "Installed and launched $INSTALLED"
