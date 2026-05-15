#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
MASTER_PNG="$ASSETS_DIR/AppIcon-1024.png"
ICNS_PATH="$ASSETS_DIR/AppIcon.icns"

mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR" "$ICNS_PATH"
mkdir -p "$ICONSET_DIR"

/usr/bin/swift "$ROOT_DIR/script/make_icon.swift" "$MASTER_PNG" >/dev/null

declare -a SIZES=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
  px="${entry%%:*}"
  name="${entry##*:}"
  /usr/bin/sips -z "$px" "$px" "$MASTER_PNG" --out "$ICONSET_DIR/$name" >/dev/null
done

/usr/bin/iconutil --convert icns "$ICONSET_DIR" --output "$ICNS_PATH"

echo "$ICNS_PATH"
