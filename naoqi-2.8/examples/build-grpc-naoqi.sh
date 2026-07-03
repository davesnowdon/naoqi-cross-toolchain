#!/usr/bin/env bash
# Build the NAO6 grpc_naoqi demo: a modern gRPC client and NAOqi 2.8 (qi API) in
# ONE binary — fetch a phrase over gRPC, speak it via qi's ALTextToSpeech.
#
#   MT            = toolchain dir (default: <tree>/output/ctc-linux64-nao6-2.8-modern)
#   ROBOT_SYSROOT = robot app sysroot (make-robot-sysroot.sh). Optional.
#   GRPC_ROOT     = gRPC cross-built FOR THIS TARGET (lib/pkgconfig). Optional.
#   PROTOC / GRPC_CPP_PLUGIN = HOST protoc + grpc plugin (real gRPC path only).
#   SKIP_RUN=1    = skip running the all-stub binary.
#
# With neither env set (the CI case) both sides are stubs — still a genuine
# two-module link, built and RUN. Real sides swap in per side when present.
# v6 note: everything is -std=gnu++17 / new ABI (no 2.1-style standards split);
# the module split is kept so gRPC and qi headers never share a TU.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="$(cd "$HERE/.." && pwd)"
MT="${MT:-$TREE/output/ctc-linux64-nao6-2.8-modern}"
ROBOT_SYSROOT="${ROBOT_SYSROOT:-}"
GRPC_ROOT="${GRPC_ROOT:-}"
PROTOC="${PROTOC:-protoc}"
GRPC_CPP_PLUGIN="${GRPC_CPP_PLUGIN:-grpc_cpp_plugin}"
PKG_CONFIG="${PKG_CONFIG:-pkg-config}"

TARGET=i686-nao6-linux-gnu
GXX="$MT/cross/bin/$TARGET-g++"
SYSROOT="$MT/cross/$TARGET/sysroot"; RT="$MT/runtime-libs"
SRC="$HERE/src/grpc_naoqi_v6"; BIN="$HERE/bin"; OBJ="$BIN/obj-grpc-naoqi"
rm -rf "$OBJ"; mkdir -p "$BIN" "$OBJ"
[ -x "$GXX" ] || { echo "FATAL: toolchain g++ not found: $GXX" >&2; exit 1; }

CXX=(-O2 -std=gnu++17 -I"$SRC")

echo "== grpc_naoqi demo (NAO6) =="
"$GXX" --version | head -1
"$GXX" "${CXX[@]}" -c "$SRC/main.cpp" -o "$OBJ/main.o"

# ---- NAOqi side (qi framework) ------------------------------------------------
naoqi_real=0; NAOQI_LNK=()
if [ -n "$ROBOT_SYSROOT" ] && [ -f "$ROBOT_SYSROOT/opt/aldebaran/include/qi/session.hpp" ]; then
  echo "   NAOqi side: REAL (qi framework, $ROBOT_SYSROOT)"
  "$GXX" "${CXX[@]}" --sysroot="$ROBOT_SYSROOT" \
        -I"$ROBOT_SYSROOT/opt/aldebaran/include" \
        -c "$SRC/naoqi_side_v6.cpp" -o "$OBJ/naoqi_side.o"
  # --sysroot on the LINK too: Debian's libc.so linker script has absolute
  # multiarch paths that ld only re-roots for scripts inside the active sysroot.
  NAOQI_LNK=(--sysroot="$ROBOT_SYSROOT"
             -L"$ROBOT_SYSROOT/opt/aldebaran/lib"
             -Wl,-rpath-link,"$ROBOT_SYSROOT/opt/aldebaran/lib"
             -lqi -lboost_thread -lboost_system -lboost_chrono)
  naoqi_real=1
else
  echo "   NAOqi side: stub  (set ROBOT_SYSROOT= for the real qi TTS call)"
  "$GXX" "${CXX[@]}" -c "$SRC/naoqi_side_stub.cpp" -o "$OBJ/naoqi_side.o"
fi

