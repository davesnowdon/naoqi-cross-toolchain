#!/usr/bin/env bash
# make-symlinks-relative.sh <sysroot-or-toolchain-root>
#
# Repair absolute symlinks so the tree survives relocation (tar/untar, docker
# COPY, moving between machines). Two absolute-link flavors occur in assembled
# sysroots:
#   host-absolute — /path/on/build/host/<root>/lib/…  (created by older
#                    overlay-lib.sh fix_symlinks; resolves only on that host)
#   root-absolute — /lib/i386-linux-gnu/…             (Debian/robot dev links;
#                    resolve against the HOST fs instead of the tree)
#
# For each: if the target exists inside the tree (after re-rooting), replace
# the link with a RELATIVE one preserving resolution. If it does not, the link
# can never be useful in a relocated tree — delete it and say so.
#
# Idempotent. Already-relative links are untouched.
set -euo pipefail

ROOT="$(realpath "${1:?usage: make-symlinks-relative.sh <root>}")"
[ -d "$ROOT" ] || { echo "not a directory: $ROOT" >&2; exit 2; }

fixed=0 pruned=0
while IFS= read -r l; do
  tgt="$(readlink "$l")"
  if [ "${tgt#"$ROOT"/}" != "$tgt" ]; then
    candidate="$tgt"                       # host-absolute into this tree
  else
    candidate="$ROOT$tgt"                  # treat as root-absolute
  fi
  if [ -e "$candidate" ]; then
    ln -sfn "$(realpath -s --relative-to="$(dirname "$l")" "$candidate")" "$l"
    fixed=$((fixed + 1))
  else
    echo "prune (no target in tree): $l -> $tgt"
    rm "$l"
    pruned=$((pruned + 1))
  fi
done < <(find "$ROOT" -type l -lname '/*')

echo "made relative: $fixed, pruned: $pruned"
remaining="$(find "$ROOT" -type l -lname '/*' | wc -l)"
[ "$remaining" = 0 ] || { echo "BUG: $remaining absolute links remain" >&2; exit 1; }
