#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# No package dependencies. Compile directly so a full Xcode install is not required.
# Some CLT releases ship mismatched SwiftPM manifest libraries; swiftc avoids that dependency.
ARCH="$(uname -m)"
mkdir -p .build/release
# Some mixed CLT installations contain duplicate SwiftBridging module maps.
# Hide only the legacy duplicate through a process-local VFS overlay; never edit the SDK.
SWIFT_FLAGS=(-swift-version 5)
INCLUDE="$(xcode-select -p)/usr/include/swift"
if [[ -f "$INCLUDE/module.modulemap" && -f "$INCLUDE/bridging.modulemap" ]] && grep -q '^module SwiftBridging' "$INCLUDE/module.modulemap" && grep -q '^module SwiftBridging' "$INCLUDE/bridging.modulemap"; then
    mkdir -p .build/sdk-compat
    printf '// Duplicate legacy module map hidden only for this build.\n' > .build/sdk-compat/empty.modulemap
    python3 - "$INCLUDE/module.modulemap" <<'PY'
import json, os, sys
json.dump({'version': 0, 'roots': [{'type': 'file', 'name': sys.argv[1], 'external-contents': os.path.abspath('.build/sdk-compat/empty.modulemap')}]}, open('.build/sdk-compat/overlay.json', 'w'))
PY
    SWIFT_FLAGS+=(-vfsoverlay "$PWD/.build/sdk-compat/overlay.json")
fi
swiftc "${SWIFT_FLAGS[@]}" -O -parse-as-library -target "$ARCH-apple-macos14.0" Sources/TomMusic/*.swift -o .build/release/TomMusic
APP="$PWD/dist/Tom Music.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TomMusic "$APP/Contents/MacOS/TomMusic"
swiftc "${SWIFT_FLAGS[@]}" scripts/make-icon.swift -o .build/release/make-icon
.build/release/make-icon .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP/Contents/Info.plist" 2>/dev/null || true
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleName': 'Tom Music',
        'CFBundleDisplayName': 'Tom Music',
        'CFBundleExecutable': 'TomMusic',
        'CFBundleIdentifier': 'com.tommusic.desktop',
        'CFBundleVersion': '5',
        'CFBundleShortVersionString': '1.4.0',
        'CFBundlePackageType': 'APPL',
        'CFBundleIconFile': 'AppIcon',
        'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True,
        'NSHumanReadableCopyright': 'Copyright © 2026 Tom Music. Independent local music player.',
        'LSApplicationCategoryType': 'public.app-category.music',
    }, f, sort_keys=True)
PY
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
