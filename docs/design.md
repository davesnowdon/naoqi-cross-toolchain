# Design & ABI rationale

## The problem

The NAO ships with Aldebaran's `ctc-linux64-atom-2.1.4.13` cross toolchain:
GCC 4.5.3 / binutils 2.21.1 / glibc 2.13 / Linux headers 2.6.33, target
`i686-aldebaran-linux-gnu`. GCC 4.5 (2011) predates C++11's finalization and
cannot build modern C++ (gRPC/abseil/protobuf need C++14/17 and a modern
libstdc++). We want a modern compiler whose output still runs on the robot.

## Why we reuse the sysroot instead of rebuilding glibc

What actually makes a binary runnable on the robot is the **glibc version** it was
linked against — the robot's rootfs provides **glibc 2.13**, so binaries must not
reference symbols newer than `GLIBC_2.13`.

Rebuilding glibc 2.13 from source with a modern GCC is fragile: modern crosstool-NG
only reliably supports glibc ≥ ~2.17, and 2011-era glibc does not build cleanly
with a 2024 compiler (the earlier crosstool-NG attempt in this repo's history hit
exactly this — its "support make 4" glibc patch is committed as *does not work*).

So we take the standard "modern GCC for an old target" path: **keep the original
toolchain's proven glibc-2.13 sysroot byte-for-byte** and rebuild only binutils,
GCC and host gdb against it (`--with-sysroot=<that sysroot>` and
`--with-glibc-version=2.13`). The glibc ABI is therefore *identical* — it is the
same binaries.

The reused sysroot is vendored (trimmed of the redundant `lib32`/`lib64`
duplicates, which a single-arch `-m32` toolchain never touches) in
`vendor/aldebaran-reuse.tar.xz`, together with the robot `gdbserver`.

## ABI invariants preserved

| Invariant | Value |
|---|---|
| Target triple | `i686-aldebaran-linux-gnu` |
| psABI | 32-bit i386 System V (x87 float return, 80-bit `long double`) |
| Dynamic linker | `/lib/ld-linux.so.2` |
| glibc symbol ceiling | `GLIBC_2.13` |
| C atexit | `--enable-__cxa_atexit` |
| C++ std lib ABI | pre-C++11 (`std::basic_string`, `GLIBCXX_3.4.14`) |

These are asserted by `tests/verify-toolchain.sh` on every build (see below).

## The C++ ABI choice

GCC 5 introduced a new libstdc++ `std::string`/`std::list` ABI
(`std::__cxx11::`). The NAOqi SDK and the bundled boost/Qt/OpenCV in the original
ctc were built with the **old** (pre-GCC5) ABI. If we linked new code with the new
ABI against those libraries we'd get `undefined reference to std::__cxx11::...`.

So this toolchain is configured with `--with-default-libstdcxx-abi=gcc4-compatible`:
the compiler **defaults to the old ABI** (`_GLIBCXX_USE_CXX11_ABI=0`), and
gRPC/protobuf/abseil built with it link cleanly against the existing NAOqi
libraries. The library is still dual-ABI, so a fully standalone component can opt
into the new ABI per target with `-D_GLIBCXX_USE_CXX11_ABI=1`.

The new `libstdc++.so.6.0.33` is a **backward-compatible superset**: it exports
GLIBCXX symbols up to 3.4.33 *and* the NAOqi-era 3.4.14, and only needs
`GLIBC_2.6`, so it runs on the robot and also satisfies existing robot binaries.

## Atom optimization

The NAO's Atom Z530 (Bonnell) supports MMX/SSE/SSE2/SSE3/SSSE3 **and MOVBE** (but
not SSE4). The compiler defaults to `-march=bonnell -mtune=bonnell -mfpmath=sse`,
so even plain `gcc` and the runtime libraries are Atom-tuned. This is ABI-safe on
i386 (scalar FP still returns via x87). Output therefore requires an SSSE3-capable
CPU (fine for NAO); for portable non-Atom i686 output use `-march=i686 -mtune=bonnell`
or `-DOPTIMIZE_FOR_TARGET=GENERIC` with the CMake toolchain file.

## gdbserver

Modern gdbserver (16.x) x86 native code needs `PTRACE_GETREGSET` / xstate
constants introduced in Linux 2.6.34; the NAO's kernel and sysroot headers are
2.6.33, so a modern gdbserver can neither be built nor run correctly on the robot.
We therefore reuse the **era-appropriate static gdbserver** from the original ctc
(built for GNU/Linux 2.6.33). The modern host `i686-aldebaran-linux-gnu-gdb` drives
it fine — gdb's remote protocol is backward compatible.

## What the build produces & verifies

`build-toolchain.sh` outputs a drop-in `ctc-linux64-atom-2.1.4.14-modern/` tree
(same layout as the original: `cross/` + `cross-config.cmake` + `toolchain*.cmake`
+ `toolchain.xml`), plus `runtime-libs/` (deployable libstdc++/libgcc_s/…) and
`robot-tools/gdbserver`, packaged as a `.tar.xz`.

`tests/verify-toolchain.sh` then checks, on the freshly built compiler:

1. identity + default `-march/-mtune/-mfpmath` (bonnell/bonnell/sse);
2. ELF is 32-bit i386 with interpreter `/lib/ld-linux.so.2`;
3. a threaded C++17 program uses the **old** ABI (no `std::__cxx11::`);
4. every produced binary requires **no glibc symbol newer than 2.13**;
5. the binary **runs** under the reused glibc-2.13 loader on the build host (no
   robot needed).

These were validated end-to-end, and the toolchain has cross-built Abseil and
protobuf (core gRPC dependencies) — libraries GCC 4.5 cannot compile at all.
