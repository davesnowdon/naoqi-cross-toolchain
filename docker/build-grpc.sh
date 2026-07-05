#!/usr/bin/env bash
# build-grpc.sh <host|v5|v6> <grpc-src-dir> <install-prefix>
#
# Builds gRPC (static, Release) for the NAO builder images:
#   host — native, WITH protoc + grpc_cpp_plugin (codegen tools for cross builds)
#   v5   — i686 old-ABI glibc-2.13 via /opt/nao/ctc-2.1 (needs two glibc-2.13
#          accommodations: static_assert shim for C sources, explicit -lrt for
#          clock_gettime which only moved into libc at glibc 2.17)
#   v6   — i686 new-ABI glibc-2.28 via /opt/nao/ctc-2.8 (builds unpatched)
#
# Cross builds consume the HOST tools from /opt/nao/grpc/host, so build host
# first. Recipes proven on real NAO V4/V5/V6 robots (see the grpc_naoqi
# examples in this repo and the robot-companion project).
set -euo pipefail

TARGET="${1:?usage: build-grpc.sh <host|v5|v6> <grpc-src> <prefix>}"
SRC="${2:?}"
PREFIX="${3:?}"
HOSTP=/opt/nao/grpc/host
B="/tmp/grpc-build-$TARGET"
JOBS="$(nproc)"

COMMON=(
  -DCMAKE_BUILD_TYPE=Release
  -DgRPC_BUILD_TESTS=OFF
  -DABSL_PROPAGATE_CXX_STD=ON
  -DgRPC_INSTALL=ON
  "-DCMAKE_INSTALL_PREFIX=$PREFIX"
)
# Cross targets: no codegen — protoc/plugins can't run on the build host as
# i686 binaries; the host install provides them.
CROSS=(
  -DgRPC_BUILD_CODEGEN=OFF
  -DgRPC_BUILD_GRPC_CPP_PLUGIN=OFF
  -DgRPC_BUILD_GRPC_CSHARP_PLUGIN=OFF
  -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF
  -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF
  -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF
  -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF
  -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF
  "-Dprotobuf_PROTOC_EXECUTABLE=$HOSTP/bin/protoc"
  "-D_gRPC_PROTOBUF_PROTOC_EXECUTABLE=$HOSTP/bin/protoc"
  "-D_gRPC_CPP_PLUGIN=$HOSTP/bin/grpc_cpp_plugin"
)

case "$TARGET" in
  host)
    cmake -S "$SRC" -B "$B" -G Ninja "${COMMON[@]}"
    ;;
  v5)
    [ -x "$HOSTP/bin/protoc" ] || { echo "host grpc missing at $HOSTP" >&2; exit 1; }
    cmake -S "$SRC" -B "$B" -G Ninja "${COMMON[@]}" "${CROSS[@]}" \
      -DCMAKE_TOOLCHAIN_FILE=/opt/nao/ctc-2.1/cross-config.cmake \
      -DCMAKE_C_FLAGS="-Dstatic_assert=_Static_assert" \
      -DCMAKE_C_STANDARD_LIBRARIES="-lrt" \
      -DCMAKE_CXX_STANDARD_LIBRARIES="-lrt"
    ;;
  v6)
    [ -x "$HOSTP/bin/protoc" ] || { echo "host grpc missing at $HOSTP" >&2; exit 1; }
    cmake -S "$SRC" -B "$B" -G Ninja "${COMMON[@]}" "${CROSS[@]}" \
      -DCMAKE_TOOLCHAIN_FILE=/opt/nao/ctc-2.8/cross-config.cmake
    ;;
  *) echo "unknown target: $TARGET" >&2; exit 2 ;;
esac

cmake --build "$B" -j"$JOBS" --target install
rm -rf "$B"

# gRPC installs no .pc files for its bundled re2/zlib/boringssl, yet
# grpc++.pc Requires.private's them; shim what's missing so pkg-config
# consumers (e.g. robot-companion's TargetGrpc.cmake) resolve statically.
# ALL targets including host: on dev boxes the system dev packages mask a
# missing host shim, in a clean container nothing does.
mkdir -p "$PREFIX/lib/pkgconfig"
for spec in "re2:-lre2" "zlib:-lz" "openssl:-lssl -lcrypto"; do
  name="${spec%%:*}" libs="${spec#*:}"
  [ -f "$PREFIX/lib/pkgconfig/$name.pc" ] && continue
  printf 'prefix=%s\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: %s\nDescription: gRPC bundled dep shim\nVersion: 0\nLibs: -L${libdir} %s\nCflags: -I${includedir}\n' \
    "$PREFIX" "$name" "$libs" > "$PREFIX/lib/pkgconfig/$name.pc"
done

echo "== gRPC $TARGET installed -> $PREFIX =="
