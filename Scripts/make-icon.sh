#!/bin/zsh

# Builds Resources/AppIcon.icns from the 1024x1024 master Resources/AppIcon.png.
set -euo pipefail

project_dir="${0:A:h:h}"
master_png="$project_dir/Resources/AppIcon.png"
output_icns="$project_dir/Resources/AppIcon.icns"

[[ -f "$master_png" ]] || { print -u2 -r -- "missing $master_png"; exit 1; }

iconset_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/wattbar-icon.XXXXXX")/AppIcon.iconset"
/bin/mkdir -p "$iconset_dir"

for size in 16 32 128 256 512; do
    double=$(( size * 2 ))
    /usr/bin/sips -z "$size" "$size" "$master_png" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    /usr/bin/sips -z "$double" "$double" "$master_png" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done

/usr/bin/iconutil --convert icns "$iconset_dir" --output "$output_icns"
/bin/rm -rf -- "${iconset_dir:h}"
echo "$output_icns"
