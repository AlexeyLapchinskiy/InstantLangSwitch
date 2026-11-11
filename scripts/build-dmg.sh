#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
dist="$PWD/dist"
mkdir -p "$dist"

build_options=(-c release --arch arm64 --arch x86_64)
swift build "${build_options[@]}"
bin_path=$(swift build "${build_options[@]}" --show-bin-path)

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
app="$staging/Instant Lang Switch.app"
mkdir -p "$app/Contents/MacOS"
install -m 755 "$bin_path/InstantLangSwitch" "$app/Contents/MacOS/InstantLangSwitch"
install -m 644 Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${CODESIGN_IDENTITY:--}" --options runtime "$app"
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/InstantLangSwitch" -verify_arch arm64
lipo "$app/Contents/MacOS/InstantLangSwitch" -verify_arch x86_64

ln -s /Applications "$staging/Applications"
hdiutil create -ov -format UDZO -volname "Instant Lang Switch" -srcfolder "$staging" \
    "$dist/InstantLangSwitch.dmg"
