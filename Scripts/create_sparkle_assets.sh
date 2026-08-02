#!/usr/bin/env bash
# Build the Sparkle update archive and add it to appcast.xml.
#
# One feed carries both tracks. Prerelease builds get a <sparkle:channel>beta
# element, which stable subscribers never see; beta subscribers get both,
# because Sparkle always includes the default channel alongside the ones the
# app opts into.
#
# Inputs (env):
#   NOTCHTRAY_UPDATE_CHANNEL       stable (default) or beta
#   NOTCHTRAY_SPARKLE_PRIVATE_KEY  EdDSA private key. When unset the key is
#                                  read from the login keychain instead, which
#                                  is what a local run normally wants.
#   NOTCHTRAY_DOWNLOAD_PREFIX      base URL the archive will be served from
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME=${APP_NAME:-NotchTray}
source "$ROOT/version.env"
VERSION="${MARKETING_VERSION}"
BUILD="${BUILD_NUMBER}"
CHANNEL="${NOTCHTRAY_UPDATE_CHANNEL:-stable}"

case "$CHANNEL" in
  stable|beta) ;;
  *) echo "error: channel must be stable or beta (got '$CHANNEL')" >&2; exit 2 ;;
esac

DOWNLOAD_PREFIX="${NOTCHTRAY_DOWNLOAD_PREFIX:-https://github.com/jx-grxf/NotchTray/releases/download/v${VERSION}}"

APP="dist/${APP_NAME}.app"
[[ -d "$APP" ]] || { echo "error: $APP not found — run Scripts/package_dmg.sh first" >&2; exit 1; }

mkdir -p dist/sparkle
ZIP="dist/sparkle/${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP"
# ditto rather than zip: it preserves the bundle's symlinks and resource forks,
# without which the archive fails signature validation after extraction.
(cd dist && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "sparkle/${APP_NAME}-${VERSION}.zip")

SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update 2>/dev/null | grep -v old_dsa | head -1 || true)"
[[ -n "$SIGN_UPDATE" ]] || { echo "error: Sparkle sign_update not found — run swift build first" >&2; exit 1; }

if [[ -n "${NOTCHTRAY_SPARKLE_PRIVATE_KEY:-}" ]]; then
  KEY_FILE="$(mktemp)"
  trap 'rm -f "$KEY_FILE"' EXIT
  printf '%s' "$NOTCHTRAY_SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  SIGNATURE_LINE="$("$SIGN_UPDATE" "$ZIP" -f "$KEY_FILE")"
else
  # Falls back to the key stored in the login keychain by generate_keys.
  SIGNATURE_LINE="$("$SIGN_UPDATE" "$ZIP" --account NotchTraySparkle)"
fi

ED_SIGNATURE="$(printf '%s' "$SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
[[ -n "$ED_SIGNATURE" ]] || { echo "error: no EdDSA signature produced" >&2; exit 1; }

LENGTH="$(stat -f%z "$ZIP")"
NOTES_FILE="release-notes/${VERSION}.md"

CHANNEL="$CHANNEL" VERSION="$VERSION" BUILD="$BUILD" \
LENGTH="$LENGTH" ED_SIGNATURE="$ED_SIGNATURE" \
DOWNLOAD_URL="${DOWNLOAD_PREFIX%/}/${APP_NAME}-${VERSION}.zip" \
NOTES_FILE="$NOTES_FILE" APP_NAME="$APP_NAME" \
/usr/bin/python3 "$ROOT/Scripts/update_appcast.py"

echo "Wrote $ZIP"
echo "Updated appcast.xml (${CHANNEL} channel, ${VERSION})"
