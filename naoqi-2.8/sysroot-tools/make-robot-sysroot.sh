#!/usr/bin/env bash
# Assemble the ROBOT (application) sysroot for NAO6: the robot's own runtime +
# NAOqi 2.8 stack, overlaid with the Debian 10 dev files and boost 1.64 headers
# needed to compile and link against it. Use this sysroot to build NAOqi programs
# (the toolchain itself only needs fetch-build-sysroot.sh).
#
# Usage:
#   make-robot-sysroot.sh --from-robot <ROBOT_IP> <dest-dir>   # rsyncs from the robot
#   make-robot-sysroot.sh --from-rsync <rsync-dir> <dest-dir>  # existing rsync copy
#
# The rsync needs the robot's password for user 'nao'. What is copied:
#   /lib /usr/lib /usr/include /opt/aldebaran   (~1.1 GB)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=overlay-lib.sh
. "$HERE/overlay-lib.sh"

MODE="${1:?usage: $0 --from-robot <IP> <dest> | --from-rsync <dir> <dest>}"
SRC="${2:?missing source (robot IP or rsync dir)}"
DEST="${3:?missing destination sysroot dir}"
CACHE="$DEST.download"

case "$MODE" in
  --from-robot)
    echo "[robot-sysroot] rsyncing from nao@$SRC (password prompts expected)"
    mkdir -p "$DEST"
    for d in lib usr/lib usr/include opt/aldebaran; do
      mkdir -p "$DEST/$d"
      rsync -az "nao@$SRC:/$d/" "$DEST/$d/"
    done
    ;;
  --from-rsync)
    [ -d "$SRC/opt/aldebaran/lib" ] || { echo "FATAL: $SRC does not look like a robot rsync (no opt/aldebaran/lib)" >&2; exit 1; }
    echo "[robot-sysroot] copying $SRC -> $DEST (hardlinks where possible)"
    mkdir -p "$DEST"
    cp -al "$SRC/." "$DEST/" 2>/dev/null || cp -a "$SRC/." "$DEST/"
    ;;
  *) echo "FATAL: unknown mode $MODE" >&2; exit 1 ;;
esac

# sanity: this must be the 32-bit NAOqi 2.8 stack
file -L "$DEST/opt/aldebaran/lib/libqi.so" | grep -q 'ELF 32-bit' || {
  echo "FATAL: libqi.so is not ELF 32-bit — unexpected robot image" >&2; exit 1; }

echo "[robot-sysroot] overlaying Debian 10 dev files (headers/CRT/static libs)"
fetch_debs "$CACHE"
T="$DEST.extract"; rm -rf "$T"
extract_debs "$CACHE" "$T"
overlay_dev "$T" "$DEST"     # --update=none: the robot's own libs stay authoritative
rm -rf "$T"

echo "[robot-sysroot] boost 1.64 headers (robot ships only the libs)"
install_boost_headers "$CACHE" "$DEST"

echo "[robot-sysroot] symlink fixes"
fix_symlinks "$DEST"
dev_symlinks "$DEST"

test -f "$DEST/opt/aldebaran/include/qi/session.hpp"
test -e "$DEST/usr/lib/libboost_thread.so"
echo "[robot-sysroot] OK: NAOqi 2.8 app sysroot at $DEST"
echo "                use it via:  ROBOT_SYSROOT=$DEST examples/build-examples.sh"
