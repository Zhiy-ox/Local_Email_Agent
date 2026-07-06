#!/usr/bin/env bash
# Builds "Email Agent.app" from the SwiftPM package and launches it.
# Double-click in Finder, or run ./build_app.command
# Requires: Xcode or the Command Line Tools (xcode-select --install)
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift toolchain not found. Install it with:  xcode-select --install" >&2
  exit 1
fi

echo "Building EmailAgentUI (release)..."
swift build -c release

BIN="$(swift build -c release --show-bin-path)/EmailAgentUI"
APP="build/Email Agent.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EmailAgentUI"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Email Agent</string>
  <key>CFBundleDisplayName</key><string>Email Agent</string>
  <key>CFBundleIdentifier</key><string>com.emailagent.desktop</string>
  <key>CFBundleExecutable</key><string>EmailAgentUI</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || echo "(ad-hoc codesign skipped)"

echo
echo "Built: $PWD/$APP"
echo "Tip: drag it into /Applications to keep it. Launching now..."
open "$APP"
