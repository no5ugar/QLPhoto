#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
configuration="${CONFIGURATION:-Release}"
derived="${DERIVED_DATA_PATH:-$root/build/DerivedData}"
signing=(CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES)
if [[ "${1:-}" == --unsigned ]]; then
    signing=(CODE_SIGNING_ALLOWED=NO)
    shift
fi
if [[ $# -ne 0 ]]; then
    echo 'Usage: bash scripts/build.sh [--unsigned]' >&2
    exit 2
fi
xcodebuild -project "$root/QLPhoto/QLPhoto.xcodeproj" -scheme QLPhoto \
    -configuration "$configuration" -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived" "${signing[@]}" build
echo "Built: $derived/Build/Products/$configuration/QLPhoto.app"
