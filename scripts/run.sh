#!/bin/sh
set -e
cd "$(dirname "$0")/.."
config=${1:-debug}
swift build -c "$config"
app=build/Qaqash.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp ".build/$config/Qaqash" "$app/Contents/MacOS/Qaqash"
cp Sources/Qaqash/Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${SIGN:-Apple Development}" "$app" 2>/dev/null || codesign --force --sign - "$app"
pkill -x Qaqash || true
open "$app"
