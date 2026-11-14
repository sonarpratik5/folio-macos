#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo 'Usage: scripts/build-app.sh [debug|release]' >&2; exit 1 ;; esac
# Keep all compiler/package caches inside this checkout, including in managed workspaces.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
build_options=()
if [[ "${FOLIO_SWIFTPM_UNSANDBOXED:-0}" == 1 ]]; then build_options+=(--disable-sandbox); fi
swift build -c "$configuration" ${build_options[@]+"${build_options[@]}"} --cache-path .build/cache --config-path .build/config --security-path .build/security
bin_path="$(swift build -c "$configuration" ${build_options[@]+"${build_options[@]}"} --cache-path .build/cache --config-path .build/config --security-path .build/security --show-bin-path)"
app_path="$PWD/.build/Folio.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/FolioMac" "$app_path/Contents/MacOS/FolioMac"
cp "$bin_path/FolioPaperTools" "$app_path/Contents/MacOS/FolioPaperTools"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
iconset="$PWD/.build/Folio.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/Icon-512.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/Icon-512.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/Folio.icns"
codesign --force --sign - "$app_path"
echo "Built $app_path"
echo "Launch: open '$app_path'"
