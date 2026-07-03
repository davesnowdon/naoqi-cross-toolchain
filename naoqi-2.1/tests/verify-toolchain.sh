#!/bin/bash
# Self-contained ABI/optimization verification for the modern NAO toolchain.
# Run from anywhere: tests/verify-toolchain.sh
#
# Note: this script uses command exit codes AS test results (e.g. grep), so it
# deliberately does NOT use `set -e`. Instead every compile/link/run step is
# checked explicitly and sets FAIL=1 with diagnostics on failure, so a broken
# toolchain can never masquerade as a pass.
#
# Env: SKIP_RUN=1 skips only the final "run under the reused loader" step, for
# hosts whose sandbox blocks executing the 32-bit binary (the compiled artifact
# is still validated; the robot itself is unaffected).
set -uo pipefail
CTC="$(cd "$(dirname "$0")/.." && pwd)"
TARGET=i686-aldebaran-linux-gnu
PREFIX="$CTC/cross"
SYSROOT="$PREFIX/$TARGET/sysroot"
RT="$CTC/runtime-libs"
GCC="$PREFIX/bin/$TARGET-gcc"; GXX="$PREFIX/bin/$TARGET-g++"
OBJDUMP="$PREFIX/bin/$TARGET-objdump"; READELF="$PREFIX/bin/$TARGET-readelf"; NM="$PREFIX/bin/$TARGET-nm"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; cd "$W"; FAIL=0

echo "1. IDENTITY";                "$GCC" --version | head -1
echo "   dumpmachine: $("$GCC" -dumpmachine)"
"$GCC" -Q --help=target 2>/dev/null | grep -E '^\s*-(march|mtune|mfpmath)=' | sed 's/^/   /'

echo "2. ELF SHAPE"
printf 'int main(void){return 0;}\n' > h.c
if "$GCC" -O2 h.c -o h 2>h.err; then
  file h | sed 's/^/   /'
  [ "$("$READELF" -l h | awk -F': ' '/interpreter/{print $2}' | tr -d ']')" = "/lib/ld-linux.so.2" ] \
    && echo "   PASS interpreter /lib/ld-linux.so.2" || { echo "   FAIL interpreter"; FAIL=1; }
else
  echo "   FAIL compile+link h.c:"; sed 's/^/     /' h.err; FAIL=1
fi

echo "3. C++17 threads+atomic+string, old ABI"
cat > a.cpp <<'EOF'
#include <string>
#include <thread>
#include <atomic>
#include <iostream>
std::atomic<int> g{0};
int main(){ std::thread t([]{g++;}); t.join(); std::cout<<std::string("ok-")+std::to_string(g)<<"\n"; }
EOF
if "$GXX" -O2 -std=c++17 a.cpp -o a -pthread 2>a.err; then
  echo "   built: $(file a | cut -d, -f1-2)"
else
  echo "   FAIL compile+link a.cpp:"; sed 's/^/     /' a.err; FAIL=1
fi
# Authoritative: let the preprocessor EVALUATE the macro (#if), don't text-expand it.
DEFABI=$(printf '#include <string>\n#if _GLIBCXX_USE_CXX11_ABI\n#error NEW_ABI\n#else\n#error OLD_ABI\n#endif\n' \
         | "$GXX" -x c++ -fsyntax-only - 2>&1 | grep -oE 'OLD_ABI|NEW_ABI')
echo "   default libstdc++ ABI: ${DEFABI:-?} (OLD_ABI = gcc4-compatible / NAOqi)"
[ "$DEFABI" = OLD_ABI ] && echo "   PASS old C++ ABI default" || { echo "   FAIL C++ ABI"; FAIL=1; }
if [ -f a ]; then
  "$NM" -C a 2>/dev/null | grep -q '__cxx11' && { echo "   FAIL __cxx11 symbols present"; FAIL=1; } || echo "   PASS no __cxx11 symbols"
fi

echo "4. glibc ceiling <= 2.13"
for b in h a; do
  [ -f "$b" ] || { echo "   FAIL $b not built"; FAIL=1; continue; }
  MAX=$("$OBJDUMP" -T "$b" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
  BAD=$("$OBJDUMP" -T "$b" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | awk -F_ '{split($2,v,".");if(v[1]>2||(v[1]==2&&v[2]>13))print}')
  [ -z "$BAD" ] && echo "   PASS $b (max ${MAX:-none})" || { echo "   FAIL $b needs $BAD"; FAIL=1; }
done

echo "5. RUN under reused glibc-2.13 loader (no robot)"
if [ "${SKIP_RUN:-0}" = 1 ]; then
  echo "   SKIP (SKIP_RUN=1)"
elif [ ! -f a ]; then
  echo "   FAIL a not built"; FAIL=1
else
  LP="$RT:$PREFIX/$TARGET/lib:$SYSROOT/lib:$SYSROOT/usr/lib"
  OUT=$("$SYSROOT/lib/ld-linux.so.2" --library-path "$LP" ./a 2>run.err); rc=$?
  if [ "$OUT" = "ok-1" ]; then
    echo "   PASS ran: '$OUT'"
  else
    echo "   FAIL ran (exit $rc): stdout='$OUT'"; sed 's/^/     stderr: /' run.err; FAIL=1
  fi
fi

echo
[ "$FAIL" = 0 ] && echo "ALL CHECKS PASSED" || echo "FAILURES: $FAIL"
exit $FAIL
