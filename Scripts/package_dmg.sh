#!/usr/bin/env bash
# Build a Developer ID signed NotchTray.app and package it into a styled DMG.
#
# Inputs (env):
#   NOTCHTRAY_SIGN_IDENTITY   Developer ID Application identity. When unset the
#                             app is ad-hoc signed and the DMG is unsigned —
#                             fine for local smoke tests, not for release.
#   ARCHES                    defaults to arm64 (no Intel Mac has a notch)
#
# Output:
#   dist/NotchTray.app
#   dist/NotchTray-<version>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME=${APP_NAME:-NotchTray}
source "$ROOT/version.env"
VERSION="${MARKETING_VERSION}"

SIGN_IDENTITY="${NOTCHTRAY_SIGN_IDENTITY:-}"

# Every Mac with a notch is Apple Silicon, so a universal binary would only add
# dead weight. Override via ARCHES if that ever stops being true.
export ARCHES="${ARCHES:-arm64}"

echo "==> Building ${APP_NAME} ${VERSION} (${ARCHES})"
if [[ -n "$SIGN_IDENTITY" ]]; then
  APP_IDENTITY="$SIGN_IDENTITY" "$ROOT/Scripts/package_app.sh" release
else
  echo "warning: NOTCHTRAY_SIGN_IDENTITY unset — ad-hoc signing, not distributable" >&2
  SIGNING_MODE=adhoc "$ROOT/Scripts/package_app.sh" release
fi

mkdir -p dist
rm -rf "dist/${APP_NAME}.app"
cp -R "$ROOT/${APP_NAME}.app" "dist/${APP_NAME}.app"

codesign --verify --deep --strict "dist/${APP_NAME}.app"

DMG="dist/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG"

STAGE="$(mktemp -d)"
BG_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$BG_DIR"' EXIT

BACKGROUND="$BG_DIR/background.png"
swift "$ROOT/Scripts/make_dmg_background.swift" "$BACKGROUND" >/dev/null

# Two unrelated tools are named "create-dmg": the Homebrew formula
# create-dmg/create-dmg (bash, supports --volname and --background for a styled
# layout) and the npm sindresorhus/create-dmg. Only the former can place the
# custom background, so prefer it and fall back progressively.
CREATE_DMG_BIN=""
for candidate in \
  "/opt/homebrew/opt/create-dmg/bin/create-dmg" \
  "/usr/local/opt/create-dmg/bin/create-dmg" \
  "/opt/homebrew/bin/create-dmg" \
  "/usr/local/bin/create-dmg" \
  "$(command -v create-dmg 2>/dev/null || true)"; do
  [[ -z "$candidate" || ! -x "$candidate" ]] && continue
  if "$candidate" --help 2>&1 | grep -q -- "--volname"; then
    CREATE_DMG_BIN="$candidate"
    break
  fi
done

build_plain_dmg() {
  # GUI-free fallback: a valid drag-install image that never depends on
  # Finder/AppleScript, at the cost of the styled window.
  echo "note: building a plain DMG via hdiutil" >&2
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "dist/${APP_NAME}.app" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
}

if [[ -n "$CREATE_DMG_BIN" ]]; then
  cp -R "dist/${APP_NAME}.app" "$STAGE/"
  # Icon coordinates are window-relative centres and line up with the ring
  # motif rendered into the background at y=232.
  if ! "$CREATE_DMG_BIN" \
      --volname "${APP_NAME} ${VERSION}" \
      --background "$BACKGROUND" \
      --window-pos 200 120 \
      --window-size 660 400 \
      --icon-size 128 \
      --text-size 13 \
      --icon "${APP_NAME}.app" 175 232 \
      --app-drop-link 485 232 \
      --no-internet-enable \
      "$DMG" \
      "$STAGE" >/dev/null; then
    echo "warning: styled create-dmg failed — falling back to a plain DMG" >&2
    rm -f "$DMG"
    build_plain_dmg
  fi
else
  echo "warning: create-dmg not installed (brew install create-dmg)" >&2
  build_plain_dmg
fi

[[ -f "$DMG" ]] || { echo "error: DMG was not produced at $DMG" >&2; exit 1; }

if [[ -n "$SIGN_IDENTITY" ]]; then
  # Sign the container too: notarize_release.sh assesses the DMG's primary
  # signature via spctl, which an unsigned image would fail.
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  codesign --verify --strict "$DMG"
fi

hdiutil imageinfo "$DMG" >/dev/null
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
