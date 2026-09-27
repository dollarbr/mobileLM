#!/usr/bin/env bash
# Run the milestone-0 probe on a connected Android device.
#
# Answers the two questions that decide whether the Rust rewrite is viable, and
# neither needs an APK, a UI or a model:
#
#   1. Does LiteRT-LM's C API .so (android_arm64) load on this phone's Bionic,
#      and do its 144 litert_lm_* symbols resolve? The AAR's JNI wrapper proves
#      nothing about the C API.
#   2. What does the CPU report, and how much RAM is there?
#
# The binary is built in CI (this host cannot link for Android: the NDK's own
# clang and glslc are x86-64 ELF binaries and this machine is aarch64). So the
# artifact is downloaded from the latest successful run.
#
#   scripts/run-on-device.sh            # full run
#   scripts/run-on-device.sh --check    # prerequisites only, no device needed
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-/tmp/opencode/mobilelm-bench}"
BIN="$WORK/mobilelm-bench"
SO_NAME="liblitert-lm.so"
SO="$ROOT/vendor/prebuilt/litert-lm/lib/android_arm64/$SO_NAME"
REMOTE_DIR=/data/local/tmp/mobilelm-rs

die() { echo "error: $*" >&2; exit 1; }

check_prereqs() {
  command -v adb >/dev/null || die "adb not on PATH"
  command -v gh  >/dev/null || die "gh not on PATH"

  if [[ ! -f "$SO" ]]; then
    echo "LiteRT-LM C API not fetched; running scripts/fetch-litert-capi.sh"
    "$ROOT/scripts/fetch-litert-capi.sh" >/dev/null || die "fetch failed"
  fi
  [[ -f "$SO" ]] || die "$SO still missing after fetch"
  local arch exports
  arch="$(readelf -h "$SO" 2>/dev/null | grep -qiE 'aarch64|ARM64' && echo aarch64 || echo "NOT-aarch64")"
  [[ "$arch" == aarch64 ]] || die "$SO is $arch"
  exports="$(nm -D --defined-only "$SO" 2>/dev/null | grep -c ' T litert_lm_' || true)"
  [[ "${exports:-0}" -gt 100 ]] || die "$SO exports only ${exports:-0} litert_lm_* symbols"
  echo "ok: $SO_NAME is aarch64 with $exports litert_lm_* exports"

  if [[ ! -f "$BIN" ]]; then
    echo "probe binary not local; downloading the latest CI artifact"
    mkdir -p "$WORK"
    gh run download --repo dollarbr/mobileLM-rs -n mobilelm-bench-arm64 -D "$WORK" \
      || die "no CI artifact available (push to main, or pass a path via BIN=)"
  fi
  [[ -f "$BIN" ]] || die "$BIN missing"
  readelf -h "$BIN" 2>/dev/null | grep -qiE 'aarch64|ARM64' \
    || die "$BIN is not an aarch64 binary -- stale or wrong artifact"
  echo "ok: probe binary is aarch64 ($(du -h "$BIN" | cut -f1))"

  if [[ "${1:-}" == "--check" ]]; then
    echo
    echo "prerequisites satisfied. Now plug the phone in (or re-enable wireless"
    echo "debugging) and re-run without --check."
    # exit, not return: returning here would only leave this function, and the
    # push below would still run and fail on "no devices".
    exit 0
  fi

  local devices
  devices="$(adb devices | sed -n '2,$p' | awk '$2=="device"{print $1}')"
  [[ -n "$devices" ]] || die "no adb device. Connect USB, or re-enable wireless
  debugging and check 'IP address & port' in Developer options. Note the phone
  is reachable on the LAN (it answers ping) but exposes no adb port right now --
  wireless debugging resets on reboot."
  echo "ok: device $devices"
}

check_prereqs "$@"

echo
echo "pushing to $REMOTE_DIR ($SO_NAME is $(du -h "$SO" | cut -f1), this takes a few seconds)"
adb shell "mkdir -p $REMOTE_DIR"
adb push "$BIN" "$REMOTE_DIR/mobilelm-bench" >/dev/null
adb push "$SO" "$REMOTE_DIR/$SO_NAME" >/dev/null
# adb push does not reliably preserve the exec bit.
adb shell "chmod 755 $REMOTE_DIR/mobilelm-bench"

echo
echo "=== device baseline (CPU + RAM, no library) ==="
adb shell "$REMOTE_DIR/mobilelm-bench --probe"

echo
echo "=== LiteRT-LM C API load test ==="
# Exit 1 here means "the library is not there", which is a finding, not a crash.
adb shell "$REMOTE_DIR/mobilelm-bench --probe --litertlm $REMOTE_DIR/$SO_NAME" || true

echo
cat <<'EOF'
How to read the second block:

  loaded:true   the C API works on this device; bindgen is unblocked and the
                .litertlm catalogue plus the NPU dispatch hook are reachable
  loaded:false  read the "error" field. The two cases that matter:
                  cannot open ... No such file  -> the push did not land
                  ... not accessible ...        -> linker namespace blocked it,
                                                    which is the same wall the
                                                    MediaTek driver hits
EOF
