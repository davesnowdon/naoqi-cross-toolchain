#!/usr/bin/env bash
# Build the NAO example programs with the freshly built modern toolchain. Proves
# the toolchain compiles, links and RUNS a real program. Used locally and in CI.
#
#   MT  = modern toolchain dir (default: <repo>/output/ctc-linux64-atom-2.1.4.14-modern,
#         i.e. what ./build-toolchain.sh produces).
#   CTC = original Aldebaran ctc providing the proprietary NAOqi 2.1 SDK (libnaoqi/).
#         OPTIONAL and NOT in this repo. If unset/absent, the NAOqi examples are
#         skipped; the plain example is still built AND run as a smoke test (this
#         is what CI gates on). Set CTC locally to also build say_hello/robot_info.
#
# Exit non-zero if the toolchain cannot build or run the plain example.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
MT="${MT:-$REPO/output/ctc-linux64-atom-2.1.4.14-modern}"
CTC="${CTC:-}"

TARGET=i686-aldebaran-linux-gnu
GXX="$MT/cross/bin/$TARGET-g++"
SYSROOT="$MT/cross/$TARGET/sysroot"
RT="$MT/runtime-libs"
SRC="$HERE/src"; BIN="$HERE/bin"; mkdir -p "$BIN"

[ -x "$GXX" ] || { echo "FATAL: toolchain g++ not found at $GXX" >&2
                   echo "       run ./build-toolchain.sh first, or set MT=<toolchain dir>" >&2; exit 1; }

CXXFLAGS=(-O2 -std=gnu++11)   # old C++ ABI + bonnell tuning are compiler defaults
echo "== compiler =="; "$GXX" --version | head -1

# ---- 1. plain_hello: no NAOqi. Build AND run under the toolchain's own loader --
echo "== plain_hello (no NAOqi) =="
"$GXX" "${CXXFLAGS[@]}" "$SRC/plain_hello.cpp" -o "$BIN/plain_hello"
if [ "${SKIP_RUN:-0}" = 1 ]; then
  echo "   built (SKIP_RUN=1: not executed)"          # for hosts whose sandbox blocks 32-bit exec
else
  LP="$RT:$SYSROOT/lib:$SYSROOT/usr/lib"
  out="$("$SYSROOT/lib/ld-linux.so.2" --library-path "$LP" "$BIN/plain_hello")"
  echo "   ran: $out"
  case "$out" in
    "Hello from the modern NAO cross-toolchain"*) echo "   PASS plain_hello built and ran" ;;
    *) echo "   FAIL plain_hello did not run as expected" >&2; exit 1 ;;
  esac
fi

# ---- 2. NAOqi examples: only when the SDK is available ------------------------
naoqi_built=0
if [ -n "$CTC" ] && [ -d "$CTC/libnaoqi/include" ]; then
  NAOQI="$CTC/libnaoqi"
  echo "== NAOqi examples (SDK: $NAOQI) =="
  NAOQI_INC=(-I"$NAOQI/include" -I"$NAOQI/include/boost-1_55")
  NAOQI_LNK=(-L"$NAOQI/lib" -Wl,-rpath-link,"$NAOQI/lib")
  # Full dependency set from alproxies-config.cmake's *_DEPENDS. Linking the
  # -mt-1_55 files records the plain boost SONAMEs the robot already provides.
  NAOQI_LIBS=(-lalproxies -lalcommon -lalvalue -lalerror -lqimessaging -lqitype -lqi -lrttools
              -lboost_system-mt-1_55 -lboost_thread-mt-1_55 -lboost_signals-mt-1_55
              -lboost_program_options-mt-1_55 -lboost_regex-mt-1_55 -lboost_locale-mt-1_55
              -lboost_chrono-mt-1_55 -lboost_filesystem-mt-1_55 -lboost_date_time-mt-1_55
              -ldl -lrt -lpthread)
  for ex in say_hello robot_info; do
    echo "   $ex"
    "$GXX" "${CXXFLAGS[@]}" "${NAOQI_INC[@]}" "$SRC/$ex.cpp" -o "$BIN/$ex" \
          "${NAOQI_LNK[@]}" "${NAOQI_LIBS[@]}"
  done
  naoqi_built=1
else
  echo "== NAOqi examples SKIPPED =="
  echo "   (no NAOqi SDK; set CTC=/path/to/original-ctc to build say_hello/robot_info)"
fi

# ---- 3. assemble a deploy bundle (binaries + newer C++ runtime + launcher) ----
if [ -d "$RT" ]; then
  DEPLOY="$HERE/deploy/nao-modern-examples"; rm -rf "$DEPLOY"; mkdir -p "$DEPLOY/bin" "$DEPLOY/lib"
  cp -a "$BIN/." "$DEPLOY/bin/"
  cp -a "$RT/libstdc++.so.6" "$RT"/libstdc++.so.6.* "$RT/libgcc_s.so.1" "$DEPLOY/lib/" 2>/dev/null || true
  cp -a "$HERE/run.sh" "$DEPLOY/run.sh"
  [ -f "$HERE/DEPLOY.md" ] && cp -a "$HERE/DEPLOY.md" "$DEPLOY/DEPLOY.md"
  chmod +x "$DEPLOY/run.sh" "$DEPLOY/bin/"*
  echo "== deploy bundle -> $DEPLOY (scp to the robot; see DEPLOY.md) =="
fi

echo "== done (NAOqi examples built: $naoqi_built) =="
ls -l "$BIN"
