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
image_dir="$staging/image"
app="$image_dir/Instant Lang Switch.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$bin_path/InstantLangSwitch" "$app/Contents/MacOS/InstantLangSwitch"
install -m 644 Info.plist "$app/Contents/Info.plist"
install -m 644 Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

# Xcode 26 and newer can build the layered icon for modern macOS.
sdk_version=$(xcrun --sdk macosx --show-sdk-version)
if [[ "${sdk_version%%.*}" -ge 26 ]]; then
    icon_build="$staging/icon"
    mkdir -p "$icon_build"
    xcrun --sdk macosx actool Resources/AppIcon.icon --compile "$icon_build" \
        --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon \
        --output-partial-info-plist "$icon_build/Info.plist" \
        --output-format human-readable-text --warnings --errors
    icon_name=$(plutil -extract CFBundleIconName raw -o - "$icon_build/Info.plist")
    install -m 644 "$icon_build/Assets.car" "$app/Contents/Resources/Assets.car"
    plutil -insert CFBundleIconName -string "$icon_name" "$app/Contents/Info.plist"
fi

codesign --force --sign "${CODESIGN_IDENTITY:--}" --options runtime "$app"
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/InstantLangSwitch" -verify_arch arm64
lipo "$app/Contents/MacOS/InstantLangSwitch" -verify_arch x86_64

ln -s /Applications "$image_dir/Applications"
hdiutil create -ov -format UDZO -volname "Instant Lang Switch" -srcfolder "$image_dir" \
    "$dist/InstantLangSwitch.dmg"
