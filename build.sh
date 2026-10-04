#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ "$(uname -s)" != Darwin ]; then
    echo 'Building requires macOS and the Apple Command Line Tools.' >&2
    exit 1
fi
app='build/Cam Link Indicator.app'
mkdir -p "$app/Contents/MacOS"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter \
    -mmacosx-version-min=13.0 CamLinkIndicator.m \
    -framework AppKit -framework IOKit -framework QuartzCore \
    -o "$app/Contents/MacOS/CamLinkIndicator"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CamLinkIndicator</string>
<key>CFBundleIdentifier</key><string>local.camlink.signal-indicator</string>
<key>CFBundleName</key><string>Cam Link Indicator</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
"$app/Contents/MacOS/CamLinkIndicator" --self-test
printf '\nBuilt %s\n' "$app"
