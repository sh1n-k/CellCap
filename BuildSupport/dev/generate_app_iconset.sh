#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ASSET_CATALOG_DIR="$ROOT_DIR/Sources/AppUI/Assets.xcassets"
APP_ICONSET_DIR="$ASSET_CATALOG_DIR/AppIcon.appiconset"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /absolute/path/to/cellcap-icon.png" >&2
  exit 64
fi

SOURCE_PNG="$1"

if [[ ! -f "$SOURCE_PNG" ]]; then
  echo "error: source image not found: $SOURCE_PNG" >&2
  exit 66
fi

if [[ "${SOURCE_PNG:e:l}" != "png" ]]; then
  echo "error: source image must be a PNG file." >&2
  exit 65
fi

read -r PIXEL_WIDTH PIXEL_HEIGHT < <(
  sips -g pixelWidth -g pixelHeight "$SOURCE_PNG" 2>/dev/null \
    | awk '/pixelWidth:/ { width = $2 } /pixelHeight:/ { height = $2 } END { print width, height }'
)

if [[ -z "${PIXEL_WIDTH:-}" || -z "${PIXEL_HEIGHT:-}" ]]; then
  echo "error: failed to read PNG dimensions from $SOURCE_PNG" >&2
  exit 65
fi

if [[ "$PIXEL_WIDTH" != "$PIXEL_HEIGHT" ]]; then
  echo "error: source image must be square. got ${PIXEL_WIDTH}x${PIXEL_HEIGHT}" >&2
  exit 65
fi

if (( PIXEL_WIDTH < 1024 )); then
  echo "error: source image must be at least 1024x1024. got ${PIXEL_WIDTH}x${PIXEL_HEIGHT}" >&2
  exit 65
fi

mkdir -p "$APP_ICONSET_DIR"

typeset -A ICON_SIZE_BY_FILE=(
  [icon_16x16.png]=16
  [icon_16x16@2x.png]=32
  [icon_32x32.png]=32
  [icon_32x32@2x.png]=64
  [icon_128x128.png]=128
  [icon_128x128@2x.png]=256
  [icon_256x256.png]=256
  [icon_256x256@2x.png]=512
  [icon_512x512.png]=512
  [icon_512x512@2x.png]=1024
)

for icon_file icon_size in ${(kv)ICON_SIZE_BY_FILE}; do
  sips -s format png -z "$icon_size" "$icon_size" "$SOURCE_PNG" --out "$APP_ICONSET_DIR/$icon_file" >/dev/null
done

cat <<EOF
Generated AppIcon.appiconset images from:
  $SOURCE_PNG

Output directory:
  $APP_ICONSET_DIR

Next step:
  add Sources/AppUI/Assets.xcassets to the AppUI target resources in Xcode if it is not already linked
EOF
