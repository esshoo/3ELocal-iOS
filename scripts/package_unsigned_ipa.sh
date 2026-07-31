#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/build/DerivedData/Build/Products/Release-iphoneos/3ELocal.app"
OUTPUT_DIR="$ROOT/build/output"
PACKAGE_DIR="$ROOT/build/package"
IPA_PATH="$OUTPUT_DIR/3ELocal-unsigned.ipa"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

rm -rf "$PACKAGE_DIR" "$OUTPUT_DIR"
mkdir -p "$PACKAGE_DIR/Payload" "$OUTPUT_DIR"
cp -R "$APP_PATH" "$PACKAGE_DIR/Payload/3ELocal.app"
rm -rf "$PACKAGE_DIR/Payload/3ELocal.app/_CodeSignature"
rm -f "$PACKAGE_DIR/Payload/3ELocal.app/embedded.mobileprovision"

(
  cd "$PACKAGE_DIR"
  /usr/bin/zip -qry "$IPA_PATH" Payload
)

echo "Created: $IPA_PATH"
/usr/bin/unzip -l "$IPA_PATH" | head -40
