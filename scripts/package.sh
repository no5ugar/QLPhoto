#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$root/build/DerivedData/Build/Products/Release/QLPhoto.app}"
if [[ ! -d "$app" || ! -f "$app/Contents/Info.plist" ]]; then
    echo 'Build first, or pass the path to a signed QLPhoto.app.' >&2
    exit 2
fi
codesign --verify --deep --strict "$app"
mkdir -p "$root/dist"
ditto -c -k --sequesterRsrc --keepParent "$app" "$root/dist/QLPhoto-Release.zip"
echo "Packaged: $root/dist/QLPhoto-Release.zip"
