#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:-/project}"
APK_OUTPUT="${2:-/apk}"
LIBS_DIR="$PROJECT_DIR/V2rayNG/app/libs"

cd "$PROJECT_DIR"

NDK_VERSION=$(basename "$NDK_HOME")

mkdir -p "$LIBS_DIR"

# ── 1. libv2ray.aar ─────────────────────────────────────────────────
if [ -f "$LIBS_DIR/libv2ray.aar" ]; then
    echo "==> libv2ray.aar already exists, skipping build"
else
    echo "==> Building libv2ray.aar from AndroidLibXrayLite"
    cd AndroidLibXrayLite

    echo "    Downloading geo assets..."
    mkdir -p assets data
    bash gen_assets.sh download
    cp -v data/*.dat assets/

    echo "    Running go mod tidy..."
    go mod tidy -v

    echo "    Running gomobile bind..."
    gomobile bind -v -androidapi 24 -trimpath -ldflags='-s -w -buildid=' ./

    cp -v libv2ray.aar "$LIBS_DIR/"
    cd "$PROJECT_DIR"
fi

# ── 2. hev-socks5-tunnel ────────────────────────────────────────────
if ls "$LIBS_DIR"/*/libhev-socks5-tunnel.so 1>/dev/null 2>&1; then
    echo "==> libhev-socks5-tunnel already exists, skipping build"
else
    echo "==> Building hev-socks5-tunnel"
    bash compile-hevtun.sh
    cp -r libs/* "$LIBS_DIR/"
fi

# ── 3. Inject ndkVersion ────────────────────────────────────────────
echo "==> Injecting ndkVersion ($NDK_VERSION) into build.gradle.kts"
if ! grep -q 'ndkVersion' V2rayNG/app/build.gradle.kts; then
    sed -i '10i\    ndkVersion = "'"${NDK_VERSION}"'"' V2rayNG/app/build.gradle.kts
fi

# ── 4. Gradle build ─────────────────────────────────────────────────
echo "==> Running Gradle build"
cd V2rayNG
echo "sdk.dir=${ANDROID_HOME}" > local.properties
chmod 755 gradlew

# Remove stale lock files left by previous runs on the mounted volume
find . -path '*/.gradle/*.lock' -delete 2>/dev/null || true
find . -path '*/.gradle/*/gc.properties' -delete 2>/dev/null || true

# Use project-local build dir inside container (not on the slow mounted volume)
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/root/.gradle}"
GRADLE_FLAGS="--no-daemon --no-watch-fs --project-cache-dir=/tmp/gradle-cache"
export GRADLE_OPTS="-Xmx4g -Dfile.encoding=UTF-8"
./gradlew $GRADLE_FLAGS licenseFdroidReleaseReport assembleRelease

# ── 5. Collect APKs ─────────────────────────────────────────────────
echo "==> Collecting APKs"
mkdir -p "$APK_OUTPUT"
find app/build/outputs/apk -name '*.apk' -exec cp {} "$APK_OUTPUT/" \;

echo "==> Done. APKs:"
ls -lh "$APK_OUTPUT"
