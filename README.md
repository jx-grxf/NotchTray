<div align="center">

<img src="Docs/icon.png" width="140" alt="NotchTray">

# NotchTray

**Recover the menu bar items your MacBook notch swallowed.**

*When status items overflow into the notch — or get parked off-screen by a menu bar manager — macOS just stops showing them, with no hint they exist. NotchTray finds those hidden items and presents them in a Dynamic Island-style panel that drops down from under the notch. Click an entry to activate the real status item.*

[![Latest release](https://img.shields.io/github/v/release/jx-grxf/NotchTray?label=release&color=2563EB)](https://github.com/jx-grxf/NotchTray/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/jx-grxf/NotchTray/total?color=2563EB&label=downloads)](https://github.com/jx-grxf/NotchTray/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/jx-grxf/NotchTray/ci.yml?branch=main&label=build)](https://github.com/jx-grxf/NotchTray/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/jx-grxf/NotchTray?color=2563EB)](LICENSE)

![Platform](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-000000?logo=apple&logoColor=white)
![Notarized](https://img.shields.io/badge/notarized-Developer%20ID-34C759?logo=apple&logoColor=white)

### [⬇︎ Download the latest release](https://github.com/jx-grxf/NotchTray/releases/latest)

</div>

---

## Install

Download the latest `NotchTray-<version>.dmg` from
[Releases](https://github.com/jx-grxf/NotchTray/releases/latest), open it and
drag NotchTray into Applications. The app is signed with a Developer ID and
notarized by Apple, so it opens without a Gatekeeper warning.

On first launch it asks for **Accessibility** access, which it needs to read
and activate menu bar items. **Screen Recording** is optional and only used to
draw each item's real icon instead of its app icon.

Requires macOS 14 or later on a MacBook with a notch (Apple Silicon).

## Updates

NotchTray updates itself through [Sparkle](https://sparkle-project.org). Two
tracks are available in **Settings → Updates**:

| Channel | What you get |
| --- | --- |
| **Stable** | Released versions only. |
| **Beta** | Prereleases as well — earlier features, rougher edges. |

Both tracks share one feed; beta subscribers also receive stable releases, so
switching back never strands you on a prerelease.

## How it works

- **Notch geometry** comes from `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` — the exact pixel band covered by the hardware notch.
- **Item discovery** uses the Accessibility API. On macOS 26 all status items are rendered by the Control Center process, so the classic `CGWindowListCopyWindowInfo` attribution (owner PID per item window) no longer works. Each app still exposes its items through the `AXExtrasMenuBar` AX attribute with global position and size, which keeps per-app attribution intact.
- An item is **hidden** when its frame intersects the notch band or lies outside the visible right-hand menu bar region.
- **Activation** performs `AXPress` on the item's AX element, which opens its menu even while the item itself is occluded.

## Usage

- Hover the notch with the cursor to expand the island; move away to close it.
- Left-click the NotchTray status icon or press **⌃⌥N** to toggle it manually.
- The island shows hidden items as their real menu bar icons (with Screen Recording permission) and includes a settings gear and a quit switch.
- The status icon shows a count badge while items are hidden.
- Settings: launch at login, hover behavior, auto-close delay, permission status (right-click the status icon → Settings…).
- Requires Accessibility access (System Settings → Privacy & Security → Accessibility). The app prompts on first launch.

## Build & run

Pure SwiftPM — no Xcode project.

```bash
swift build                      # compile
./Scripts/compile_and_run.sh     # package NotchTray.app (ad-hoc signed) + launch
./Scripts/package_app.sh release # package only
```

> **Note:** with ad-hoc signing the code signature changes on every rebuild, so macOS drops the Accessibility grant each time. For iterative development, create a stable self-signed identity and pass it via `APP_IDENTITY`.

## Moving items into the notch

The island's edit mode (pencil) can move items across an invisible separator status item; expanding the separator's length pushes everything left of it off-screen. Moves are performed with a synthetic ⌘-drag — the automated version of the gesture users perform by hand, since macOS has no API for repositioning other apps' items. Two behaviors follow from the mechanism:

- Newly launched apps insert their status items at the far left, i.e. into the hidden section. They show up in the island rather than the bar.
- Restoring an item on a completely full menu bar can only bring it back as far as physics allow; the leftmost item may sit behind the notch, where the island still shows and activates it.

## Limitations (V1)

- Built-in display only; external-display menu bars are not scanned.
- Items are listed, not visually reordered — macOS offers no public API to move other apps' status items (managers like Ice simulate ⌘-drags).
- Menu bar managers that park items off-screen (Ice, Bartender) make those items appear in NotchTray's "hidden" list as well; that is by design.

## Release

```bash
NOTCHTRAY_SIGN_IDENTITY="Developer ID Application: … (TEAMID)" \
  ./Scripts/package_dmg.sh          # build, sign, styled DMG -> dist/

NOTCHTRAY_NOTARY_ENABLED=true \
NOTCHTRAY_NOTARY_KEYCHAIN_PROFILE=notchtray-notary \
  ./Scripts/notarize_release.sh     # notarize + staple
```

Pushing a `v*` tag runs the same pipeline on CI and publishes the release.
See `.github/workflows/release.yml` for the required repository secrets.

## License

MIT — see [LICENSE](LICENSE).
