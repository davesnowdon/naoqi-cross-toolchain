#!/bin/bash
###############################################################################
# build-toolchain.sh
#
# Reproducibly build a MODERN, ABI-compatible, Atom-optimized cross toolchain
# for the Aldebaran NAO robot.
#
# Strategy: keep the proven glibc-2.13 sysroot from the original Aldebaran ctc
# (vendored as vendor/aldebaran-reuse.tar.xz) and rebuild ONLY binutils + GCC
# (+ host gdb) against it. This guarantees an identical glibc ABI while giving a
# modern C++ compiler. The era-appropriate static gdbserver is reused as-is.
#
# Result: GCC 14 / binutils 2.44 targeting i686-aldebaran-linux-gnu, glibc-2.13
# ABI, old (gcc4-compatible) libstdc++ ABI by default, -march=bonnell tuned,
# packaged as output/<name>.tar.xz and self-verified.
#
# Host prerequisites (Debian/Ubuntu): build-essential, wget, xz-utils, bzip2,
# libgmp-dev, file. flex/bison/texinfo/m4 are NOT required for these release
# tarballs. On non-Ubuntu hosts override GMP_INC / GMP_LIB (see below).
#
# Overridable via environment: OUT, WORK, JOBS, REUSE_TARBALL, GMP_INC, GMP_LIB,
# SKIP_VERIFY.
###############################################################################
set -euo pipefail

# ---- configuration ----------------------------------------------------------
TARGET=i686-aldebaran-linux-gnu
BINUTILS_VER=2.44
GCC_VER=14.3.0
GDB_VER=16.3
CTC_NAME=ctc-linux64-atom-2.1.4.14-modern

# Pinned upstream checksums (ftp.gnu.org) — verified before extraction so the
# build is reproducible and does not blindly trust the network/cache. The GCC
# prerequisites (gmp/mpfr/mpc/isl) are checksum-verified by download_prerequisites.
BINUTILS_SHA256=ce2017e059d63e67ddb9240e9d4ec49c2893605035cd60e92ad53177f4377237
GCC_SHA256=e0dc77297625631ac8e50fa92fffefe899a4eb702592da5c32ef04e2293aca3a
GDB_SHA256=bcfcd095528a987917acf9fff3f1672181694926cc18d609c99d0042c00224c5

HERE="$(cd "$(dirname "$0")" && pwd)"                 # repo root
OUT="${OUT:-$HERE/output/$CTC_NAME}"                  # assembled toolchain
PREFIX="$OUT/cross"                                   # mirrors original ctc layout
SYSROOT="$PREFIX/$TARGET/sysroot"

REUSE_TARBALL="${REUSE_TARBALL:-$HERE/vendor/aldebaran-reuse.tar.xz}"

WORK="${WORK:-$HERE/.build}"                          # scratch: sources + objects
SRC="$WORK/src"; OBJ="$WORK/obj"; HOSTLIBS="$OBJ/hostlibs"; REUSE="$WORK/reuse"
JOBS="${JOBS:-$(nproc)}"

# Host GMP (needed to build gdb); defaults match Debian/Ubuntu multiarch.
GMP_INC="${GMP_INC:-/usr/include/x86_64-linux-gnu}"
GMP_LIB="${GMP_LIB:-/usr/lib/x86_64-linux-gnu}"

export MAKEINFO=true                                  # skip texinfo docs
export PATH="$PREFIX/bin:$PATH"
mkdir -p "$SRC" "$OBJ"

msg(){ echo "[$(date +%T)] $*"; }
# verify_sha256 <file> <expected-hash>
verify_sha256(){ echo "$2  $1" | sha256sum -c - >/dev/null \
  || { echo "FATAL: checksum mismatch for $1" >&2; exit 1; }; }
# fetch <url> <sha256>: download if missing, then verify
fetch(){ local f; f="$(basename "$1")"; [ -f "$f" ] || wget -q "$1"; verify_sha256 "$f" "$2"; }

