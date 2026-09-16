#!/bin/sh
# Defaults to a development-signed optimized build. Notarization is explicit.
set -eu
cd "$(dirname "$0")/.."
mode="${1:---development}"
case "$mode" in
  --development) export SIGNING_IDENTITY="${SIGNING_IDENTITY:--}" ;;
  --notarize) : "${SIGNING_IDENTITY:?Set your Developer ID Application identity}"; : "${NOTARY_PROFILE:?Set your stored notarytool Keychain profile}"; [ "$SIGNING_IDENTITY" != '-' ] ;;
  *) printf 'Usage: scripts/package-release.sh --development|--notarize\n' >&2; exit 1 ;;
esac
BUILD_CONFIGURATION=release ./scripts/package-dev.sh
app="$PWD/.build/uVirtualization.app"
if [ "$mode" = '--notarize' ]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements Resources/uvm.entitlements "$app/Contents/MacOS/uvm"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements Resources/uvm.entitlements "$app"
fi
mkdir -p dist
archive="$PWD/dist/uVirtualization-0.1.0-dev-macos-arm64.zip"
# Replace only this generated archive; never package VM storage or credentials.
if [ -f "$archive" ]; then rm "$archive"; fi
ditto -c -k --keepParent "$app" "$archive"
if [ "$mode" = '--notarize' ]; then
  xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  rm "$archive"
  ditto -c -k --keepParent "$app" "$archive"
fi
codesign --verify --deep --strict "$app"
shasum -a 256 "$archive" > "$archive.sha256"
printf '%s\n' "$archive"
