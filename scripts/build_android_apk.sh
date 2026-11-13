#!/usr/bin/env bash
set -euo pipefail

# Reproducible Godot 4.7.2 Android APK build script for Incremental Traffic: Karesidenan Madiun

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_APK="${ROOT}/releases/incremental-traffic-madiun-android.apk"

export JAVA_HOME="${JAVA_HOME:-/home/antigravity/.local/share/rea/jdk-21}"
export ANDROID_HOME="${ANDROID_HOME:-/tmp/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
export PATH="${JAVA_HOME}/bin:${ANDROID_HOME}/build-tools/34.0.0:${ANDROID_HOME}/cmdline-tools/latest/bin:${PATH}"

GODOT_BIN="${GODOT_BIN:-/tmp/godot472/Godot_v4.7.2-stable_linux.x86_64}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [[ ! -x "$GODOT_BIN" ]]; then
  GODOT_BIN="$(command -v godot)"
fi

echo "==> [1/5] Building Karesidenan Madiun WGS84 map bundle..."
python3 "${ROOT}/scripts/build_madiun_geodata.py"

KEYSTORE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-/tmp/madiun_godot_release.keystore}"
KEYSTORE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-madiunrelease}"
KEYSTORE_PASS="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-madiunandroid2026}"

if [[ ! -f "${KEYSTORE_PATH}" ]]; then
  echo "==> [2/5] Generating RSA-2048 Android release signing keystore..."
  keytool -genkeypair -v \
    -keystore "${KEYSTORE_PATH}" \
    -alias "${KEYSTORE_USER}" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "${KEYSTORE_PASS}" \
    -keypass "${KEYSTORE_PASS}" \
    -dname "CN=Incremental Traffic Karesidenan Madiun, OU=Mobile Game, O=Madiun Open GIS, L=Madiun, ST=Jawa Timur, C=ID" >/dev/null 2>&1
fi

DBG_KEYSTORE="/tmp/godot_debug.keystore"
if [[ ! -f "${DBG_KEYSTORE}" ]]; then
  keytool -genkeypair -v \
    -keystore "${DBG_KEYSTORE}" \
    -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android -keypass android \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi

echo "==> [3/5] Configuring Godot 4.7 Android SDK & Keystore paths..."
GODOT_CFG_DIR="${HOME}/.config/godot"
mkdir -p "${GODOT_CFG_DIR}" "${ROOT}/releases"

cat > "${GODOT_CFG_DIR}/editor_settings-4.7.tres" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "${JAVA_HOME}"
export/android/android_sdk_path = "${ANDROID_HOME}"
export/android/debug_keystore = "${DBG_KEYSTORE}"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${KEYSTORE_PATH}"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${KEYSTORE_USER}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${KEYSTORE_PASS}"

echo "==> [4/5] Importing project & exporting signed Godot 4.7.2 Android APK..."
"${GODOT_BIN}" --headless --path "${ROOT}" --import
"${GODOT_BIN}" --headless --path "${ROOT}" --export-release "Android" "${OUT_APK}"

echo "==> [5/5] Applying full v1/v2/v3 cryptographic signatures & verifying APK..."
apksigner sign \
  --ks "${KEYSTORE_PATH}" \
  --ks-key-alias "${KEYSTORE_USER}" \
  --ks-pass "pass:${KEYSTORE_PASS}" \
  --key-pass "pass:${KEYSTORE_PASS}" \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  "${OUT_APK}"
apksigner verify --verbose "${OUT_APK}" | head -n 20
ls -lh "${OUT_APK}"
echo "==> SUCCESS: Signed Godot Android APK ready at ${OUT_APK}"
