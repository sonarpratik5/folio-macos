#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo 'Usage: scripts/build-app.sh [debug|release]' >&2; exit 1 ;; esac
# Keep all compiler/package caches inside this checkout, including in managed workspaces.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
build_options=()
build_options+=(-Xlinker -dead_strip)
if [[ "${FOLIO_SWIFTPM_UNSANDBOXED:-0}" == 1 ]]; then build_options+=(--disable-sandbox); fi
# Keep source/debug metadata portable; Swift otherwise embeds the builder's home/project paths.
for prefix in "$PWD=/Folio" "$HOME=/build-user"; do
    build_options+=(-Xswiftc -debug-prefix-map -Xswiftc "$prefix" -Xswiftc -file-prefix-map -Xswiftc "$prefix")
done
swift build -c "$configuration" ${build_options[@]+"${build_options[@]}"} --cache-path .build/cache --config-path .build/config --security-path .build/security
bin_path="$(swift build -c "$configuration" ${build_options[@]+"${build_options[@]}"} --cache-path .build/cache --config-path .build/config --security-path .build/security --show-bin-path)"
final_app_path="$PWD/.build/Folio.app"
# Build/sign fresh inodes. Overwriting a previously launched Mach-O in place can
# leave macOS's signature cache referring to the old executable.
package_root="$(mktemp -d "$PWD/.build/package.XXXXXX")"
trap 'rm -rf "$package_root"' EXIT
app_path="$package_root/Folio.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ ! -d Models/Skim/AdaptedMiniLM.mlmodelc && "${FOLIO_SOURCE_ONLY_BUILD:-0}" != 1 ]]; then
    echo "Missing adapted Skim model. See Models/Skim/MODEL.md for the local export command." >&2
    exit 1
fi
cp -R Models/Skim "$app_path/Contents/Resources/Skim"
if [[ ! -d Models/Skim/AdaptedMiniLM.mlmodelc ]]; then
    echo "Source-only bundle: local Skim unavailable; model weights were not supplied." >&2
fi
cp -R "$bin_path/FolioMac_FolioMac.bundle" "$app_path/Contents/Resources/"
cp "$bin_path/FolioMac" "$app_path/Contents/MacOS/FolioMac"
cp "$bin_path/FolioPaperTools" "$app_path/Contents/MacOS/FolioPaperTools"
# Linker debug-map symbols also contain absolute object paths; keep them in build outputs only.
strip -S "$app_path/Contents/MacOS/FolioMac" "$app_path/Contents/MacOS/FolioPaperTools"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
# Configuration is resolved on the recipient's Mac. Never embed dotenv paths or contents.
iconset="$package_root/Folio.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/Icon-512.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/Icon-512.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/Folio.icns"
# Fail closed if packaging reintroduces builder paths or private local data.
python3 - "$app_path" <<'PYPRIVACY'
from pathlib import Path
import re
import sys

bundle = Path(sys.argv[1])
private_names = {".env", "auth.json", "library.json", ".DS_Store"}
patterns = re.compile(rb"/Users/[^/\x00\s]+|/home/[^/\x00\s]+|(?:sk-ant-|sk-proj-|ghp_)[A-Za-z0-9_-]{25,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")
for path in bundle.rglob("*"):
    if not path.is_file():
        continue
    if path.name in private_names or path.suffix in {".pdf", ".ses"} or patterns.search(path.read_bytes()):
        sys.exit(f"Privacy check failed in bundled file: {path.relative_to(bundle)}")
print("Bundle privacy check passed: no home paths, private data files or recognized credential patterns.")
PYPRIVACY
codesign --force --sign - "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
# Keep the last valid bundle until packaging and verification have succeeded.
if [[ -e "$final_app_path" ]]; then mv "$final_app_path" "$package_root/previous.app"; fi
if ! mv "$app_path" "$final_app_path"; then
    if [[ -e "$package_root/previous.app" ]]; then mv "$package_root/previous.app" "$final_app_path"; fi
    exit 1
fi
echo "Built $final_app_path"
echo "Launch: open '$final_app_path'"
