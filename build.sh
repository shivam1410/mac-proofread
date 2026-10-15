#!/bin/bash
# Builds build/Proofread.app, runs the self-test, signs it, and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Proofread.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O main.swift SelectionWatcher.swift MarkdownView.swift -o "$APP/Contents/MacOS/Proofread"
"$APP/Contents/MacOS/Proofread" --selftest

# App icon: render once at 1024px, downscale into an iconset, pack as .icns.
mkdir -p "$APP/Contents/Resources" build/AppIcon.iconset
swift make_icon.swift build/icon-1024.png
for px in 16 32 128 256 512; do
  sips -z $px $px build/icon-1024.png --out "build/AppIcon.iconset/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) build/icon-1024.png --out "build/AppIcon.iconset/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.selectedit</string>
  <key>CFBundleName</key><string>Proofread</string>
  <key>CFBundleExecutable</key><string>Proofread</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
INSTALLED=/Applications/Proofread.app
pkill -x Proofread || true
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
open "$INSTALLED"
echo "Installed and launched $INSTALLED"
