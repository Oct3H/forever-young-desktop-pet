#!/bin/zsh
set -eu
project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
app_dir="$project_dir/Forever Young.app"
mkdir -p "$app_dir/Contents/Resources/UI"
cp -R "$project_dir/界面/." "$app_dir/Contents/Resources/UI/"
cache_dir="$(mktemp -d "${TMPDIR:-/tmp/}forever-young-swift.XXXXXX")"
trap 'rm -rf -- "$cache_dir"' EXIT
xcrun swiftc -O -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$cache_dir" -framework AppKit -framework AVFoundation -framework WebKit -framework PDFKit -lsqlite3 \
  "$project_dir"/源码/*.swift \
  -o "$app_dir/Contents/MacOS/ForeverYoungDesktop"
mkdir -p "$app_dir/Contents/Resources/Bridges"
cp "$project_dir/联动插件/forever-young-vscode-3.8.0.vsix" "$project_dir/联动插件/forever-young-pycharm-3.8.0.zip" "$app_dir/Contents/Resources/Bridges/"
xcrun swiftc -O -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$cache_dir" -framework AppKit "$project_dir/源码/版本切换/main.swift" -o "$app_dir/Contents/MacOS/VersionSwitch"
codesign --force --sign - "$app_dir/Contents/MacOS/VersionSwitch"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
"$app_dir/Contents/MacOS/ForeverYoungDesktop" --self-test
