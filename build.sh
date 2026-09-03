#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LaunchdManager"
APP_DIR="$APP_NAME.app"
ARCH="$(uname -m)"
MIN_MACOS="13.0"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "Compiling Swift sources..."
# shellcheck disable=SC2046
swiftc -O -swift-version 5 \
    -target "${ARCH}-apple-macosx${MIN_MACOS}" \
    -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
    $(find Sources -name '*.swift' | sort)

cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

echo "Built $APP_DIR"
echo "Run with: open $APP_DIR"
