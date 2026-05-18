#!/bin/bash
# Build GPU backend .so files for Android in WSL2 Ubuntu
#
# Prerequisites (run once):
#   sudo apt-get install -y build-essential curl python3
#   mkdir -p ~/tools && cd ~/tools
#   curl -L -o cmake.tar.gz https://github.com/Kitware/CMake/releases/download/v4.0.0/cmake-4.0.0-linux-x86_64.tar.gz
#   tar xzf cmake.tar.gz
#   curl -L -o ninja.zip https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-linux.zip
#   python3 -m zipfile -e ninja.zip .
#   chmod +x ninja
#   curl -L -o ndk.zip https://dl.google.com/android/repository/android-ndk-r27c-linux.zip
#   python3 -m zipfile -e ndk.zip .
#   # Fix broken symlinks in NDK (Python zipfile doesn't preserve them):
#   # Run the fix_ndk_symlinks.py script included in this repo
#
# Usage:
#   cd /mnt/c/.../cross-platform-llm-client
#   bash local_plugins/sd_flutter_android/scripts/build_gpu_backends_wsl.sh

set -e

export PATH="$HOME/tools/cmake-4.0.0-linux-x86_64/bin:$HOME/tools:$PATH"
export ANDROID_NDK="$HOME/tools/android-ndk-r27c"

CMAKE="$HOME/tools/cmake-4.0.0-linux-x86_64/bin/cmake"
NINJA="$HOME/tools/ninja"

# Resolve project root from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$PLUGIN_DIR/android"
BUILD_BASE="$HOME/build_sd_release"
OUT_DIR="$SRC/src/main/jniLibs/arm64-v8a"

ANDROID_ABI="arm64-v8a"
ANDROID_PLATFORM="android-28"
TOOLCHAIN="$ANDROID_NDK/build/cmake/android.toolchain.cmake"

echo "=== SD Android GPU Backend Build ==="
echo "CMake: $CMAKE"
echo "Ninja: $NINJA"
echo "NDK:   $ANDROID_NDK"
echo "Src:   $SRC"
echo "Out:   $OUT_DIR"

mkdir -p "$OUT_DIR"

COMMON_ARGS=(
    -G Ninja
    -DCMAKE_MAKE_PROGRAM="$NINJA"
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
    -DANDROID_ABI="$ANDROID_ABI"
    -DANDROID_PLATFORM="$ANDROID_PLATFORM"
    -DCMAKE_BUILD_TYPE=Release
    -DSD_BUILD_EXAMPLES=OFF
    -DSD_BUILD_SHARED_LIBS=OFF
    -DGGML_OPENMP=ON
)

# ------------------------------------------------------------------
# CPU variant
# ------------------------------------------------------------------
echo ""
echo "=== [1/3] Building CPU variant ==="
CPU_BUILD="$BUILD_BASE/cpu"
rm -rf "$CPU_BUILD"
mkdir -p "$CPU_BUILD"
cd "$CPU_BUILD"
"$CMAKE" "${COMMON_ARGS[@]}" -DSD_VULKAN=OFF -DSD_OPENCL=OFF "$SRC"
"$NINJA" -j"$(nproc)" sd_jni
cp "$CPU_BUILD/libsd_jni.so" "$OUT_DIR/libsd_jni.so"
echo "CPU OK"

# ------------------------------------------------------------------
# Vulkan variant
# ------------------------------------------------------------------
echo ""
echo "=== [2/3] Building Vulkan variant ==="
VULKAN_BUILD="$BUILD_BASE/vulkan"
rm -rf "$VULKAN_BUILD"
mkdir -p "$VULKAN_BUILD"
cd "$VULKAN_BUILD"
"$CMAKE" "${COMMON_ARGS[@]}" -DSD_VULKAN=ON -DSD_OPENCL=OFF "$SRC"
"$NINJA" -j"$(nproc)" sd_jni
cp "$VULKAN_BUILD/libsd_jni.so" "$OUT_DIR/libsd_jni_vulkan.so"
echo "Vulkan OK"

# ------------------------------------------------------------------
# OpenCL variant
# ------------------------------------------------------------------
echo ""
echo "=== [3/3] Building OpenCL variant ==="
OPENCL_BUILD="$BUILD_BASE/opencl"
rm -rf "$OPENCL_BUILD"
mkdir -p "$OPENCL_BUILD"
cd "$OPENCL_BUILD"
"$CMAKE" "${COMMON_ARGS[@]}" -DSD_VULKAN=OFF -DSD_OPENCL=ON \
    -DOpenCL_INCLUDE_DIRS="$HOME/tools/opencl-headers/OpenCL-Headers-2024.10.24" \
    "$SRC"
"$NINJA" -j"$(nproc)" sd_jni
cp "$OPENCL_BUILD/libsd_jni.so" "$OUT_DIR/libsd_jni_opencl.so"
echo "OpenCL OK"

# ------------------------------------------------------------------
# Copy OpenMP runtime
# ------------------------------------------------------------------
echo ""
echo "=== Copying OpenMP runtime ==="
cp "$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/18/lib/linux/aarch64/libomp.so" "$OUT_DIR/libomp.so"
echo "libomp.so OK"

# ------------------------------------------------------------------
# Strip debug symbols
# ------------------------------------------------------------------
echo ""
echo "=== Stripping debug symbols ==="
STRIP="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
for f in "$OUT_DIR"/libsd_jni.so "$OUT_DIR"/libsd_jni_vulkan.so "$OUT_DIR"/libsd_jni_opencl.so "$OUT_DIR"/libomp.so; do
    "$STRIP" --strip-debug "$f"
done

echo ""
echo "=== All builds completed ==="
ls -lh "$OUT_DIR"/*.so
