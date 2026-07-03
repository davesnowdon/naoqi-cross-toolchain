#!/usr/bin/env bash
# Assemble the BUILD sysroot for the NAO6 toolchain — 100% public sources
# (archive.debian.org, checksum-pinned). This is everything GCC needs to build
# libstdc++ etc. for i686/glibc-2.28. No robot, no proprietary bits.
#
# Usage: fetch-build-sysroot.sh <dest-sysroot-dir> [<download-cache-dir>]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=overlay-lib.sh
. "$HERE/overlay-lib.sh"

DEST="${1:?usage: fetch-build-sysroot.sh <dest-sysroot-dir> [cache-dir]}"
CACHE="${2:-$DEST.download}"
T="$DEST.extract"

echo "[sysroot] fetching pinned Debian 10 i386 dev packages"
fetch_debs "$CACHE"
rm -rf "$T"
extract_debs "$CACHE" "$T"

echo "[sysroot] assembling $DEST"
mkdir -p "$DEST"
overlay_dev "$T" "$DEST"
fix_symlinks "$DEST"
rm -rf "$T"

test -f "$DEST/usr/include/stdio.h"
test -e "$DEST/usr/lib/crt1.o" || test -e "$DEST/usr/lib/i386-linux-gnu/crt1.o"
test -e "$DEST/lib/ld-linux.so.2"
echo "[sysroot] OK: glibc 2.28 build sysroot at $DEST"
