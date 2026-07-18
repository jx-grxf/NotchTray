# NotchTray

A menu bar utility for MacBooks with a notch. When status items overflow into
the notch area (or are parked off-screen by a menu bar manager), macOS simply
stops showing them — with no indication they exist. NotchTray finds those
hidden items and presents them in a Dynamic Island-style panel that drops down
from under the notch. Clicking an entry activates the real status item.

## How it works

- **Notch geometry** comes from `NSScreen.auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea` — the exact pixel band covered by the hardware notch.
- **Item discovery** uses the Accessibility API. On macOS 26 all status items
  are rendered by the Control Center process, so the classic
  `CGWindowListCopyWindowInfo` attribution (owner PID per item window) no
  longer works. Each app still exposes its items through the
  `AXExtrasMenuBar` AX attribute with global position and size, which keeps
  per-app attribution intact.
- An item is **hidden** when its frame intersects the notch band or lies
  outside the visible right-hand menu bar region.
- **Activation** performs `AXPress` on the item's AX element, which opens its
  menu even while the item itself is occluded.

## Usage

- Hover the notch with the cursor to expand the island; move away to close it.
- Left-click the NotchTray status icon or press **⌃⌥N** to toggle it manually.
- The island shows hidden items as their real menu bar icons (with Screen
  Recording permission) and includes a settings gear and a quit switch.
- The status icon shows a count badge while items are hidden.
- Settings: launch at login, hover behavior, auto-close delay, permission
  status (right-click the status icon → Settings…).
- Requires Accessibility access (System Settings → Privacy & Security →
  Accessibility). The app prompts on first launch.

## Build & run

Pure SwiftPM — no Xcode project.

```bash
swift build                      # compile
./Scripts/compile_and_run.sh     # package NotchTray.app (ad-hoc signed) + launch
./Scripts/package_app.sh release # package only
```

Note: with ad-hoc signing the code signature changes on every rebuild, so
macOS drops the Accessibility grant each time. For iterative development,
create a stable self-signed identity and pass it via `APP_IDENTITY`.

## Limitations (V1)

- Built-in display only; external-display menu bars are not scanned.
- Items are listed, not visually reordered — macOS offers no public API to
  move other apps' status items (managers like Ice simulate ⌘-drags).
- Menu bar managers that park items off-screen (Ice, Bartender) make those
  items appear in NotchTray's "hidden" list as well; that is by design.
