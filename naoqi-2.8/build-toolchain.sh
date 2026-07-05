#!/usr/bin/env bash
###############################################################################
# Modern GCC-14 cross-toolchain for NAO V6 (NAOqi 2.8).
#
# Target: i686-nao6-linux-gnu — the STOCK NAO6 userland is 32-bit i686 on a
# 64-bit kernel (measured on a real robot: all 444 NAOqi 2.8 libs are ELF32).
#   * glibc floor 2.28 (the robot's), silvermont-tuned (Atom E3845),
#   * DEFAULT NEW C++11 ABI — NAOqi 2.8 libs are __cxx11 (the opposite of the
#     naoqi-2.1 toolchain, whose NAOqi libs need the old gcc4-compatible ABI).
#
# Unlike naoqi-2.1 there is NO vendored blob: the build sysroot is assembled
# from checksum-pinned public sources (archive.debian.org glibc 2.28 + kernel
# headers) by sysroot-tools/fetch-build-sysroot.sh. The proprietary NAOqi 2.8
# stack is only needed to build the NAOqi *examples*, and comes from your own
# robot via sysroot-tools/make-robot-sysroot.sh (ROBOT_SYSROOT=).
#
# Host prerequisites (Debian/Ubuntu): build-essential, wget, xz-utils, bzip2,
# dpkg-dev (dpkg-deb), file. Overridable via environment: OUT, WORK, JOBS.
###############################################################################
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

BINUTILS_VER=2.44
GCC_VER=14.3.0
# Pinned upstream checksums (ftp.gnu.org) — verified before extraction. GCC's
# prerequisites (gmp/mpfr/mpc/isl) are checksum-verified by download_prerequisites.
BINUTILS_SHA256=ce2017e059d63e67ddb9240e9d4ec49c2893605035cd60e92ad53177f4377237
GCC_SHA256=e0dc77297625631ac8e50fa92fffefe899a4eb702592da5c32ef04e2293aca3a

TARGET=i686-nao6-linux-gnu
OUT="${OUT:-$HERE/output/ctc-linux64-nao6-2.8-modern}"
WORK="${WORK:-$HERE/.build}"
JOBS="${JOBS:-$(nproc)}"
PREFIX="$OUT/cross"
SYSROOT="$PREFIX/$TARGET/sysroot"     # inside the prefix -> relocatable tarball
export PATH="$PREFIX/bin:$PATH"

msg(){ echo "[$(date +%T)] $*"; }
verify_sha256(){ echo "$2  $1" | sha256sum -c - >/dev/null || { echo "FATAL: checksum mismatch: $1" >&2; exit 1; }; }
fetch(){ local f; f="$(basename "$1")"; [ -f "$f" ] || wget -q "$1"; verify_sha256 "$f" "$2"; }

mkdir -p "$WORK/src" "$OUT"

msg "== [0] sources =="
( cd "$WORK/src"
  fetch https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VER.tar.xz "$BINUTILS_SHA256"
  fetch https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/gcc-$GCC_VER.tar.xz    "$GCC_SHA256"
)

msg "== [1] build sysroot (public Debian 10 glibc 2.28) =="
if [ ! -f "$SYSROOT/usr/include/stdio.h" ]; then
  "$HERE/sysroot-tools/fetch-build-sysroot.sh" "$SYSROOT" "$WORK/sysroot-cache"
fi

msg "== [2] binutils $BINUTILS_VER =="
if [ ! -x "$PREFIX/bin/$TARGET-ld" ]; then
  rm -rf "$WORK/binutils-$BINUTILS_VER" "$WORK/binutils"
  tar -C "$WORK" -xf "$WORK/src/binutils-$BINUTILS_VER.tar.xz"
  mkdir -p "$WORK/binutils" && cd "$WORK/binutils"
  "../binutils-$BINUTILS_VER/configure" --target="$TARGET" --prefix="$PREFIX" \
      --with-sysroot="$SYSROOT" --disable-nls --disable-werror \
      --disable-gdb --disable-gdbserver --disable-sim MAKEINFO=true
  make -j"$JOBS" MAKEINFO=true
  make install MAKEINFO=true
fi
"$PREFIX/bin/$TARGET-ld" --version | head -1

msg "== [3] GCC $GCC_VER (c, c++) =="
if [ ! -x "$PREFIX/bin/$TARGET-g++" ]; then
  if [ ! -d "$WORK/gcc-$GCC_VER" ]; then
    tar -C "$WORK" -xf "$WORK/src/gcc-$GCC_VER.tar.xz"
    ( cd "$WORK/gcc-$GCC_VER" && ./contrib/download_prerequisites )   # self-verifies sha512
  fi
  rm -rf "$WORK/gcc"; mkdir -p "$WORK/gcc"; cd "$WORK/gcc"
  # NOTE: no --with-default-libstdcxx-abi flag — the DEFAULT (new C++11) ABI is
  # exactly what NAOqi 2.8 needs. Compare naoqi-2.1/build-toolchain.sh.
  "../gcc-$GCC_VER/configure" --target="$TARGET" --prefix="$PREFIX" \
      --with-sysroot="$SYSROOT" --with-glibc-version=2.28 \
      --enable-languages=c,c++ --disable-multilib --disable-nls \
      --disable-bootstrap --disable-libsanitizer --enable-checking=release \
      --with-arch=silvermont --with-tune=silvermont \
      MAKEINFO=true
  make -j"$JOBS" MAKEINFO=true
  make install MAKEINFO=true
fi
"$PREFIX/bin/$TARGET-g++" --version | head -1

msg "== [4] runtime-libs (deploy set: this GCC's newer 32-bit libstdc++) =="
mkdir -p "$OUT/runtime-libs"
cp -P "$PREFIX/$TARGET/lib/libstdc++.so.6"* "$OUT/runtime-libs/" 2>/dev/null || true
cp -P "$PREFIX/$TARGET/lib/libgcc_s.so.1"   "$OUT/runtime-libs/" 2>/dev/null || true
rm -f "$OUT/runtime-libs/"*.py
ls "$OUT/runtime-libs" >/dev/null

msg "== [5] toolchain files + tests + sysroot tools =="
cp "$HERE/toolchain-files/"*.cmake "$OUT/"
mkdir -p "$OUT/tests"
cp "$HERE/tests/verify-toolchain.sh" "$OUT/tests/"
chmod +x "$OUT/tests/verify-toolchain.sh"
# Ship sysroot-tools so archive-only users can make a robot app sysroot
# (make-robot-sysroot.sh) without cloning the repo.
mkdir -p "$OUT/sysroot-tools"
cp "$HERE/sysroot-tools/"*.sh "$OUT/sysroot-tools/"
chmod +x "$OUT/sysroot-tools/"*.sh

msg "== [6] strip host binaries =="
find "$PREFIX/bin" "$PREFIX/libexec" -type f -perm -u+x \
  -exec sh -c 'file -b "$1" | grep -q "ELF 64-bit.*not stripped" && strip "$1" || true' _ {} \; 2>/dev/null || true

msg "== [7] package =="
( cd "$(dirname "$OUT")"
  base="$(basename "$OUT")"
  tar -cf - "$base" | xz -6 -T0 > "$base.tar.xz"
  sha256sum "$base.tar.xz" > "$base.tar.xz.sha256"
)

msg "== [8] self-verify =="
"$OUT/tests/verify-toolchain.sh" "$OUT"

msg "== DONE: $OUT =="
