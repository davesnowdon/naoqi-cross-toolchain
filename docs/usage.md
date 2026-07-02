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

### Combining gRPC and NAOqi in one binary

You can put modern-gRPC code and NAOqi code in the **same executable**, but two
independent constraints drive the design:

1. **Language standard is per–translation-unit and the two sides disagree.** The
   NAOqi 2.1 / boost 1.55 headers **do not compile under C++17** (GCC 14's default)
   — they use `std::auto_ptr` / `std::unary_function`, removed in C++17 — so NAOqi
   code must be compiled `-std=gnu++11`. Modern gRPC/abseil need `-std=c++17`.
   → **Never `#include` NAOqi headers and gRPC/abseil headers in the same `.cpp`.**
   Splitting by module (as you suspected) is therefore *necessary*.

2. **The libstdc++ ABI is whole-binary and must be uniform.** Keep the toolchain's
   default **old ABI (`_GLIBCXX_USE_CXX11_ABI=0`) everywhere** — including when you
   build gRPC, abseil, protobuf, re2, c-ares, zlib. Because every TU then shares the
   same `std::string`/container layout, the two module-sets interoperate freely
   (you can even pass `std::string` across the boundary). Verify the final binary
   has **zero `__cxx11` symbols** (`objdump -T app | grep __cxx11`).

Recommended shape — a thin ABI-neutral bridge:

```
bridge.h        // plain funcs / POD / std::string only; compiles under BOTH standards
naoqi_side.cpp  // -std=gnu++11 ; #includes NAOqi headers + bridge.h
grpc_side.cpp   // -std=c++17   ; #includes gRPC/abseil headers + bridge.h
main.cpp        // orchestration; #includes bridge.h only
```

Link the objects together normally. This is *sufficient* provided you also handle:

- **Build abseil and your gRPC-side TUs with the same `-std`/flags.** abseil's ABI
  changes with the C++ standard (e.g. `absl::string_view` aliases
  `std::string_view` under C++17); mixing standards across abseil users is an ODR
  trap. Pick C++17 for the whole gRPC side.
- **Duplicate third-party libraries.** NAOqi bundles OpenSSL (and boost); gRPC
  brings BoringSSL/OpenSSL (and protobuf). Two copies of the same library's symbols
  in one process can crash. Prefer static-linking gRPC's deps with hidden
  visibility (`-fvisibility=hidden`, `-Wl,--exclude-libs,ALL`) so they don't
  collide with the robot's copies.
- **Runtime kernel limits (2.6.33)** — see *Caveats* below; gRPC in particular
  needs `SO_REUSEPORT` disabled.

If the in-process ABI juggling gets fragile, the robust alternative is **two
processes**: a modern-gRPC binary and a NAOqi binary that talk over a local socket
/ pipe. Each process is its own ABI world, so nothing above applies — at the cost
of an IPC hop.

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

### Old kernel (Linux 2.6.33) — a runtime ceiling, not a build one

NAO V4/V5 run Linux **2.6.33**, and the reused sysroot's headers match. Features
added to later kernels are simply absent at runtime (and some constants are not even
defined in the headers). This is a property of the *robot*, not the toolchain — the
toolchain will happily build code that then fails at runtime on the robot.

The one that bites gRPC users:

- **`SO_REUSEPORT`** was added in Linux **3.9**. It is not defined in the 2.6.33
  headers (there is literally a `/* To add :#define SO_REUSEPORT 15 */` in
  `asm-generic/socket.h`). Software that references it either fails to compile
  (undefined constant) or, if it self-defines it (gRPC does, value 15),
  `setsockopt(...SO_REUSEPORT...)` returns **`ENOPROTOOPT`** at runtime.
  - **gRPC workaround:** disable it via the channel arg `GRPC_ARG_ALLOW_REUSEPORT`
    (`"grpc.so_reuseport"`) set to `0`, on both server and client:
    ```cpp
    // server
    grpc::ServerBuilder b;
    b.AddChannelArgument(GRPC_ARG_ALLOW_REUSEPORT, 0);

    // client (as the grpc_naoqi example's grpc_side.cpp does)
    grpc::ChannelArguments args;
    args.SetInt(GRPC_ARG_ALLOW_REUSEPORT, 0);
    auto channel = grpc::CreateCustomChannel(addr, creds, args);
    ```
  - **General code:** guard the call and treat `ENOPROTOOPT` as "not supported"; for
    a single listener you don't need `SO_REUSEPORT` at all (`SO_REUSEADDR` exists).

Other post-2.6.33 gaps to expect if you pull in modern networking/crypto:
`TCP_USER_TIMEOUT` (3.7 — also not in the headers; gRPC keepalive uses it),
`sendmmsg` (3.0), and `getrandom` (3.17 — BoringSSL/abseil fall back to
`/dev/urandom`). Audit `setsockopt`/syscall use, or run under `strace` on the robot
to find `ENOSYS`/`ENOPROTOOPT`.

### Other

- Sanitizers (asan/tsan) are disabled for this target.
- `-march=bonnell` output requires SSSE3+MOVBE (present on NAO Z530, not on plain
  i686).