# ---- gRPC side ------------------------------------------------------------------
grpc_real=0; GRPC_OBJS=("$OBJ/grpc_side.o"); GRPC_LNK=()
if [ -n "$GRPC_ROOT" ]; then
  echo "   gRPC side: REAL (GRPC_ROOT=$GRPC_ROOT)"
  "$PROTOC" -I"$SRC" --cpp_out="$OBJ" "$SRC/speaker.proto"
  "$PROTOC" -I"$SRC" --grpc_out="$OBJ" --plugin=protoc-gen-grpc="$GRPC_CPP_PLUGIN" "$SRC/speaker.proto"
  # Plain HOST pkg-config, no sysroot rewriting; query protobuf explicitly and
  # link the static closure in a group (see naoqi-2.1's script for the history).
  gpc() { PKG_CONFIG_PATH="$GRPC_ROOT/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="" "$PKG_CONFIG" --static "$@"; }
  read -ra GRPC_CFLAGS <<< "$(gpc --cflags grpc++ protobuf 2>/dev/null || true)"
  read -ra GRPC_LIBS   <<< "$(gpc --libs   grpc++ protobuf 2>/dev/null || echo '-lgrpc++ -lgrpc -lgpr -lprotobuf')"
  "$GXX" "${CXX[@]}" -I"$OBJ" "${GRPC_CFLAGS[@]}" -c "$OBJ/speaker.pb.cc"      -o "$OBJ/speaker.pb.o"
  "$GXX" "${CXX[@]}" -I"$OBJ" "${GRPC_CFLAGS[@]}" -c "$OBJ/speaker.grpc.pb.cc" -o "$OBJ/speaker.grpc.pb.o"
  "$GXX" "${CXX[@]}" -I"$OBJ" "${GRPC_CFLAGS[@]}" -c "$SRC/grpc_side.cpp"       -o "$OBJ/grpc_side.o"
  GRPC_OBJS=("$OBJ/speaker.pb.o" "$OBJ/speaker.grpc.pb.o" "$OBJ/grpc_side.o")
  GRPC_LNK=(-L"$GRPC_ROOT/lib" -Wl,--start-group "${GRPC_LIBS[@]}" -Wl,--end-group
            -lpthread -ldl -lm)
  grpc_real=1
else
  echo "   gRPC side: stub  (set GRPC_ROOT=/path/to/target-grpc for the real client)"
  "$GXX" "${CXX[@]}" -c "$SRC/grpc_side_stub.cpp" -o "$OBJ/grpc_side.o"
fi

echo "   linking grpc_naoqi_demo_v6"
"$GXX" -o "$BIN/grpc_naoqi_demo_v6" "$OBJ/main.o" "$OBJ/naoqi_side.o" "${GRPC_OBJS[@]}" \
      "${GRPC_LNK[@]}" "${NAOQI_LNK[@]}"

# ---- checks: new ABI present, glibc within the robot's 2.28 --------------------
OD="$MT/cross/bin/$TARGET-objdump"; NM="$MT/cross/bin/$TARGET-nm"
DEMO="$BIN/grpc_naoqi_demo_v6"
cxx11=$({ "$NM" -C "$DEMO" 2>/dev/null; "$OD" -T "$DEMO" 2>/dev/null; } | grep -c '__cxx11' || true)
maxglibc=$("$OD" -T "$DEMO" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
echo "   ABI/glibc: __cxx11 = $cxx11 (expect > 0, NAOqi 2.8 is new-ABI); max glibc = ${maxglibc:-none}"
[ "$cxx11" -gt 0 ] || { echo "   FAIL: no __cxx11 — wrong ABI for NAOqi 2.8" >&2; exit 1; }
if [ -n "$maxglibc" ] && \
   [ "$(printf '%s\nGLIBC_2.28\n' "$maxglibc" | sort -V | tail -1)" != "GLIBC_2.28" ]; then
  echo "   FAIL: needs $maxglibc, newer than the robot's glibc 2.28" >&2; exit 1
fi

# ---- run (all-stub only: self-contained) ---------------------------------------
if [ "$naoqi_real" = 0 ] && [ "$grpc_real" = 0 ] && [ "${SKIP_RUN:-0}" != 1 ]; then
  echo "   running the all-stub demo under the toolchain loader:"
  "$SYSROOT/lib/ld-linux.so.2" --library-path "$RT:$SYSROOT/lib:$SYSROOT/usr/lib" \
    "$BIN/grpc_naoqi_demo_v6" | sed 's/^/     | /'
fi

# ---- add to the deploy bundle (if build-examples.sh has assembled it) -----------
# run.sh's `grpc` mode expects bin/grpc_naoqi_demo_v6; keep the tarball in sync.
DEP="$HERE/deploy/nao6-modern-examples"
if [ -d "$DEP/bin" ]; then
  cp "$BIN/grpc_naoqi_demo_v6" "$DEP/bin/"
  ( cd "$HERE/deploy" && tar czf nao6-modern-examples.tar.gz nao6-modern-examples )
  echo "   added to deploy bundle: $DEP/bin/grpc_naoqi_demo_v6"
fi
echo "== done (NAOqi real: $naoqi_real, gRPC real: $grpc_real) -> $BIN/grpc_naoqi_demo_v6 =="
