# Snap

A minimal menu bar screenshot app for macOS. Press a shortcut and grab what you need.

| Shortcut | |
|---|---|
| **⌥⌘S** | Freeze the screen, then **drag** to capture an area or **click** a highlighted window |
| **⌥⌘F** | Capture the full screen under the mouse |
| **Esc** | Cancel |

After a capture, a thumbnail appears in the corner. Click it to open the image or drag it into any app.
From the menu bar icon, choose **Clipboard Only** or **Clipboard & Save to Folder** (default `~/Pictures/Screenshots`).

Requires macOS 14 or later. Runs on Apple silicon and Intel.

## Install

Download **Snap.dmg** from [Releases](../../releases/latest) and drag Snap to Applications.

Snap isn't notarized, so macOS blocks it the first time you open it:
1. Open Snap once and dismiss the warning.
2. Go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. Turn on Snap under **Screen & System Audio Recording**, then quit and reopen it.

## Build from source

Requires Xcode 26 or later (for the Icon Composer icon).

```sh
./build.sh           # build/Snap.app
./build.sh run       # build and launch
./build.sh install   # copy to /Applications and launch
./build.sh dmg       # universal build/Snap.dmg
```

Shortcuts live at the top of `Sources/App.swift`. Icon layers are drawn by `swift tools/make-icon.swift`.

## Releases

GitHub Actions builds a DMG on every push. Pushing a `v*` tag publishes a release:

```sh
git tag v1.1.0 && git push origin v1.1.0
```
