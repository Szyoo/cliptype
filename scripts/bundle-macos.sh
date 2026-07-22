#!/usr/bin/env bash
# Cliptype.app を組み立てる:
#   Rust エンジン (release) + SwiftUI アプリ + Info.plist → dist/Cliptype.app
# 使い方: scripts/bundle-macos.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO/dist/Cliptype.app"
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$REPO/Cargo.toml" | head -1)"

echo "==> building Rust engine (release)"
cargo build --release --manifest-path "$REPO/Cargo.toml"

echo "==> building SwiftUI app (release)"
swift build -c release --package-path "$REPO/app/macos"
SWIFT_BIN="$(swift build -c release --package-path "$REPO/app/macos" --show-bin-path)/CliptypeApp"

echo "==> assembling $APP_DIR (v$VERSION)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$SWIFT_BIN" "$APP_DIR/Contents/MacOS/CliptypeApp"
cp "$REPO/target/release/cliptype" "$APP_DIR/Contents/MacOS/cliptype"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CliptypeApp</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.szyoo.cliptype</string>
    <key>CFBundleName</key>
    <string>Cliptype</string>
    <key>CFBundleDisplayName</key>
    <string>Cliptype</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

# ad-hoc 署名: TCC がアプリを安定して識別できるようにする（配布用の署名は将来課題）
codesign --force --deep --sign - "$APP_DIR"

echo "==> done: $APP_DIR"
