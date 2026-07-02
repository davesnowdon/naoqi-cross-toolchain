#!/usr/bin/env bash
# Build the grpc_naoqi coexistence demo: a gRPC client module (-std=c++17) and a
# NAOqi module (-std=gnu++11) in ONE binary, with a uniform old libstdc++ ABI.
# Flow: fetch a phrase over gRPC -> speak it via NAOqi.
#
#   MT        = modern toolchain dir (default: <repo>/output/ctc-linux64-atom-2.1.4.14-modern)
#   CTC       = original Aldebaran ctc (NAOqi SDK, libnaoqi/). Optional.
#   GRPC_ROOT = a gRPC install cross-built FOR THE TARGET (has lib/pkgconfig). Optional.
#   PROTOC / GRPC_CPP_PLUGIN = HOST protoc + grpc plugin (only for the real gRPC path).
#
# With neither CTC nor GRPC_ROOT (the CI case) it builds STUB implementations of
# each side and RUNS the binary — still a genuine C++17<->gnu++11 link with old ABI,
# which is the coexistence proof. Real implementations swap in per side when the
# corresponding SDK is present.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
MT="${MT:-$REPO/output/ctc-linux64-atom-2.1.4.14-modern}"
CTC="${CTC:-}"
GRPC_ROOT="${GRPC_ROOT:-}"
PROTOC="${PROTOC:-protoc}"
GRPC_CPP_PLUGIN="${GRPC_CPP_PLUGIN:-grpc_cpp_plugin}"

TARGET=i686-aldebaran-linux-gnu
GXX="$MT/cross/bin/$TARGET-g++"
PKGCONFIG="$MT/cross/bin/$TARGET-pkg-config"
SYSROOT="$MT/cross/$TARGET/sysroot"; RT="$MT/runtime-libs"
SRC="$HERE/src/grpc_naoqi"; BIN="$HERE/bin"; OBJ="$BIN/obj-grpc-naoqi"
rm -rf "$OBJ"; mkdir -p "$BIN" "$OBJ"
[ -x "$GXX" ] || { echo "FATAL: toolchain g++ not found: $GXX (run ./build-toolchain.sh or set MT)" >&2; exit 1; }

CXX17=(-O2 -std=c++17   -I"$SRC")
CXX11=(-O2 -std=gnu++11 -I"$SRC")

echo "== grpc_naoqi coexistence demo =="
"$GXX" --version | head -1

# orchestration TU (only bridge.h) — c++17
"$GXX" "${CXX17[@]}" -c "$SRC/main.cpp" -o "$OBJ/main.o"

# ---- NAOqi side (gnu++11) ----------------------------------------------------
naoqi_real=0; NAOQI_LNK=()
if [ -n "$CTC" ] && [ -d "$CTC/libnaoqi/include" ]; then
  NAOQI="$CTC/libnaoqi"; echo "   NAOqi side: REAL ($NAOQI)"
  "$GXX" "${CXX11[@]}" -I"$NAOQI/include" -I"$NAOQI/include/boost-1_55" \
        -c "$SRC/naoqi_side.cpp" -o "$OBJ/naoqi_side.o"
  NAOQI_LNK=(-L"$NAOQI/lib" -Wl,-rpath-link,"$NAOQI/lib"
             -lalproxies -lalcommon -lalvalue -lalerror -lqimessaging -lqitype -lqi -lrttools
             -lboost_system-mt-1_55 -lboost_thread-mt-1_55 -lboost_signals-mt-1_55
             -lboost_program_options-mt-1_55 -lboost_regex-mt-1_55 -lboost_locale-mt-1_55
             -lboost_chrono-mt-1_55 -lboost_filesystem-mt-1_55 -lboost_date_time-mt-1_55
             -ldl -lrt -lpthread)
  naoqi_real=1
else
  echo "   NAOqi side: stub  (set CTC=/path/to/original-ctc for real ALTextToSpeechProxy)"
  "$GXX" "${CXX11[@]}" -c "$SRC/naoqi_side_stub.cpp" -o "$OBJ/naoqi_side.o"
fi

