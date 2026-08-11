#!/usr/bin/env bash
# assets/appicon.svg から app/macos/AppIcon.icns を再生成する（macOS 標準ツールのみ使用）。
# アイコンのデザインを変えたら本スクリプトを実行して icns をコミットし直す。
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> rasterizing assets/appicon.svg (1024px)"
qlmanage -t -s 1024 -o "$WORK" "$REPO/assets/appicon.svg" >/dev/null
MASTER="$WORK/appicon.svg.png"

echo "==> building iconset"
mkdir "$WORK/AppIcon.iconset"
cp "$MASTER" "$WORK/AppIcon.iconset/icon_512x512@2x.png"
while read -r size name; do
    sips -z "$size" "$size" "$MASTER" --out "$WORK/AppIcon.iconset/$name.png" >/dev/null
done <<'EOF'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
EOF

iconutil -c icns "$WORK/AppIcon.iconset" -o "$REPO/app/macos/AppIcon.icns"
echo "==> done: app/macos/AppIcon.icns"
