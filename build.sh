#!/usr/bin/env bash
# Builds build/Snap.app.   ./build.sh         build
#                          ./build.sh run     build and launch
#                          ./build.sh install build and copy to /Applications
#                          ./build.sh dmg     universal build -> build/Snap.dmg for sharing
set -euo pipefail
cd "$(dirname "$0")"

# Fall back to the Command Line Tools if Xcode's license hasn't been accepted.
if ! xcrun --find swiftc >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

MODE="${1:-}"
APP=build/Snap.app
SDK=$(xcrun --sdk macosx --show-sdk-path)
ARCHS=$(uname -m)
[[ "$MODE" == dmg ]] && ARCHS="arm64 x86_64"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SLICES=()
for arch in $ARCHS; do
    xcrun swiftc -O -swift-version 5 -parse-as-library \
        -target "$arch-apple-macos14.0" -sdk "$SDK" \
        Sources/*.swift -o "build/Snap-$arch"
    SLICES+=("build/Snap-$arch")
done
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/Snap"
rm -f "${SLICES[@]}"

cp Resources/Info.plist "$APP/Contents/Info.plist"
# CI sets these from the git tag / run number.
[[ -n "${SNAP_VERSION:-}" ]] && plutil -replace CFBundleShortVersionString -string "$SNAP_VERSION" "$APP/Contents/Info.plist"
[[ -n "${SNAP_BUILD:-}" ]] && plutil -replace CFBundleVersion -string "$SNAP_BUILD" "$APP/Contents/Info.plist"

# App icon: Resources/Snap.icon -> Assets.car (Liquid Glass) + Snap.icns (older macOS).
# Redraw the layers with:  swift tools/make-icon.swift
xcrun actool Resources/Snap.icon --compile "$APP/Contents/Resources" \
    --app-icon Snap --include-all-app-icons --enable-on-demand-resources NO \
    --output-partial-info-plist build/icon-partial.plist \
    --development-region en --target-device mac --platform macosx \
    --minimum-deployment-target 14.0 --errors --warnings >/dev/null

# Sign with the self-signed "spidy" certificate when it's in the keychain.
# A stable certificate keeps the Screen Recording permission across rebuilds
# and updates. Without it, fall back to ad-hoc signing.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"spidy"/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "Built $APP ($ARCHS)"

case "$MODE" in
    run)
        pkill -x Snap 2>/dev/null || true
        open "$APP"
        ;;
    install)
        pkill -x Snap 2>/dev/null || true
        rm -rf /Applications/Snap.app
        cp -R "$APP" /Applications/
        open /Applications/Snap.app
        echo "Installed to /Applications/Snap.app"
        ;;
    dmg)
        STAGE=build/dmg
        rm -rf "$STAGE" build/Snap.dmg
        mkdir -p "$STAGE"
        cp -R "$APP" "$STAGE/"
        ln -s /Applications "$STAGE/Applications"
        cp Resources/DMG-ReadMe.txt "$STAGE/Read Me.txt"
        hdiutil create -volname Snap -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/Snap.dmg >/dev/null 2>&1
        rm -rf "$STAGE"
        codesign --force --sign "${IDENTITY:--}" build/Snap.dmg
        echo "Created build/Snap.dmg"
        ;;
esac
