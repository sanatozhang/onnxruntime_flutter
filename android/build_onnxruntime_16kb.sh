#!/bin/bash
# Build 16KB-aligned onnxruntime shared library.
# Usage:
#   export ANDROID_SDK_ROOT=/path/to/sdk
#   export ANDROID_NDK=/path/to/ndk-r28
#   export ONNXRUNTIME_SRC_DIR=/path/to/onnxruntime
#   ./build_onnxruntime_16kb.sh [arm64-v8a|armeabi-v7a]

set -euo pipefail

ABI=${1:-arm64-v8a}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONNXRUNTIME_SRC_DIR="${ONNXRUNTIME_SRC_DIR:-${SCRIPT_DIR}/../../onnxruntime}"
OUTPUT_DIR="${SCRIPT_DIR}/src/main/jniLibs/${ABI}"

case "$ABI" in
  arm64-v8a|armeabi-v7a)
    ANDROID_ABI="$ABI"
    ;;
  *)
    echo "ERROR: Unsupported ABI: $ABI (arm64-v8a, armeabi-v7a)"
    exit 1
    ;;
esac

# Try to read sdk/ndk from Plaud-App local.properties if env not set.
LOCAL_PROPERTIES="${SCRIPT_DIR}/../../Plaud-App/plaud-android/local.properties"
if [ -z "${ANDROID_SDK_ROOT:-}" ] && [ -f "$LOCAL_PROPERTIES" ]; then
  SDK_LINE=$(grep -m1 '^sdk.dir=' "$LOCAL_PROPERTIES" || true)
  if [ -n "$SDK_LINE" ]; then
    ANDROID_SDK_ROOT=${SDK_LINE#sdk.dir=}
  fi
fi

if [ -z "${ANDROID_NDK:-}" ] && [ -f "$LOCAL_PROPERTIES" ]; then
  NDK_LINE=$(grep -m1 '^ndk.dir=' "$LOCAL_PROPERTIES" || true)
  if [ -z "$NDK_LINE" ]; then
    NDK_LINE=$(grep -m1 '^ndk=' "$LOCAL_PROPERTIES" || true)
  fi
  if [ -n "$NDK_LINE" ]; then
    ANDROID_NDK=${NDK_LINE#ndk.dir=}
    ANDROID_NDK=${ANDROID_NDK#ndk=}
  fi
fi

if [ -z "${ANDROID_NDK:-}" ]; then
  if [ -n "${ANDROID_NDK_ROOT:-}" ]; then
    ANDROID_NDK="$ANDROID_NDK_ROOT"
  else
    echo "ERROR: ANDROID_NDK or ANDROID_NDK_ROOT is not set"
    exit 1
  fi
fi

if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  if [ -n "${ANDROID_HOME:-}" ]; then
    ANDROID_SDK_ROOT="$ANDROID_HOME"
  else
    echo "ERROR: ANDROID_SDK_ROOT is not set"
    exit 1
  fi
fi

if [ ! -d "$ANDROID_NDK" ]; then
  echo "ERROR: NDK dir not found: $ANDROID_NDK"
  exit 1
fi
if [ ! -d "$ANDROID_SDK_ROOT" ]; then
  echo "ERROR: Android SDK dir not found: $ANDROID_SDK_ROOT"
  exit 1
fi
if [ ! -d "$ONNXRUNTIME_SRC_DIR" ]; then
  echo "ERROR: onnxruntime source dir not found: $ONNXRUNTIME_SRC_DIR"
  exit 1
fi
if [ ! -f "$ONNXRUNTIME_SRC_DIR/cmake/CMakeLists.txt" ]; then
  echo "ERROR: CMakeLists.txt not found under $ONNXRUNTIME_SRC_DIR/cmake"
  exit 1
fi

# Require NDK r28+ for 16KB page size support.
if [ -f "$ANDROID_NDK/source.properties" ]; then
  NDK_REV=$(grep -m1 '^Pkg.Revision' "$ANDROID_NDK/source.properties" | sed 's/.*=//;s/ //g')
  NDK_MAJOR=${NDK_REV%%.*}
  if [ -n "$NDK_MAJOR" ] && [ "$NDK_MAJOR" -lt 28 ]; then
    echo "ERROR: NDK r28+ required. Found: $NDK_REV"
    exit 1
  fi
fi

echo "=========================================="
echo "Build 16KB-aligned onnxruntime"
echo "ABI: $ABI"
echo "Source: $ONNXRUNTIME_SRC_DIR"
echo "Output: $OUTPUT_DIR"
echo "NDK: $ANDROID_NDK"
echo "SDK: $ANDROID_SDK_ROOT"
echo "=========================================="

mkdir -p "$OUTPUT_DIR"

cd "$ONNXRUNTIME_SRC_DIR"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found"
  exit 1
fi

ONNXRUNTIME_BUILD_DIR="build/android_${ABI}_16kb"
rm -rf "$ONNXRUNTIME_BUILD_DIR"
mkdir -p "$ONNXRUNTIME_BUILD_DIR"

# Clear env flags to prevent linker flags from leaking into compile flags.
unset CFLAGS CXXFLAGS LDFLAGS

python3 tools/ci_build/build.py   --build_dir "$ONNXRUNTIME_BUILD_DIR"   --android   --android_abi "$ANDROID_ABI"   --android_api 24   --android_ndk_path "$ANDROID_NDK"   --android_sdk_path "$ANDROID_SDK_ROOT"   --android_cpp_shared   --build_shared_lib   --config Release   --skip_tests   --cmake_extra_defines onnxruntime_BUILD_UNIT_TESTS=OFF   --cmake_extra_defines CMAKE_C_FLAGS=   --cmake_extra_defines CMAKE_CXX_FLAGS=   --cmake_extra_defines CMAKE_SHARED_LINKER_FLAGS=   --cmake_extra_defines CMAKE_EXE_LINKER_FLAGS=   --cmake_extra_defines CMAKE_MODULE_LINKER_FLAGS=   --parallel "$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

if [ "$ANDROID_ABI" = "arm64-v8a" ]; then
  LIB_SEARCH_PATHS=(
    "$ONNXRUNTIME_BUILD_DIR/Release/libonnxruntime.so"
    "$ONNXRUNTIME_BUILD_DIR/arm64-v8a/Release/libonnxruntime.so"
    "$ONNXRUNTIME_BUILD_DIR/Android/Release/libonnxruntime.so"
    "$ONNXRUNTIME_BUILD_DIR/Android/arm64-v8a/Release/libonnxruntime.so"
  )
else
  LIB_SEARCH_PATHS=(
    "$ONNXRUNTIME_BUILD_DIR/Release/libonnxruntime.so"
    "$ONNXRUNTIME_BUILD_DIR/armeabi-v7a/Release/libonnxruntime.so"
    "$ONNXRUNTIME_BUILD_DIR/Android/Release/libonnxruntime.so"
    "$ONNXRUNTIME_BUILD_DIR/Android/armeabi-v7a/Release/libonnxruntime.so"
  )
fi

LIB_FILE=""
for path in "${LIB_SEARCH_PATHS[@]}"; do
  if [ -f "$path" ]; then
    LIB_FILE="$path"
    break
  fi
done

if [ -z "$LIB_FILE" ]; then
  LIB_FILE=$(find "$ONNXRUNTIME_SRC_DIR/$ONNXRUNTIME_BUILD_DIR" -name "libonnxruntime.so" -type f 2>/dev/null | head -1)
fi

if [ -z "$LIB_FILE" ]; then
  echo "ERROR: libonnxruntime.so not found in build output"
  exit 1
fi

echo "Found: $LIB_FILE"

ABS_OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_DIR")" && pwd)/$(basename "$OUTPUT_DIR")"
mkdir -p "$ABS_OUTPUT_DIR"
cp "$LIB_FILE" "$ABS_OUTPUT_DIR/libonnxruntime.so"

echo "Copied to: $ABS_OUTPUT_DIR/libonnxruntime.so"

# Verify LOAD alignment using Python (no reliance on system readelf)
python3 - "$ABS_OUTPUT_DIR/libonnxruntime.so" <<'PY'
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
PAGE_16K = 0x4000

with path.open('rb') as f:
    ident = f.read(16)
    if ident[:4] != b'ELF':
        print('ERROR: not an ELF file')
        sys.exit(2)
    elf_class = ident[4]
    data = ident[5]
    endian = '<' if data == 1 else '>'
    if elf_class == 2:
        hdr_fmt = endian + 'HHIQQQIHHHHHH'
        hdr = f.read(struct.calcsize(hdr_fmt))
        (e_type, e_machine, e_version, e_entry, e_phoff, e_shoff,
         e_flags, e_ehsize, e_phentsize, e_phnum, e_shentsize,
         e_shnum, e_shstrndx) = struct.unpack(hdr_fmt, hdr)
        ph_fmt = endian + 'IIQQQQQQ'
    else:
        hdr_fmt = endian + 'HHIIIIIHHHHHH'
        hdr = f.read(struct.calcsize(hdr_fmt))
        (e_type, e_machine, e_version, e_entry, e_phoff, e_shoff,
         e_flags, e_ehsize, e_phentsize, e_phnum, e_shentsize,
         e_shnum, e_shstrndx) = struct.unpack(hdr_fmt, hdr)
        ph_fmt = endian + 'IIIIIIII'
    f.seek(e_phoff)
    aligns = []
    for _ in range(e_phnum):
        ph = f.read(struct.calcsize(ph_fmt))
        if len(ph) < struct.calcsize(ph_fmt):
            break
        if elf_class == 2:
            p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack(ph_fmt, ph)
        else:
            p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack(ph_fmt, ph)
        if p_type == 1:
            aligns.append(p_align)

if not aligns:
    print('ERROR: no PT_LOAD segments found')
    sys.exit(2)

ok = all(a >= PAGE_16K for a in aligns)
print(f"LOAD alignments: {[hex(a) for a in aligns]}")
if not ok:
    print('ERROR: 16KB alignment not met')
    sys.exit(2)

print('OK: 16KB alignment verified')
PY

echo "Done."
