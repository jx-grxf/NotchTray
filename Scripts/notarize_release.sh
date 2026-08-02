#!/usr/bin/env bash
# Submit dist/NotchTray-<version>.dmg for Apple notarization and staple the
# ticket, so Gatekeeper opens it without the "unidentified developer" prompt.
#
# Auth methods, in order of precedence:
#   1. NOTCHTRAY_NOTARY_KEYCHAIN_PROFILE   local: profile created with
#      `xcrun notarytool store-credentials`
#   2. App Store Connect API key — preferred on CI (independent of the Apple
#      ID's password and 2FA):
#        NOTCHTRAY_NOTARY_KEY_ID           key ID, e.g. ABC123DEF4
#        NOTCHTRAY_NOTARY_ISSUER_ID        issuer UUID
#        NOTCHTRAY_NOTARY_KEY_PATH         path to the .p8 (local), or
#        NOTCHTRAY_NOTARY_KEY_P8_BASE64    base64 .p8 contents (CI secret)
#   3. Apple ID + app-specific password:
#        NOTCHTRAY_NOTARY_APPLE_ID / NOTCHTRAY_NOTARY_TEAM_ID /
#        NOTCHTRAY_NOTARY_PASSWORD
#
# Set NOTCHTRAY_NOTARY_ENABLED=true to run. Anything else is a no-op, so a
# build without the secrets produces an (unnotarized) artifact instead of
# failing the pipeline.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME=${APP_NAME:-NotchTray}
source "$ROOT/version.env"
VERSION="${MARKETING_VERSION}"

if [[ "${NOTCHTRAY_NOTARY_ENABLED:-}" != "true" ]]; then
  echo "Notarization skipped (NOTCHTRAY_NOTARY_ENABLED != true)"
  exit 0
fi

DMG="dist/${APP_NAME}-${VERSION}.dmg"
[[ -f "$DMG" ]] || { echo "error: $DMG not found — run Scripts/package_dmg.sh first" >&2; exit 1; }

echo "==> Submitting $DMG for notarization"

if [[ -n "${NOTCHTRAY_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTCHTRAY_NOTARY_KEYCHAIN_PROFILE" \
    --wait
elif [[ -n "${NOTCHTRAY_NOTARY_KEY_PATH:-}" || -n "${NOTCHTRAY_NOTARY_KEY_P8_BASE64:-}" ]]; then
  : "${NOTCHTRAY_NOTARY_KEY_ID:?required with API-key auth}"
  : "${NOTCHTRAY_NOTARY_ISSUER_ID:?required with API-key auth}"
  KEY_PATH="${NOTCHTRAY_NOTARY_KEY_PATH:-}"
  if [[ -z "$KEY_PATH" ]]; then
    KEY_DIR="$(mktemp -d)"
    KEY_PATH="$KEY_DIR/AuthKey_${NOTCHTRAY_NOTARY_KEY_ID}.p8"
    printf '%s' "$NOTCHTRAY_NOTARY_KEY_P8_BASE64" | base64 --decode > "$KEY_PATH"
    trap 'rm -rf "$KEY_DIR"' EXIT
  fi
  xcrun notarytool submit "$DMG" \
    --key "$KEY_PATH" \
    --key-id "$NOTCHTRAY_NOTARY_KEY_ID" \
    --issuer "$NOTCHTRAY_NOTARY_ISSUER_ID" \
    --wait
else
  : "${NOTCHTRAY_NOTARY_APPLE_ID:?required}"
  : "${NOTCHTRAY_NOTARY_TEAM_ID:?required}"
  : "${NOTCHTRAY_NOTARY_PASSWORD:?required}"
  xcrun notarytool submit "$DMG" \
    --apple-id "$NOTCHTRAY_NOTARY_APPLE_ID" \
    --team-id "$NOTCHTRAY_NOTARY_TEAM_ID" \
    --password "$NOTCHTRAY_NOTARY_PASSWORD" \
    --wait
fi

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# Staple the loose app copy as well. The notary service ticketed its cdhash as
# part of the DMG submission, but the ticket only travels inside the image —
# without this, dist/NotchTray.app stays unstapled and fails offline Gatekeeper.
xcrun stapler staple "dist/${APP_NAME}.app"
xcrun stapler validate "dist/${APP_NAME}.app"

echo "==> Gatekeeper assessment"
codesign --verify --deep --strict "dist/${APP_NAME}.app"
spctl --assess --type execute -vv "dist/${APP_NAME}.app"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

echo "Notarized and stapled $DMG"
