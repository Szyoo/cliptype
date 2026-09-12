#!/usr/bin/env bash
# Cliptype.app を組み立てる:
#   Rust エンジン (release) + SwiftUI アプリ + Info.plist → dist/Cliptype.app
# 使い方: scripts/bundle-macos.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO/dist/Cliptype.app"
# APP_VERSION で上書き可能（アップデート機能のテストで古いバージョンを装うため）
VERSION="${APP_VERSION:-$(sed -n 's/^version = "\(.*\)"/\1/p' "$REPO/Cargo.toml" | head -1)}"

# BUILD_UNIVERSAL=1 で arm64 + x86_64 のユニバーサルバイナリを組む（リリース用）
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo "==> building Rust engine (release, universal)"
    rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null 2>&1 || true
    cargo build --release --target aarch64-apple-darwin --manifest-path "$REPO/Cargo.toml"
    cargo build --release --target x86_64-apple-darwin --manifest-path "$REPO/Cargo.toml"
    mkdir -p "$REPO/target/universal"
    lipo -create -output "$REPO/target/universal/cliptype" \
        "$REPO/target/aarch64-apple-darwin/release/cliptype" \
        "$REPO/target/x86_64-apple-darwin/release/cliptype"
    RUST_BIN="$REPO/target/universal/cliptype"
    SWIFT_ARCH_FLAGS="--arch arm64 --arch x86_64"
else
    echo "==> building Rust engine (release)"
    cargo build --release --manifest-path "$REPO/Cargo.toml"
    RUST_BIN="$REPO/target/release/cliptype"
    SWIFT_ARCH_FLAGS=""
fi

echo "==> building SwiftUI app (release)"
# shellcheck disable=SC2086
swift build -c release $SWIFT_ARCH_FLAGS --package-path "$REPO/app/macos"
# shellcheck disable=SC2086
SWIFT_BIN="$(swift build -c release $SWIFT_ARCH_FLAGS --package-path "$REPO/app/macos" --show-bin-path)/CliptypeApp"

echo "==> assembling $APP_DIR (v$VERSION)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$SWIFT_BIN" "$APP_DIR/Contents/MacOS/CliptypeApp"
cp "$RUST_BIN" "$APP_DIR/Contents/MacOS/cliptype"

# SwiftPM のリソースバンドル（ローカライズ文字列など）を同梱する
SWIFT_BIN_DIR="$(dirname "$SWIFT_BIN")"
if [ -d "$SWIFT_BIN_DIR/CliptypeApp_CliptypeApp.bundle" ]; then
    cp -R "$SWIFT_BIN_DIR/CliptypeApp_CliptypeApp.bundle" "$APP_DIR/Contents/Resources/"
fi

# アプリアイコン（scripts/make-icon.sh で assets/appicon.svg から生成）
cp "$REPO/app/macos/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
        <string>ja</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>CliptypeApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

# 署名。
# - 証明書（.p12）があれば一時キーチェーンに取り込んで署名する。署名要件（DR）が
#   「identifier + 証明書」になり、版をまたいでも同じなので、ユーザーのアクセシビリティ
#   許可がアップデート後も維持される。ログインキーチェーンは触らないので GUI の
#   許可ダイアログも出ない。ローカルも CI も同じ経路。
# - 無ければ ad-hoc 署名（毎ビルド署名が変わり、許可は失効する）。
P12="${CODESIGN_P12:-$HOME/.config/cliptype-signing/cliptype-signing.p12}"
P12_PASSWORD="${CODESIGN_P12_PASSWORD:-}"
if [ -z "$P12_PASSWORD" ] && [ -f "$(dirname "$P12")/p12-password.txt" ]; then
    P12_PASSWORD="$(cat "$(dirname "$P12")/p12-password.txt")"
fi
CODESIGN_ID="${CODESIGN_ID:-Cliptype Signing}"

if [ -f "$P12" ] && [ -n "$P12_PASSWORD" ]; then
    KEYCHAIN="$(mktemp -d)/cliptype-signing.keychain-db"
    KC_PASS="$(openssl rand -hex 16)"
    cleanup_keychain() { security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true; }
    trap cleanup_keychain EXIT
    security create-keychain -p "$KC_PASS" "$KEYCHAIN"
    security set-keychain-settings -lut 600 "$KEYCHAIN"
    security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
    security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null
    # 自己署名証明書はタイムスタンプサーバを使えないので --timestamp=none
    codesign --force --deep --sign "$CODESIGN_ID" --keychain "$KEYCHAIN" --timestamp=none "$APP_DIR"
    echo "==> signed with identity: $CODESIGN_ID"
    codesign -d -r- "$APP_DIR" 2>&1 | grep '^designated' || true
else
    codesign --force --deep --sign - "$APP_DIR"
    echo "note: ad-hoc signed (no certificate at $P12). Every rebuild changes the"
    echo "      signature, so macOS treats it as a new app and the Accessibility grant"
    echo "      stops applying. See AGENTS.md → 签名 for the certificate setup."
fi

echo "==> done: $APP_DIR"
