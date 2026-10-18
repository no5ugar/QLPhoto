# QLPhoto — Photo previews, EXIF, and histograms in Finder

[简体中文](README.md) · English

A macOS photo preview tool. Select a photo in Finder and press Space to view the image, shooting parameters, and histogram.

Built with Swift, AppKit, SwiftUI, and the system Image I/O framework, with no third-party runtime dependencies. The minimum deployment target is macOS 13.

## Screenshots

### Space preview window

![Space preview window](docs/images/preview-window.png)

### Settings and icon toggles

![Settings window](docs/images/settings.png)

The settings screenshot predates the rename; PhotoPeek is the former name of QLPhoto.

## Features

- Preview of JPG / JPEG, HEIC / HEIF, and DNG; DNG decoding compatibility depends on macOS and the camera model.
- ISO, shutter speed, aperture, focal length, exposure compensation, and 35mm-equivalent focal length, plus camera, lens, capture time, and the raw metadata.
- Exposure histogram, GPS coordinates, and an Apple Maps entry.
- Scroll-wheel zoom, click-and-drag panning, and double-click to fit the window.
- ↑ / ↓ move through the list order exposed by Finder and keep the selection in sync; unsupported items show a message and you can keep navigating.
- HEIC / HEIF are previewed as still photos; Live Photo is temporarily disabled.
- Shooting parameters are read independently and shown as soon as they arrive; skeleton layout, thumbnail-first loading, and direct replacement on completion with no fade-in; stale results never overwrite the current photo.
- Window position and size are remembered per screen; on first open the window is centered in the available area of the Finder screen.
- Menu bar and Dock icons can be toggled independently, and the image background can follow the system or be set to white or black.

## Installation and usage

1. Build it yourself, or use an installer provided by the project publisher, and place `QLPhoto.app` in Applications.
2. Launch QLPhoto and allow it under System Settings → Privacy & Security → Accessibility.
3. Return to the app, click "Enable Space preview", select a supported photo in Finder, and press Space.
4. Press ↑ / ↓ to switch; press Space, Esc, or ⌘W to close. Using Finder's list view is recommended.

The app keeps running after the home window is closed. When both icons are hidden, opening QLPhoto again from Applications brings the home window back. The enabled state and display settings are saved automatically.

Launch at login: add QLPhoto under System Settings → General → Login Items & Extensions → Open at Login; the home window provides a shortcut to that setting. The app launches after the account logs in, and the accessibility permission must be granted separately.

The current build uses a local ad-hoc signature, so the accessibility permission may be lost after an update. Remove the old entry in System Settings, add the app again, and re-enable it. For public binary distribution, signing with a Developer ID and Apple notarization are recommended; the repository does not include signing certificates.

When upgrading from the previous app name, quit the old app first, grant Accessibility permission to QLPhoto, and enable Space preview again. The bundle identifier changed with the rename, so old preferences are not migrated automatically. Update any existing login item to QLPhoto.

## Install with an AI Agent

An AI Agent with local command execution can follow [AGENTS.md](AGENTS.md) and the [installation guide](docs/AGENT_INSTALL.md) to download, build, and install QLPhoto. Give it this prompt together with this repository's URL or local path:

> Read AGENTS.md and docs/AGENT_INSTALL.md in this repository, check my environment, and help me download, build, and install QLPhoto. Tell me when a system permission requires my action.

Requires macOS and full Xcode. You must grant Accessibility permission manually in System Settings.

## Build

Requires macOS, a full Xcode installation, and the matching macOS SDK. The minimum deployment target does not mean the project has been tested on every macOS / Xcode version. The command line must point at full Xcode, and first-run setup must be completed as prompted.

```sh
# From the repository root
bash scripts/build.sh
```

By default this produces `build/DerivedData/Build/Products/Release/QLPhoto.app` with a local ad-hoc signature. You can also open `QLPhoto/QLPhoto.xcodeproj` and select the shared `QLPhoto` scheme.

The Xcode project is committed, so a normal build does not require XcodeGen. When you change targets, the file list, or type declarations, keep `QLPhoto/project.yml` and the generated project in sync; with XcodeGen installed you can run:

```sh
cd QLPhoto
xcodegen generate
```

## Checks

```sh
# Logic checks that need no photos and no accessibility permission
bash scripts/check.sh

# Verify decoding, metadata, and HTML preview with your own photos; files are never uploaded
bash scripts/check.sh /absolute/path/photo.jpg /absolute/path/photo.dng /absolute/path/photo.heic

# Briefly shows test windows on an interactive local desktop; CI does not run this group
bash scripts/check.sh --ui /absolute/path/photo.dng /absolute/path/photo.jpg
```

Passing a `.heic` / `.heif` file also runs the (disabled) Live Photo check; running `--ui` with both a `.dng` and a `.jpg` / `.jpeg` additionally runs the rapid-switch loading check. CI builds an unsigned app on macOS and runs the basic checks. Real Finder key presses, accessibility authorization, and multi-display setups still need manual verification; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Limitations

- The primary approach is an accessibility-driven standalone preview window. The repository keeps an experimental data-based Quick Look extension, but the system is not guaranteed to pick it to handle JPG / HEIC / DNG. The extension is static HTML and does not include all of the main app's interactions.
- The preview is at most 3200 pixels on the long edge, so zooming is not a pixel-level 100% view; the histogram is normalized on a single Rec. 709 luminance channel over a downsampled sRGB preview.
- No RAW color grading, no full HDR / gain-map display, and not every camera RAW format is supported.
- Live Photo is temporarily disabled: neighboring videos are neither scanned nor paired, and the play button and Live Photo state are not shown. HEIC still previews are unaffected.
- Some Finder views, virtual lists, or unreadable items may not be switchable; the app shows a message and never re-sorts by filename. For a multiple selection, only the first recognizable image is opened.
- When a DNG has no embedded thumbnail, the app waits for a full decode; an in-progress system decode cannot be forcibly stopped, and stale results are discarded.

## Privacy

Photo decoding, metadata, and histograms are all handled locally. There is no analytics, automatic upload, or update service. Global key handling is only used for the Finder Space preview and never records keystrokes. Clicking the map link hands the photo's coordinates to the map service. The sidebar lists the file's raw metadata fields verbatim, which may include private details such as GPS, device model, serial number, and capture time; mask them before sharing screenshots. Do not upload original photos containing private GPS / EXIF to public issues. See [Security and Privacy](SECURITY.md).

## Layout

| Path | Contents |
| --- | --- |
| `QLPhoto/App/` | App lifecycle, settings, Finder key handling, and window management |
| `QLPhoto/Sources/` | Decoding, metadata, histogram, image interaction, and HTML preview |
| `QLPhoto/Extension/` | Experimental Quick Look extension |
| `QLPhoto/Checks/` | Standalone Swift check entry points |
| `scripts/` | Build, check, and package scripts |

Issues and improvements are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). This project is released under the [MIT License](LICENSE).