# ---- 0. fetch (checksum-verified) sources + unpack the reused sysroot --------
cd "$SRC"
fetch https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VER.tar.xz "$BINUTILS_SHA256"
fetch https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/gcc-$GCC_VER.tar.xz    "$GCC_SHA256"
fetch https://ftp.gnu.org/gnu/gdb/gdb-$GDB_VER.tar.xz                 "$GDB_SHA256"
[ -d binutils-$BINUTILS_VER ] || tar xf binutils-$BINUTILS_VER.tar.xz
[ -d gcc-$GCC_VER ]          || { tar xf gcc-$GCC_VER.tar.xz; ( cd gcc-$GCC_VER && ./contrib/download_prerequisites ); }
[ -d gdb-$GDB_VER ]          || tar xf gdb-$GDB_VER.tar.xz

if [ ! -e "$REUSE/sysroot/lib/libc-2.13.so" ]; then
  msg "verifying + unpacking reuse blob $REUSE_TARBALL"
  if [ -f "$REUSE_TARBALL.sha256" ]; then
    ( cd "$(dirname "$REUSE_TARBALL")" && sha256sum -c "$(basename "$REUSE_TARBALL").sha256" )
  else
    echo "warning: no $REUSE_TARBALL.sha256 to verify against" >&2
  fi
  rm -rf "$REUSE"; mkdir -p "$REUSE"
  tar -C "$REUSE" -xf "$REUSE_TARBALL"
fi
if [ ! -e "$SYSROOT/lib/libc-2.13.so" ]; then
  msg "staging reused glibc-2.13 sysroot into $SYSROOT"
  mkdir -p "$PREFIX/$TARGET"
  cp -a "$REUSE/sysroot" "$SYSROOT"
fi

# ---- 1. binutils ------------------------------------------------------------
msg "building binutils $BINUTILS_VER"
rm -rf "$OBJ/binutils"; mkdir -p "$OBJ/binutils"; cd "$OBJ/binutils"
"$SRC/binutils-$BINUTILS_VER/configure" --target="$TARGET" --prefix="$PREFIX" \
  --with-sysroot="$SYSROOT" --disable-multilib --disable-nls --disable-werror \
  --enable-plugins MAKEINFO=true
make -j"$JOBS" MAKEINFO=true && make install MAKEINFO=true

# ---- 2. GCC 14 (core deliverable) -------------------------------------------
msg "building gcc $GCC_VER (this is the long one)"
rm -rf "$OBJ/gcc"; mkdir -p "$OBJ/gcc"; cd "$OBJ/gcc"
"$SRC/gcc-$GCC_VER/configure" --target="$TARGET" --prefix="$PREFIX" \
  --with-sysroot="$SYSROOT" --with-build-sysroot="$SYSROOT" \
  --with-glibc-version=2.13 \
  --enable-languages=c,c++ --disable-multilib --disable-nls \
  --enable-__cxa_atexit --enable-threads=posix --enable-clocale=gnu \
  --with-default-libstdcxx-abi=gcc4-compatible \
  --with-arch=bonnell --with-tune=bonnell --with-fpmath=sse \
  --disable-libsanitizer --disable-default-pie \
  --with-pkgversion="NAO modern toolchain (Atom/bonnell, glibc-2.13 ABI)" \
  MAKEINFO=true
make -j"$JOBS" MAKEINFO=true && make install MAKEINFO=true

# ---- 3. host cross gdb ; reuse era-appropriate gdbserver --------------------
msg "building host MPFR (static) then cross gdb $GDB_VER"
if [ ! -f "$HOSTLIBS/lib/libmpfr.a" ]; then
  rm -rf "$OBJ/mpfr"; mkdir -p "$OBJ/mpfr"; cd "$OBJ/mpfr"
  "$SRC/gcc-$GCC_VER/mpfr/configure" --prefix="$HOSTLIBS" --disable-shared \
    --enable-static --with-gmp-include="$GMP_INC" --with-gmp-lib="$GMP_LIB"
  make -j"$JOBS" && make install
