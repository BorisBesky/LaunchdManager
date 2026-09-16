#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="LaunchdManager"
APP_DIR="$APP_NAME.app"
MIN_MACOS="13.0"
MODE="${1:-native}" # native | universal

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

SOURCES=$(find Sources -name '*.swift' | sort)

compile_arch() {
  local arch="$1"
  local out="$2"
  echo "Compiling Swift sources for ${arch}..."
  # shellcheck disable=SC2086
  swiftc -O -swift-version 5 \
    -target "${arch}-apple-macosx${MIN_MACOS}" \
    -o "$out" \
    $SOURCES
}

case "$MODE" in
  native)
    ARCH="$(uname -m)"
    compile_arch "$ARCH" "$APP_DIR/Contents/MacOS/$APP_NAME"
    ;;
  universal)
    TMPDIR_BUILD="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR_BUILD"' EXIT
    compile_arch arm64 "$TMPDIR_BUILD/${APP_NAME}-arm64"
    compile_arch x86_64 "$TMPDIR_BUILD/${APP_NAME}-x86_64"
    echo "Creating universal binary with lipo..."
    lipo -create \
      "$TMPDIR_BUILD/${APP_NAME}-arm64" \
      "$TMPDIR_BUILD/${APP_NAME}-x86_64" \
      -output "$APP_DIR/Contents/MacOS/$APP_NAME"
    lipo -info "$APP_DIR/Contents/MacOS/$APP_NAME"
    ;;
  *)
    echo "Usage: $0 [native|universal]" >&2
    exit 1
    ;;
esac

cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"

echo "Built $APP_DIR ($MODE)"
echo "Run with: open $APP_DIR"
