#!/bin/zsh
set -euo pipefail

# Convert the 1024-class master artwork into Apple's standard iconset matrix.
source_path="${PWD}/Assets/FanBarIcon-1024.png"
temporary_root="$(mktemp -d)"
trap 'rm -rf "${temporary_root}"' EXIT
iconset_path="${temporary_root}/FanBar.iconset"
normalized_path="${temporary_root}/FanBar-1024.png"
mkdir -p "${iconset_path}"

# The master is full-bleed with black corners and a dark rim that only macOS 26+
# masks away; cut a transparent rounded shape 4px inside the rim (built at 4x).
mask_path="${temporary_root}/mask.png"
magick "${source_path}" -alpha off -resize 4096x4096! \
    -fuzz 4% -fill '#FF0000' \
    -draw 'color 0,0 floodfill' -draw 'color 4095,0 floodfill' \
    -draw 'color 0,4095 floodfill' -draw 'color 4095,4095 floodfill' +fuzz \
    -fill white +opaque '#FF0000' -fill black -opaque '#FF0000' \
    -colorspace Gray -bordercolor black -border 32 \
    -morphology Erode Disk:16 -shave 32 -resize 1024x1024! "${mask_path}"
cutout_path="${temporary_root}/FanBar-cutout.png"
magick "${source_path}" -resize 1024x1024! -alpha off "${mask_path}" \
    -compose CopyOpacity -composite "${cutout_path}"

# The cutout squircle is full-bleed (edge-to-edge), but Apple's icon grid expects
# the shape inset within a safe area (~824pt of 1024pt, matching the system's own
# app icons) so FanBar doesn't read larger than its neighbors in Finder/Launchpad.
magick -size 1024x1024 xc:none -gravity center \
    \( "${cutout_path}" -resize 824x824 \) -composite -depth 8 "${normalized_path}"
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