fi
rm -rf "$OBJ/gdb"; mkdir -p "$OBJ/gdb"; cd "$OBJ/gdb"
"$SRC/gdb-$GDB_VER/configure" --target="$TARGET" --prefix="$PREFIX" \
  --with-sysroot="$SYSROOT" --with-gmp-include="$GMP_INC" --with-gmp-lib="$GMP_LIB" \
  --with-mpfr="$HOSTLIBS" --disable-nls --disable-gdbserver MAKEINFO=true
make -j"$JOBS" all-gdb MAKEINFO=true && make install-gdb MAKEINFO=true

# The NAO kernel is 2.6.33; a modern gdbserver needs newer kernel headers/ABI.
# Reuse the era-appropriate static gdbserver (drives fine from the modern host gdb).
mkdir -p "$OUT/robot-tools"
cp -a "$REUSE/gdbserver" "$OUT/robot-tools/gdbserver"

# ---- 4. runtime redistributable (built against glibc 2.13) ------------------
msg "collecting target runtime libraries"
RT="$OUT/runtime-libs"; rm -rf "$RT"; mkdir -p "$RT"
for pat in 'libstdc++.so.6*' 'libgcc_s.so.1' 'libatomic.so.1*' 'libgomp.so.1*'; do
  find "$PREFIX/$TARGET/lib" -maxdepth 1 -name "$pat" ! -name '*-gdb.py' -exec cp -a {} "$RT/" \;
done

# ---- 5. sysroot-aware pkg-config wrapper ------------------------------------
# cross-config.cmake points at <tuple>-pkg-config; generate it so pkg_check_modules
# resolves .pc files inside the sysroot (needs a host pkg-config to delegate to).
msg "installing $TARGET-pkg-config wrapper"
cat > "$PREFIX/bin/$TARGET-pkg-config" <<EOF
#!/bin/sh
# Sysroot-aware pkg-config for the NAO cross toolchain (delegates to host pkg-config).
here="\$(cd "\$(dirname "\$0")" && pwd)"
sysroot="\$here/../$TARGET/sysroot"
export PKG_CONFIG_SYSROOT_DIR="\$sysroot"
export PKG_CONFIG_LIBDIR="\$sysroot/usr/lib/pkgconfig:\$sysroot/usr/lib/$TARGET/pkgconfig:\$sysroot/usr/share/pkgconfig"
exec pkg-config "\$@"
EOF
chmod +x "$PREFIX/bin/$TARGET-pkg-config"

# ---- 6. assemble the drop-in ctc (integration files + tests) ----------------
msg "assembling toolchain integration files"
cp -a "$HERE/toolchain-files/." "$OUT/"
mkdir -p "$OUT/tests"; cp -a "$HERE/tests/verify-toolchain.sh" "$OUT/tests/"
[ -f "$HERE/README.md" ] && cp -a "$HERE/README.md" "$OUT/README.md"

# ---- 7. strip host executables (safe; big size win) -------------------------
msg "stripping host executables"
find "$PREFIX/bin" "$PREFIX/libexec" -type f -print0 \
  | xargs -0 -n1 -P"$JOBS" strip --strip-unneeded 2>/dev/null || true

# ---- 8. package -------------------------------------------------------------
msg "packaging $CTC_NAME.tar.xz"
tar -C "$(dirname "$OUT")" -cf - "$(basename "$OUT")" | xz -6 -T0 > "$OUT.tar.xz"
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT").tar.xz" | tee "$(basename "$OUT").tar.xz.sha256" )

# ---- 9. self-verify ---------------------------------------------------------
"$PREFIX/bin/$TARGET-gcc" --version | head -1
if [ "${SKIP_VERIFY:-0}" != 1 ]; then
  msg "verifying"
  "$OUT/tests/verify-toolchain.sh"
fi
msg "DONE -> $OUT.tar.xz"
