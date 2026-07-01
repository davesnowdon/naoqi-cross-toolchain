# Using the toolchain

After `./build-toolchain.sh`, the toolchain lives at
`output/ctc-linux64-atom-2.1.4.14-modern/` (also packaged as `…/….tar.xz`). Unpack
the tarball wherever you like — it is relocatable.

```
cross/                         the toolchain (bin/, libexec/, lib/, sysroot)
  bin/i686-aldebaran-linux-gnu-{gcc,g++,gdb,ld,...}
  i686-aldebaran-linux-gnu/sysroot/     reused glibc-2.13 sysroot
cross-config.cmake             CMake toolchain file (drop-in)
toolchain.cmake / -atom.cmake  qibuild entry points
toolchain.xml                  qitoolchain manifest
runtime-libs/                  libstdc++.so.6 / libgcc_s / libatomic / libgomp
robot-tools/gdbserver          era-appropriate static gdbserver for the robot
tests/verify-toolchain.sh
```

## Plain compiler

```sh
cross/bin/i686-aldebaran-linux-gnu-g++ -O2 -std=c++17 app.cpp -o app
```

## CMake (any modern project, incl. gRPC / protobuf / abseil)

```sh
cmake -S . -B build \
  -DCMAKE_TOOLCHAIN_FILE=/path/to/ctc/cross-config.cmake \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

Dependencies you cross-build into a staging prefix are found via
`-DCMAKE_PREFIX_PATH=/path/to/stage`. The toolchain file defaults to the old C++
ABI, so gRPC/protobuf/abseil built through it are ABI-compatible with the NAO's
existing C++ libraries.

> **This toolchain bundles only the compiler + glibc-2.13 sysroot — not NAOqi,
> boost, Qt or OpenCV.** To build/link against those, point at the copies in the
> **original Aldebaran ctc** — e.g. add them to `CMAKE_PREFIX_PATH`, or overlay
> this `cross/` directory into a copy of the original ctc so its bundled packages
> sit alongside. The old-ABI default is what makes that linking work.

`.pc` files inside the sysroot are resolved by the generated
`cross/bin/i686-aldebaran-linux-gnu-pkg-config` wrapper (it sets
`PKG_CONFIG_SYSROOT_DIR`/`PKG_CONFIG_LIBDIR` and delegates to the host
`pkg-config`); `cross-config.cmake` wires it into `pkg_check_modules`.

### Cross-building gRPC

gRPC pulls in abseil, protobuf, c-ares, re2 and zlib. The pattern:

1. Build a **host** gRPC/protobuf to get `protoc` + `grpc_cpp_plugin` (codegen runs
   on the host).
2. Cross-build gRPC and its deps for the target with the `cross-config.cmake`
   toolchain file, provider options set to `package`, `-DCMAKE_PREFIX_PATH` pointing
   at your cross-built abseil/protobuf, and the gRPC `protoc`/plugin variables
   pointed at the host binaries.

Abseil and protobuf are verified to cross-build with this toolchain out of the box.

## qibuild / qitoolchain

```sh
qitoolchain create nao-modern /path/to/ctc/toolchain.xml
qibuild configure -c nao-modern
```

`toolchain.xml` registers the **cross compiler + sysroot** only (it deliberately
does not list NAOqi/boost/Qt/OpenCV packages, which this artifact does not ship).
To build a project that needs the NAO libraries, also feed qibuild the original
ctc's packages — the simplest route is to overlay this `cross/` directory into a
copy of the original Aldebaran ctc and register that ctc's `toolchain.xml`, which
already lists them.

## C++ ABI switch

Default is the old (gcc4-compatible) ABI for NAOqi compatibility. For a fully
standalone component that does not link the old NAOqi C++ libraries you may opt
into the modern ABI per target: `-D_GLIBCXX_USE_CXX11_ABI=1`.

## Deploying the C++ runtime to the robot

Modern C++ output needs the newer `libstdc++.so.6` at runtime (the robot's stock
`6.0.14` is too old). The new one is backward compatible and only needs glibc 2.13,
so it serves both new and existing binaries:

```sh
scp runtime-libs/libstdc++.so.6* runtime-libs/libgcc_s.so.1 nao@robot:/opt/naomodern/lib/
# run with:   LD_LIBRARY_PATH=/opt/naomodern/lib ./your_app
# or link:    -Wl,-rpath,/opt/naomodern/lib
```

Alternatively link statically: `-static-libstdc++ -static-libgcc`.

## Remote debugging

On the robot:

```sh
./gdbserver :2345 ./your_app          # robot-tools/gdbserver, deployed to the robot
```

On the host:

```sh
cross/bin/i686-aldebaran-linux-gnu-gdb ./your_app
(gdb) target remote robot:2345
```

## Verifying a build

```sh
tests/verify-toolchain.sh             # expects: ALL CHECKS PASSED
```

Checks identity, ELF32 + `/lib/ld-linux.so.2`, glibc ceiling ≤ 2.13, old C++ ABI
default, and that a freshly compiled binary runs under the reused glibc-2.13 loader.

## Caveats

- **Old kernel (2.6.33):** some modern libraries assume newer *runtime* syscalls
  (e.g. `SO_REUSEPORT` needs Linux 3.9). That's a property of the software you
  build, not of the toolchain.
- Sanitizers (asan/tsan) are disabled for this target.
- `-march=bonnell` output requires SSSE3+MOVBE (present on NAO Z530, not on plain
  i686).
