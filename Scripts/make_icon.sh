#!/usr/bin/env bash
# Build Icon.icns from Assets/AppIcon.png.
#
# The source is a full-bleed 1024x1024 rounded-square artwork. macOS app icons
# are not full-bleed: the artwork sits on a 1024pt canvas inset to 824pt so it
# lines up with every other icon in the Dock and Finder. This script performs
# that inset and emits the complete iconset.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ICON_SOURCE:-$ROOT/Assets/AppIcon.png}"
OUT="${ICON_OUTPUT:-$ROOT/Icon.icns}"

# Apple's macOS icon grid: 824pt of artwork centred on a 1024pt canvas.
CANVAS=1024
CONTENT=824

[[ -f "$SRC" ]] || { echo "error: $SRC not found" >&2; exit 1; }

WIDTH=$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')
HEIGHT=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
if [[ "$WIDTH" -lt "$CANVAS" || "$HEIGHT" -lt "$CANVAS" ]]; then
  echo "error: source must be at least ${CANVAS}x${CANVAS} (got ${WIDTH}x${HEIGHT})" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BASE="$WORK/base.png"
cp "$SRC" "$BASE"

# Inset: shrink to the content box, then pad back out to the full canvas with
# transparent margins. sips centres the pad, which matches the grid closely
# enough that the icon reads as native.
sips -s format png -z "$CONTENT" "$CONTENT" "$BASE" --out "$BASE" >/dev/null
sips -p "$CANVAS" "$CANVAS" "$BASE" --out "$BASE" >/dev/null

ICONSET="$WORK/Icon.iconset"
mkdir -p "$ICONSET"

emit() {
  local px="$1" name="$2"
  sips -s format png -z "$px" "$px" "$BASE" --out "$ICONSET/$name" >/dev/null
}

emit 16   icon_16x16.png
emit 32   icon_16x16@2x.png
emit 32   icon_32x32.png
emit 64   icon_32x32@2x.png
emit 128  icon_128x128.png
emit 256  icon_128x128@2x.png
emit 256  icon_256x256.png
emit 512  icon_256x256@2x.png
emit 512  icon_512x512.png
emit 1024 icon_512x512@2x.png

iconutil --convert icns --output "$OUT" "$ICONSET"
echo "Created $OUT ($(du -h "$OUT" | cut -f1))"
