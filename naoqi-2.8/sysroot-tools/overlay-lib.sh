# Shared helpers for assembling NAO6 sysroots (sourced, not executed).
# The NAO6 robot image is a RUNTIME: it ships no headers, CRT objects, static
# libs or unversioned .so symlinks. These come from Debian 10 i386 — the exact
# era match for the robot's glibc 2.28 / GCC 8 userland.

# Pinned Debian 10 packages (archive.debian.org). glibc 2.28 == the robot's.
DEB_BASE=http://archive.debian.org/debian/pool/main
DEBS="
g/glibc/libc6-dev_2.28-10+deb10u1_i386.deb b16dd2fac357e931e5167ea973294e4f5ee2f8c53ce7f7f125939ce3ccb9e38f
g/glibc/libc6_2.28-10+deb10u1_i386.deb 9667b0de0c4f8b4ffe7bbb986720a8d8e3947e415a072eb410d7f7db6e8a8786
l/linux/linux-libc-dev_4.19.249-2_i386.deb 0a25c176c2caf6df56c7e6f58acaebe16f54abdfe6105547a52e4488e08b36f9
"
BOOST_URL=https://archives.boost.io/release/1.64.0/source/boost_1_64_0.tar.bz2
BOOST_SHA256=7bcc5caace97baa948931d712ea5f37038dbb1c5d89b43ad4def4ed7cb683332

verify_sha256() { echo "$2  $1" | sha256sum -c - >/dev/null || { echo "FATAL: checksum mismatch: $1" >&2; exit 1; }; }

fetch_debs() {  # $1 = download dir
  local dir="$1" path sha f
  mkdir -p "$dir"
  while read -r path sha; do
    [ -n "$path" ] || continue
    f="$dir/$(basename "$path")"
    [ -f "$f" ] || wget -q -O "$f" "$DEB_BASE/$path"
    verify_sha256 "$f" "$sha"
  done <<EOF
$DEBS
EOF
}

extract_debs() {  # $1 = download dir, $2 = extraction root
  local dir="$1" root="$2" path sha
  mkdir -p "$root"
  while read -r path sha; do
    [ -n "$path" ] || continue
    dpkg-deb -x "$dir/$(basename "$path")" "$root"
  done <<EOF
$DEBS
EOF
}

overlay_dev() {  # $1 = extracted-debs root, $2 = sysroot  (never clobbers existing files)
  local t="$1" s="$2" ma f
  mkdir -p "$s/usr/include" "$s/usr/lib/i386-linux-gnu" "$s/lib/i386-linux-gnu" "$s/lib"
  cp -a --update=none "$t/usr/include/." "$s/usr/include/"
  # flatten Debian multiarch headers (bits/, gnu/, sys/, asm/) — robot layout is flat
  [ -d "$s/usr/include/i386-linux-gnu" ] && cp -a --update=none "$s/usr/include/i386-linux-gnu/." "$s/usr/include/"
  ma="$t/usr/lib/i386-linux-gnu"
  cp -a --update=none "$ma/." "$s/usr/lib/i386-linux-gnu/"
  for f in "$ma"/*.o "$ma"/*.a "$ma"/*.so; do [ -e "$f" ] && cp -a --update=none "$f" "$s/usr/lib/"; done
  # Debian runtime libs (loader included) — only where the sysroot lacks them
  # (a robot sysroot keeps its own; a pure build sysroot gets Debian's).
  cp -a --update=none "$t/lib/i386-linux-gnu/." "$s/lib/"
}

fix_symlinks() {  # $1 = sysroot
  local s="$1" l tgt
  # FIRST: bridge the Debian multiarch paths (/lib/i386-linux-gnu/<lib>) that the
  # linker scripts and dev symlinks reference, onto the flattened robot layout.
  # Must happen before the rewrite below, or those rewrites find no target.
  for l in libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 \
           libutil.so.1 libresolv.so.2 libnsl.so.1 libgcc_s.so.1 libcrypt.so.1 \
           ld-linux.so.2; do
    [ -e "$s/lib/$l" ] && ln -sfn "../$l" "$s/lib/i386-linux-gnu/$l"
  done
  # THEN: absolute symlinks resolve against the HOST fs at link time (e.g.
  # usr/lib/libpthread.so hitting the host's placeholder libpthread) — repoint
  # every one whose target exists inside the sysroot.
  while IFS= read -r l; do
    tgt=$(readlink "$l")
    [ -e "$s$tgt" ] && ln -sfn "$s$tgt" "$l"
  done < <(find "$s" -lname '/*')
  return 0
}

install_boost_headers() {  # $1 = download dir, $2 = sysroot
  local dir="$1" s="$2" f="$1/boost_1_64_0.tar.bz2"
  [ -d "$s/usr/include/boost" ] && return 0
  [ -f "$f" ] || wget -q -O "$f" "$BOOST_URL"
  verify_sha256 "$f" "$BOOST_SHA256"
  tar -xjf "$f" -C "$dir" boost_1_64_0/boost
  mv "$dir/boost_1_64_0/boost" "$s/usr/include/boost"
  rmdir "$dir/boost_1_64_0" 2>/dev/null || true
}

dev_symlinks() {  # $1 = sysroot: unversioned .so names for the robot's runtime libs
  ( cd "$1/usr/lib" || exit 0
    for f in libboost_*.so.1.64.0 libssl.so.1.1 libcrypto.so.1.1 libsystemd.so.0.*; do
      [ -e "$f" ] || continue
      b=$(echo "$f" | sed -E 's/\.so\..*$/.so/')
      [ -e "$b" ] || ln -s "$f" "$b"
    done )
}