# ---- gRPC side (c++17) -------------------------------------------------------
grpc_real=0; GRPC_OBJS=("$OBJ/grpc_side.o"); GRPC_LNK=()
if [ -n "$GRPC_ROOT" ]; then
  echo "   gRPC side: REAL (GRPC_ROOT=$GRPC_ROOT)"
  "$PROTOC" -I"$SRC" --cpp_out="$OBJ" "$SRC/speaker.proto"
  "$PROTOC" -I"$SRC" --grpc_out="$OBJ" --plugin=protoc-gen-grpc="$GRPC_CPP_PLUGIN" "$SRC/speaker.proto"
  read -ra GRPC_CFLAGS <<< "$(PKG_CONFIG_PATH="$GRPC_ROOT/lib/pkgconfig" "$PKGCONFIG" --cflags grpc++ 2>/dev/null || true)"
  read -ra GRPC_LIBS   <<< "$(PKG_CONFIG_PATH="$GRPC_ROOT/lib/pkgconfig" "$PKGCONFIG" --libs   grpc++ 2>/dev/null || echo '-lgrpc++ -lgrpc -lgpr -lprotobuf')"
  "$GXX" "${CXX17[@]}" -I"$OBJ" "${GRPC_CFLAGS[@]}" -c "$OBJ/speaker.pb.cc"      -o "$OBJ/speaker.pb.o"
  "$GXX" "${CXX17[@]}" -I"$OBJ" "${GRPC_CFLAGS[@]}" -c "$OBJ/speaker.grpc.pb.cc" -o "$OBJ/speaker.grpc.pb.o"
  "$GXX" "${CXX17[@]}" -I"$OBJ" "${GRPC_CFLAGS[@]}" -c "$SRC/grpc_side.cpp"       -o "$OBJ/grpc_side.o"
  GRPC_OBJS=("$OBJ/speaker.pb.o" "$OBJ/speaker.grpc.pb.o" "$OBJ/grpc_side.o")
  GRPC_LNK=(-L"$GRPC_ROOT/lib" -Wl,-rpath-link,"$GRPC_ROOT/lib" "${GRPC_LIBS[@]}")
  grpc_real=1
else
  echo "   gRPC side: stub  (set GRPC_ROOT=/path/to/target-grpc for the real gRPC client)"
  "$GXX" "${CXX17[@]}" -c "$SRC/grpc_side_stub.cpp" -o "$OBJ/grpc_side.o"
fi

# ---- link the two module-sets into one binary -------------------------------
echo "   linking grpc_naoqi_demo"
"$GXX" -o "$BIN/grpc_naoqi_demo" "$OBJ/main.o" "$OBJ/naoqi_side.o" "${GRPC_OBJS[@]}" \
      "${GRPC_LNK[@]}" "${NAOQI_LNK[@]}"

# ---- coexistence proof: the whole binary is uniformly old-ABI ---------------
OD="$MT/cross/bin/$TARGET-objdump"
cxx11=$("$OD" -T "$BIN/grpc_naoqi_demo" 2>/dev/null | grep -c '__cxx11' || true)
echo "   uniform old C++ ABI check: __cxx11 symbols = $cxx11 (expect 0)"
[ "$cxx11" = 0 ] || { echo "   FAIL: binary mixes old and new libstdc++ ABI" >&2; exit 1; }

# ---- run (only the all-stub build is self-contained: no server/robot needed) --
if [ "$naoqi_real" = 0 ] && [ "$grpc_real" = 0 ] && [ "${SKIP_RUN:-0}" != 1 ]; then
  echo "   running the all-stub demo under the toolchain loader (proves the std::string"
  echo "   returned by the C++17 module survives the call into the gnu++11 module):"
  LP="$RT:$SYSROOT/lib:$SYSROOT/usr/lib"
  "$SYSROOT/lib/ld-linux.so.2" --library-path "$LP" "$BIN/grpc_naoqi_demo" | sed 's/^/     | /'
fi
echo "== done (NAOqi real: $naoqi_real, gRPC real: $grpc_real) -> $BIN/grpc_naoqi_demo =="
