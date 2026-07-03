#!/usr/bin/env bash
# Build the NAO6 (NAOqi 2.8) examples with the naoqi-2.8 toolchain.
#
#   MT            = toolchain dir (default: <tree>/output/ctc-linux64-nao6-2.8-modern)
#   ROBOT_SYSROOT = app sysroot from sysroot-tools/make-robot-sysroot.sh. Optional:
#                   without it only plain_hello builds (the CI case).
#   SKIP_RUN=1    = skip the run-under-loader gate (hosts that can't exec i686)
#
# plain_hello is always built AND RUN (CI gate). say_hello_v6 / robot_info_v6 use
# the qi framework (NAOqi 2.8's C++ API) and need the robot sysroot. Everything
# is -std=gnu++17 (strict -std=c++NN breaks qi's log macros) with the toolchain's
# default NEW C++11 ABI, matching the robot's NAOqi libs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="$(cd "$HERE/.." && pwd)"
MT="${MT:-$TREE/output/ctc-linux64-nao6-2.8-modern}"
ROBOT_SYSROOT="${ROBOT_SYSROOT:-}"

TARGET=i686-nao6-linux-gnu
GXX="$MT/cross/bin/$TARGET-g++"
SYSROOT="$MT/cross/$TARGET/sysroot"; RT="$MT/runtime-libs"
SRC="$HERE/src"; BIN="$HERE/bin"
mkdir -p "$BIN"
[ -x "$GXX" ] || { echo "FATAL: toolchain g++ not found: $GXX (run ./build-toolchain.sh or set MT)" >&2; exit 1; }

echo "== NAO6 examples =="
"$GXX" --version | head -1

echo "   plain_hello (always; the CI gate)"
"$GXX" -O2 -std=c++17 "$SRC/plain_hello_v6.cpp" -o "$BIN/plain_hello"
if [ "${SKIP_RUN:-0}" != 1 ]; then
  "$SYSROOT/lib/ld-linux.so.2" --library-path "$RT:$SYSROOT/lib:$SYSROOT/usr/lib" \
    "$BIN/plain_hello" | sed 's/^/     | /'
fi

built="plain_hello"
if [ -n "$ROBOT_SYSROOT" ] && [ -f "$ROBOT_SYSROOT/opt/aldebaran/include/qi/session.hpp" ]; then
  echo "   NAOqi 2.8 examples: REAL (ROBOT_SYSROOT=$ROBOT_SYSROOT)"
  # --sysroot: MUST point at the app sysroot, not just -L into it — Debian's
  # libc.so linker script carries absolute multiarch paths, which ld only
  # re-roots for scripts located INSIDE the active sysroot.
  QI=(--sysroot="$ROBOT_SYSROOT"
      -I"$ROBOT_SYSROOT/opt/aldebaran/include"
      -L"$ROBOT_SYSROOT/opt/aldebaran/lib"
      -Wl,-rpath-link,"$ROBOT_SYSROOT/opt/aldebaran/lib"
      -lqi -lboost_thread -lboost_system -lboost_chrono)
  "$GXX" -O2 -std=gnu++17 "$SRC/say_hello_v6.cpp"  -o "$BIN/say_hello_v6"  "${QI[@]}"
  "$GXX" -O2 -std=gnu++17 "$SRC/robot_info_v6.cpp" -o "$BIN/robot_info_v6" "${QI[@]}"
  built="$built say_hello_v6 robot_info_v6"
else
  echo "   NAOqi 2.8 examples: skipped (set ROBOT_SYSROOT=<dir from make-robot-sysroot.sh>)"
fi

echo "   verifying: ELF32, glibc<=2.28, new ABI"
OD="$MT/cross/bin/$TARGET-objdump"
for b in $built; do
  f="$BIN/$b"
  file -b "$f" | grep -q 'ELF 32-bit LSB.*80386' || { echo "FAIL: $b not ELF32/i386" >&2; exit 1; }
  mx=$("$OD" -T "$f" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
  [ -z "$mx" ] || [ "$(printf '%s\nGLIBC_2.28\n' "$mx" | sort -V | tail -1)" = "GLIBC_2.28" ] \
    || { echo "FAIL: $b needs $mx > glibc 2.28" >&2; exit 1; }
  cx=$("$OD" -T "$f" | grep -c '__cxx11' || true)
  [ "$cx" -gt 0 ] || { echo "FAIL: $b has no __cxx11 symbols (wrong ABI for NAOqi 2.8)" >&2; exit 1; }
  echo "     $b: ok (glibc<=${mx:-2.28}, __cxx11=$cx)"
done

echo "   assembling deploy bundle"
DEP="$HERE/deploy/nao6-modern-examples"
rm -rf "$DEP"; mkdir -p "$DEP/bin" "$DEP/lib"
for b in $built; do cp "$BIN/$b" "$DEP/bin/"; done
cp -P "$RT/libstdc++.so.6"* "$RT/libgcc_s.so.1" "$DEP/lib/" 2>/dev/null || true
cp "$HERE/run.sh" "$HERE/DEPLOY-V6.md" "$DEP/"
chmod +x "$DEP/run.sh" "$DEP/bin/"*
( cd "$HERE/deploy" && tar czf nao6-modern-examples.tar.gz nao6-modern-examples )
echo "== done -> $DEP (and .tar.gz) =="
