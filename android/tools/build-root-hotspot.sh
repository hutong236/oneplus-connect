#!/bin/bash
# 构建 RootHotspotMain → root-hotspot.jar（供 App assets 使用）
# 依赖：JDK 17+、Android SDK（platforms/android-34、build-tools/34.0.0）
set -euo pipefail
cd "$(dirname "$0")"

SDK="${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}"
PLATFORM="$SDK/platforms/android-34/android.jar"
D8="$SDK/build-tools/34.0.0/d8"
OUT_JAR="root-hotspot.jar"
OUT_DIR="../app/src/main/assets"

rm -rf build
mkdir -p build "$OUT_DIR"

javac -source 17 -target 17 -cp "$PLATFORM" -d build RootHotspotMain.java
"$D8" --release --min-api 30 --lib "$PLATFORM" build/*.class --output build
jar cfM "$OUT_JAR" -C build classes.dex
cp "$OUT_JAR" "$OUT_DIR/$OUT_JAR"
rm -rf build
echo "OK: $OUT_DIR/$OUT_JAR ($(wc -c < "$OUT_DIR/$OUT_JAR") bytes)"
