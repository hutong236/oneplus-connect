#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="OnePlusConnect"
BUNDLE_ID="com.hutong.oneplusconnect"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"

case "$MODE" in
  run|--build-only|--logs|--telemetry|--verify|--debug) ;;
  *) echo "usage: $0 [--build-only|--logs|--telemetry|--verify|--debug]" >&2; exit 2 ;;
esac

if [ "$MODE" != "--build-only" ]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build --package-path "$ROOT_DIR/macos" -c release
BIN_DIR="$(swift build --package-path "$ROOT_DIR/macos" -c release --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/macos/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
/usr/bin/codesign --verify --strict "$APP_BUNDLE"

case "$MODE" in
  --build-only) printf 'Built %s\n' "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  *)
    /usr/bin/open -n "$APP_BUNDLE"
    case "$MODE" in
      --logs) /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
      --telemetry) /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
      --verify) sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
    esac
    ;;
esac
