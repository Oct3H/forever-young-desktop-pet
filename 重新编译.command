#!/bin/zsh
set -eu
project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
app_dir="$project_dir/青春永驻桌宠.app"
mkdir -p "$app_dir/Contents/Resources/UI"
cp -R "$project_dir/界面/." "$app_dir/Contents/Resources/UI/"
cache_dir="$(mktemp -d "${TMPDIR:-/tmp/}forever-young-swift.XXXXXX")"
trap 'rm -rf -- "$cache_dir"' EXIT
xcrun swiftc -O -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$cache_dir" -framework AppKit -framework AVFoundation -framework WebKit -framework PDFKit -lsqlite3 \
  "$project_dir"/源码/*.swift \
  -o "$app_dir/Contents/MacOS/ForeverYoungDesktop"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
"$app_dir/Contents/MacOS/ForeverYoungDesktop" --self-test
