#!/usr/bin/env bash
# Fetch the LiteRT-LM C API prebuilt for Android.
#
# Why this and not the AAR: litertlm-android ships liblitertlm_jni.so, whose 42
# exports are all JNI. The C API (LiteRT-LM v0.16+) is a separate prebuilt with a
# real C ABI -- 144 litert_lm_* symbols, including the NPU dispatch hook
# litert_lm_engine_settings_set_litert_dispatch_lib_dir. Binding that from Rust
# removes the Kotlin plugin from the app entirely.
#
# Nothing downloaded here is committed; vendor/prebuilt/ is gitignored.
set -euo pipefail

VERSION="${LITERT_C_API_VERSION:-0.1.0}"   # the C API package version
LITERTLM_TAG="${LITERTLM_TAG:-v0.16.0}"    # the LiteRT-LM release that ships it
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vendor/prebuilt/litert-lm"

if [[ -f "$DEST/lib/android_arm64/liblitert-lm.so" ]]; then
  echo "already present: $DEST/lib/android_arm64/liblitert-lm.so"
  exit 0
fi

URL="https://github.com/google-ai-edge/LiteRT-LM/releases/download/${LITERTLM_TAG}/litert_lm_c_api-${VERSION}.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "fetching $URL"
curl -fsSL -o "$TMP/capi.zip" "$URL"

echo "unpacking headers + android_arm64 into $DEST"
# unzip -d wants the directory to exist; it will not create the parent.
mkdir -p "$DEST"
unzip -q "$TMP/capi.zip" "include/*" "lib/android_arm64/*" -d "$DEST"

SO="$DEST/lib/android_arm64/liblitert-lm.so"
[[ -f "$SO" ]] || { echo "FATAL: $SO missing after unpack" >&2; exit 1; }
[[ -f "$DEST/include/engine.h" ]] || { echo "FATAL: engine.h missing" >&2; exit 1; }

# Readelf is enough to prove this is the right artifact before anything tries to
# dlopen it on a phone: wrong architecture here wastes a CI cycle and a device
# trip.
if command -v readelf >/dev/null; then
  if ! readelf -h "$SO" | grep -qiE 'aarch64|ARM64'; then
    echo "FATAL: $SO is not aarch64" >&2
    readelf -h "$SO" | grep -E 'Class|Machine' >&2 || true
    exit 1
  fi
  n=$(nm -D --defined-only "$SO" 2>/dev/null | grep -c ' T litert_lm_' || true)
  echo "ok: $(du -h "$SO" | cut -f1), $n litert_lm_* exports"
  [[ "$n" -gt 100 ]] || { echo "FATAL: expected >100 litert_lm_* exports, got $n" >&2; exit 1; }
fi

cat <<EOF

Next:
  1. bindgen over $DEST/include/{engine,conversation}.h
  2. cargo ndk -t arm64-v8a build --release   (CI only -- see AGENTS.md)
  3. push and run:  mobilelm-bench --probe --litertlm <pushed>/liblitert-lm.so
EOF
