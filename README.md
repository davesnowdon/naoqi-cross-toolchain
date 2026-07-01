# naoqi-cross-toolchain — modern GCC for the NAO robot

Build a **modern GCC 14 cross-toolchain** for the Aldebaran/SoftBank **NAO robot**
that produces binaries which still run unmodified on the robot, and that are tuned
for its Intel Atom Z530 (Bonnell) CPU.

The stock Aldebaran toolchain (`ctc-linux64-atom-2.1.4.13`) ships **GCC 4.5.3
(2011)**, which cannot build modern C++ software — gRPC, Abseil, protobuf and
friends all need C++14/17 and a modern libstdc++. This project gives you a modern
compiler **without breaking ABI compatibility** with the robot.

| | Stock ctc 2.1.4.13 | This toolchain |
|---|---|---|
| GCC / G++ | 4.5.3 | **14.3.0** |
| binutils | 2.21.1 | **2.44** |
| gdb (host) | 7.3 | **16.3** |
| glibc (target) | 2.13 | **2.13 (reused, unchanged)** |
| Linux headers | 2.6.33 | **2.6.33 (reused, unchanged)** |
| Target triple | i686-aldebaran-linux-gnu | i686-aldebaran-linux-gnu |
| Default C++ ABI | pre-C++11 | pre-C++11 (`gcc4-compatible`) |
| Default CPU tuning | generic i686, x87 | **-march=bonnell -mtune=bonnell -mfpmath=sse** |

## How it works

The ABI ceiling that lets a binary run on the robot is **glibc 2.13**. Rebuilding
glibc 2.13 with a modern GCC is fragile and effectively unsupported (crosstool-NG
only reliably supports glibc ≥ ~2.17 — the earlier attempt in this repo's history
foundered exactly there). Instead we **reuse the original toolchain's proven
glibc-2.13 sysroot byte-for-byte** and rebuild only **binutils + GCC (+ host gdb)**
against it. That guarantees an identical glibc ABI while giving a modern compiler.

The minimal reused pieces (a trimmed glibc-2.13 sysroot + the era-appropriate
static `gdbserver`) are vendored in [`vendor/aldebaran-reuse.tar.xz`](vendor/)
(~24 MB). Everything else is built from upstream GNU sources.

See [`docs/design.md`](docs/design.md) for the full ABI rationale and
[`docs/usage.md`](docs/usage.md) for using the result.

## Build it

Prerequisites (Debian/Ubuntu): `build-essential wget xz-utils bzip2 libgmp-dev file`.
On other hosts, override `GMP_INC` / `GMP_LIB` to point at your host GMP.

```sh
./build-toolchain.sh
```

This downloads binutils/GCC/gdb, builds against the vendored sysroot, assembles a
drop-in toolchain under `output/ctc-linux64-atom-2.1.4.14-modern/`, packages it as
`output/ctc-linux64-atom-2.1.4.14-modern.tar.xz`, and self-verifies. ~5–10 min on
a many-core host; ~60–90 min on a 2-core CI runner. Useful env overrides: `OUT`,
`WORK`, `JOBS`, `REUSE_TARBALL`, `GMP_INC`, `GMP_LIB`, `SKIP_VERIFY=1`.

## Use it

Point CMake at the toolchain file that ships inside the built toolchain:

```sh
cmake -S . -B build \
  -DCMAKE_TOOLCHAIN_FILE=output/ctc-linux64-atom-2.1.4.14-modern/cross-config.cmake \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

The compiler **defaults to the old (gcc4-compatible) libstdc++ ABI**, so modern
code — and gRPC/protobuf/abseil built with it — links cleanly against the NAOqi /
boost / Qt / OpenCV libraries in the original ctc. Deploy the matching
`runtime-libs/libstdc++.so.6` (+ `libgcc_s.so.1`) to the robot, or link the C++
runtime statically. Full details, qibuild integration, and remote debugging with
`robot-tools/gdbserver` are in [`docs/usage.md`](docs/usage.md).

## Continuous integration

[`.github/workflows/build-toolchain.yml`](.github/workflows/build-toolchain.yml)
builds and verifies the toolchain. It runs **on demand** (Actions → *Build
toolchain* → *Run workflow*) and **on pushing a `v*` tag**, which additionally
attaches the built `.tar.xz` to a GitHub Release. It does not run on ordinary
pushes/PRs (the build is long).

```sh
git tag v14.3.0-nao1 && git push origin v14.3.0-nao1   # -> builds + publishes a release
```

## Repository layout

```
build-toolchain.sh              reproducible build (sources -> verified tarball)
toolchain-files/                CMake/qibuild integration copied into the built ctc
tests/verify-toolchain.sh       ABI / optimization checks
vendor/aldebaran-reuse.tar.xz   trimmed glibc-2.13 sysroot + static gdbserver (reused)
docs/                           design.md, usage.md, reference/
.github/workflows/              build-toolchain.yml
```

## License & provenance

Project files are GPLv3 (see [LICENSE](LICENSE)). The vendored blob contains
unmodified binaries from the redistributable Aldebaran NAO toolchain (glibc under
LGPL-2.1, GCC runtime under the GCC Runtime Library Exception, gdbserver under
GPL) — see [`vendor/README.md`](vendor/README.md).
