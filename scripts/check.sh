#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
ui=false
if [[ "${1:-}" == --ui ]]; then ui=true; shift; fi
for photo in "$@"; do
    if [[ ! -f "$photo" ]]; then echo "File not found: $photo" >&2; exit 2; fi
done

# Print the first argument whose extension is in the comma-separated list $1.
first_with_ext() {
    local exts=",$1," f ext
    shift
    for f in "$@"; do
        ext="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"
        if [[ "$exts" == *",$ext,"* ]]; then printf '%s\n' "$f"; return 0; fi
    done
    return 1
}

temp="$(mktemp -d "${TMPDIR:-/tmp}/qlphoto-check.XXXXXX")"
trap 'rm -rf "$temp"' EXIT
compiler="${SWIFTC:-$(xcrun --find swiftc)}"
sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
flags=(-swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos13.0" -sdk "$sdk" -module-cache-path "$temp/cache")
photoSource="$root/QLPhoto/Sources/Photo.swift"
checks="$root/QLPhoto/Checks"
"$compiler" "${flags[@]}" "$photoSource" "$checks/ShootingInfo.swift" -o "$temp/shooting"
"$temp/shooting"
"$compiler" "${flags[@]}" "$root/QLPhoto/App/FinderSpace.swift" "$checks/Placement.swift" -o "$temp/placement"
"$temp/placement"
"$compiler" "${flags[@]}" "$photoSource" "$checks/Decode.swift" -o "$temp/decode"
"$temp/decode" "$@"
"$compiler" "${flags[@]}" "$photoSource" "$checks/Metadata.swift" -o "$temp/metadata"
"$temp/metadata" "$@"
"$compiler" "${flags[@]}" "$photoSource" "$root/QLPhoto/Sources/HTMLPreview.swift" "$checks/HTMLPreviewCheck.swift" -o "$temp/html"
"$temp/html" "$@"
heic="$(first_with_ext 'heic,heif' "$@" || true)"
if [[ -n "$heic" ]]; then
    "$compiler" "${flags[@]}" "$photoSource" "$checks/LivePhoto.swift" -o "$temp/livephoto"
    "$temp/livephoto" "$heic"
else
    echo "Skip Live Photo check: pass a .heic / .heif file to enable it."
fi
if $ui; then
    sed '/^@main$/d' "$root/QLPhoto/App/App.swift" > "$temp/App.swift"
    for check in Navigation Settings WindowMotion; do
        "$compiler" "${flags[@]}" "$photoSource" "$temp/App.swift" "$root/QLPhoto/App/FinderSpace.swift" "$checks/$check.swift" -o "$temp/$check"
        "$temp/$check"
    done
    dng="$(first_with_ext 'dng' "$@" || true)"
    jpeg="$(first_with_ext 'jpg,jpeg' "$@" || true)"
    if [[ -n "$dng" && -n "$jpeg" ]]; then
        "$compiler" "${flags[@]}" "$photoSource" "$temp/App.swift" "$root/QLPhoto/App/FinderSpace.swift" "$checks/Loading.swift" -o "$temp/loading"
        "$temp/loading" "$dng" "$jpeg"
    else
        echo "Skip rapid-switch loading check: pass both a .dng and a .jpg / .jpeg file to enable it."
    fi
fi
echo 'All requested checks passed.'
