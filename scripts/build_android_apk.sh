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

DEFAULT_KS="${ROOT}/signing/madiun_godot_release.keystore"
if [[ ! -f "${DEFAULT_KS}" && -f "${HOME}/.gemini/signing/madiun_godot_release.keystore" ]]; then
  DEFAULT_KS="${HOME}/.gemini/signing/madiun_godot_release.keystore"
fi
KEYSTORE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-${DEFAULT_KS}}"
KEYSTORE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-madiunrelease}"
KEYSTORE_PASS="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-madiunandroid2026}"
EXPECTED_CERT_SERIAL="${EXPECTED_CERT_SERIAL:-5071a11bb51cc4dc}"
EXPECTED_CERT_SHA256="${EXPECTED_CERT_SHA256:-7bae8ba2a722a2168c38f3faaf0a3d61df57b32700cefdf2041fd59fbf4981ce}"

if [[ ! -f "${KEYSTORE_PATH}" ]]; then
  echo "ERROR: Release keystore not found at ${KEYSTORE_PATH}!" >&2
  echo "Refusing to generate a random certificate so Android APK in-place updates remain compatible." >&2
  exit 1
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

echo "==> [5/5] Applying full cryptographic signatures & verifying certificate continuity..."
apksigner sign \
  --min-sdk-version 21 \
  --ks "${KEYSTORE_PATH}" \
  --ks-key-alias "${KEYSTORE_USER}" \
  --ks-pass "pass:${KEYSTORE_PASS}" \
  --key-pass "pass:${KEYSTORE_PASS}" \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  "${OUT_APK}"

CERT_INFO="$(apksigner verify --verbose --print-certs "${OUT_APK}")"
echo "${CERT_INFO}" | head -n 20

ACTUAL_SHA256="$(echo "${CERT_INFO}" | awk '/Signer #1 certificate SHA-256 digest:/ {print $NF}')"
ACTUAL_SERIAL="$(keytool -list -v -keystore "${KEYSTORE_PATH}" -alias "${KEYSTORE_USER}" -storepass "${KEYSTORE_PASS}" | awk '/Serial number:/ {print $NF}')"

if [[ "${ACTUAL_SHA256}" != "${EXPECTED_CERT_SHA256}" || "${ACTUAL_SERIAL}" != "${EXPECTED_CERT_SERIAL}" ]]; then
  echo "ERROR: Certificate mismatch! Expected serial=${EXPECTED_CERT_SERIAL} sha256=${EXPECTED_CERT_SHA256}, got serial=${ACTUAL_SERIAL} sha256=${ACTUAL_SHA256}" >&2
  exit 1
fi

ls -lh "${OUT_APK}"
echo "==> SUCCESS: Signed Godot Android APK ready at ${OUT_APK} (Cert Serial: ${ACTUAL_SERIAL}, Cert SHA-256: ${ACTUAL_SHA256})"
