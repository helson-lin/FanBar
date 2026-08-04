#!/bin/zsh
set -euo pipefail

# Convert the 1024-class master artwork into Apple's standard iconset matrix.
source_path="${PWD}/Assets/FanBarIcon-1024.png"
temporary_root="$(mktemp -d)"
trap 'rm -rf "${temporary_root}"' EXIT
iconset_path="${temporary_root}/FanBar.iconset"
normalized_path="${temporary_root}/FanBar-1024.png"
mkdir -p "${iconset_path}"

# Normalize generated RGB artwork to the RGBA PNG format iconutil expects.
magick "${source_path}" -resize 1024x1024! -alpha on "${normalized_path}"
magick "${normalized_path}" -resize 16x16! "${iconset_path}/icon_16x16.png"
magick "${normalized_path}" -resize 32x32! "${iconset_path}/icon_16x16@2x.png"
magick "${normalized_path}" -resize 32x32! "${iconset_path}/icon_32x32.png"
magick "${normalized_path}" -resize 64x64! "${iconset_path}/icon_32x32@2x.png"
magick "${normalized_path}" -resize 128x128! "${iconset_path}/icon_128x128.png"
magick "${normalized_path}" -resize 256x256! "${iconset_path}/icon_128x128@2x.png"
magick "${normalized_path}" -resize 256x256! "${iconset_path}/icon_256x256.png"
magick "${normalized_path}" -resize 512x512! "${iconset_path}/icon_256x256@2x.png"
magick "${normalized_path}" -resize 512x512! "${iconset_path}/icon_512x512.png"
cp "${normalized_path}" "${iconset_path}/icon_512x512@2x.png"

node "${PWD}/scripts/make-icns.mjs" \
    "${iconset_path}" \
    "${PWD}/Assets/FanBar.icns"
print "Built ${PWD}/Assets/FanBar.icns"
