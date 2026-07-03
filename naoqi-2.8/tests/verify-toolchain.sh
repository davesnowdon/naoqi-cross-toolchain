#!/usr/bin/env bash
# Verify the NAO6 (NAOqi 2.8) toolchain. Usage: verify-toolchain.sh [toolchain-dir]
# Assertions (note: the C++ ABI check is INVERTED vs the naoqi-2.1 toolchain —
# NAOqi 2.8 libs are new-ABI, so __cxx11 symbols must be PRESENT):
#   1. compiler identity: i686-nao6-linux-gnu GCC 14.x
#   2. ELF 32-bit i386 output, interpreter /lib/ld-linux.so.2
#   3. glibc symbol ceiling <= 2.28 (the robot's)
#   4. NEW C++11 ABI: __cxx11 symbols present in a std::string-using binary
#   5. GLIBCXX ceiling covered by the shipped runtime-libs/libstdc++
#   6. the binary RUNS under the sysroot loader (SKIP_RUN=1 to skip on
#      hosts that cannot exec 32-bit binaries)
set -uo pipefail
TC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
TARGET=i686-nao6-linux-gnu
GXX="$TC/cross/bin/$TARGET-g++"
OD="$TC/cross/bin/$TARGET-objdump"
SYSROOT="$TC/cross/$TARGET/sysroot"
RT="$TC/runtime-libs"
FAIL=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

say(){ echo "  $*"; }
bad(){ echo "  FAIL: $*" >&2; FAIL=1; }

echo "== verify NAO6 toolchain: $TC =="

# 1. identity
[ -x "$GXX" ] || { bad "missing $GXX"; echo "== VERIFY FAILED =="; exit 1; }
"$GXX" --version | head -1 | grep -q 'GCC) 14\.' && say "compiler: $("$GXX" --version | head -1)" \
  || bad "unexpected compiler version"

# 2-5. compile a std::string-using program and inspect it
cat > "$T/probe.cpp" <<'EOF'
#include <iostream>
#include <string>
int main(){ std::string s = "nao6 toolchain probe"; std::cout << s << std::endl; return 0; }
EOF
if "$GXX" -O2 -std=c++17 "$T/probe.cpp" -o "$T/probe" 2>"$T/err"; then
  say "compile+link: ok (-std=c++17)"
else
  bad "compile failed: $(head -3 "$T/err")"
fi

if [ -x "$T/probe" ]; then
  file -b "$T/probe" | grep -q 'ELF 32-bit LSB.*Intel 80386' && say "ELF: 32-bit i386" || bad "not ELF32/i386: $(file -b "$T/probe")"
  file -b "$T/probe" | grep -q '/lib/ld-linux.so.2' && say "interpreter: /lib/ld-linux.so.2" || bad "wrong interpreter"

  maxglibc=$("$OD" -T "$T/probe" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
  say "glibc ceiling: ${maxglibc:-none} (robot: GLIBC_2.28)"
  if [ -n "$maxglibc" ] && [ "$(printf '%s\nGLIBC_2.28\n' "$maxglibc" | sort -V | tail -1)" != "GLIBC_2.28" ]; then
    bad "needs $maxglibc > robot's glibc 2.28"
  fi

  cxx11=$("$OD" -T "$T/probe" | grep -c '__cxx11')
  say "new C++11 ABI (__cxx11 symbols): $cxx11 (expect > 0)"
  [ "$cxx11" -gt 0 ] || bad "no __cxx11 symbols — wrong ABI default for NAOqi 2.8"

  maxgxx=$("$OD" -T "$T/probe" | grep -oE 'GLIBCXX_[0-9.]+' | sort -uV | tail -1)
  rtgxx=$(strings "$RT/libstdc++.so.6" 2>/dev/null | grep -oE '^GLIBCXX_[0-9.]+$' | sort -uV | tail -1)
  say "GLIBCXX: binary needs ${maxgxx:-none}; runtime-libs provides up to ${rtgxx:-none}"
  if [ -n "$maxgxx" ] && [ -n "$rtgxx" ] && \
     [ "$(printf '%s\n%s\n' "$maxgxx" "$rtgxx" | sort -V | tail -1)" != "$rtgxx" ]; then
    bad "binary needs $maxgxx but runtime-libs only provides $rtgxx"
  fi

  # 6. run under the sysroot's own loader (Debian glibc 2.28 == robot's version)
  if [ "${SKIP_RUN:-0}" != 1 ]; then
    out=$("$SYSROOT/lib/ld-linux.so.2" --library-path "$RT:$SYSROOT/lib:$SYSROOT/usr/lib" "$T/probe" 2>&1)
    [ "$out" = "nao6 toolchain probe" ] && say "runs under glibc-2.28 loader: ok" \
      || bad "run failed: $out"
  else
    say "run: skipped (SKIP_RUN=1)"
  fi
fi

if [ "$FAIL" = 0 ]; then echo "== ALL CHECKS PASSED =="; else echo "== VERIFY FAILED =="; exit 1; fi
