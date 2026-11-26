#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"

cd "$project_dir"
swift build -c "$configuration" --product WattBar

binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$project_dir/dist/WattBar.app"

# Start from an empty bundle so files from older builds never linger.
/bin/rm -rf -- "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/WattBar" "$app_dir/Contents/MacOS/WattBar"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
printf "APPL????" > "$app_dir/Contents/PkgInfo"

codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
