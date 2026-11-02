#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
CONFIGURATION=debug
if [[ "$MODE" == "--package" ]]; then CONFIGURATION=release; fi
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) pkill -x LensCue >/dev/null 2>&1 || true ;;
  --build|--package) ;;
  *) echo "Usage: $0 [--build|--package|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
swift build -c "$CONFIGURATION"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/LensCue.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$(swift build -c "$CONFIGURATION" --show-bin-path)/LensCue" "$APP_BUNDLE/Contents/MacOS/LensCue"
cp "$ROOT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/LensCue.icns" "$APP_BUNDLE/Contents/Resources/LensCue.icns"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
case "$MODE" in
  --build) ;;
  --package)
    case "$(uname -m)" in arm64) ARCH_LABEL=AppleSilicon ;; x86_64) ARCH_LABEL=Intel ;; *) ARCH_LABEL="$(uname -m)" ;; esac
    ARCHIVE="LensCue-macOS-$ARCH_LABEL.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/$ARCHIVE"
    (cd "$DIST_DIR" && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
    echo "Packaged: $DIST_DIR/$ARCHIVE"
    ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/LensCue" ;;
  --logs|--telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "LensCue"' ;;
  --verify) open -n "$APP_BUNDLE"; sleep 1; pgrep -x LensCue ;;
  run) open -n "$APP_BUNDLE" ;;
esac
