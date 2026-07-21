#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"

cd "$project_dir"
swift build -c "$configuration" --product WattBar

binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$project_dir/dist/WattBar.app"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/WattBar" "$app_dir/Contents/MacOS/WattBar"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
