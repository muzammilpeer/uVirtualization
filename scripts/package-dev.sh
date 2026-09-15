#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/build.sh
app="$PWD/.build/uVirtualization.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/debug/uVirtualization "$app/Contents/MacOS/uVirtualization"
cp .build/debug/uvm "$app/Contents/MacOS/uvm"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.uvirtualization.app</string>
<key>CFBundleName</key><string>uVirtualization</string>
<key>CFBundleExecutable</key><string>uVirtualization</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "${SIGNING_IDENTITY:--}" --entitlements Resources/uvm.entitlements "$app/Contents/MacOS/uvm"
codesign --force --sign "${SIGNING_IDENTITY:--}" --entitlements Resources/uvm.entitlements "$app"
codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
