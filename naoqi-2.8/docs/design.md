# naoqi-2.8 toolchain — design notes

## The discovery that shaped everything: stock NAO V6 is 32-bit

Received wisdom says "NAO V6 is 64-bit". Measured reality (sysroot rsync'd from a
real V6 running NAOqi 2.8.7.4):

- `lib/`: 85 ELF32 libraries, 0 ELF64. `opt/aldebaran/lib`: **363 ELF32, 0 ELF64**.
- `libqi.so` is ELF 32-bit; its NEEDED list ends at `ld-linux.so.2` (the 32-bit loader).
- glibc is 2.28 (32-bit `libc-2.28.so`), libstdc++ is 6.0.25 (GCC 8 era),
  boost is 1.64 — all i686.

The V6's Atom E3845 and kernel are 64-bit; SoftBank simply kept the userland
32-bit. The widely-quoted x86_64 target belongs to **B-Human's replacement
runtime**, not the stock robot. Anything that must link `libqi`/NAOqi 2.8 must be
**i686, glibc ≤ 2.28, new C++11 ABI** (NAOqi 2.8 libs export `__cxx11` symbols:
libqi 465, libalproxies 2346).

## Consequences for the toolchain

| Decision | Why |
|---|---|
| target `i686-nao6-linux-gnu` | stock userland is i686 (above) |
| `--with-arch/tune=silvermont` | V6's E3845 is Silvermont. **V6 only** — Silvermont binaries SIGILL on V4/V5 (Bonnell) |
| default **new** C++11 ABI (no `--with-default-libstdcxx-abi` flag) | NAOqi 2.8 is `__cxx11`; the 2.1 toolchain's old-ABI default would not link |
| `--with-glibc-version=2.28` + Debian 10 sysroot | the robot's exact glibc version |
| ship `runtime-libs/` (libstdc++ 6.0.33, 32-bit) | GCC-14 binaries reference `GLIBCXX_3.4.32` > robot's 3.4.25 — same deploy trick as naoqi-2.1 |

## Why the build sysroot is public (and 2.1's is vendored)

The toolchain build needs target glibc headers + libs + CRT. For 2.1 those had to
come from the unobtainable-era Aldebaran ctc (hence the vendored trimmed blob).
For 2.8 the robot's glibc is **2.28 — exactly Debian 10** ("Buster", also GCC 8,
matching the robot's libstdc++ 6.0.25). So the build sysroot is assembled from
checksum-pinned debs off `archive.debian.org`:

- `libc6-dev` / `libc6` 2.28-10+deb10u1 (i386) — headers, CRT, linker inputs, loader
- `linux-libc-dev` 4.19 (i386) — kernel headers

Nothing proprietary: **CI builds and verifies this toolchain from scratch.** The
NAOqi 2.8 stack itself (needed only to build the NAOqi examples) is rsync'd from
*your* robot by `sysroot-tools/make-robot-sysroot.sh` — the robot image is a
runtime with no dev files, so the same Debian overlay (plus boost 1.64 headers,
which the robot also lacks) is applied on top of the rsync.

### Sysroot assembly traps (fixed in `sysroot-tools/overlay-lib.sh`)

1. **Debian's dev symlinks are absolute** (`libpthread.so → /lib/i386-linux-gnu/libpthread.so.0`).
   At link time the OS resolves them against the **host** filesystem — on a modern
   host, `-lpthread` silently linked Ubuntu's *placeholder* libpthread (no
   `pthread_create`). All absolute symlinks are rewritten to resolve in-sysroot.
2. Debian linker scripts reference multiarch paths (`/lib/i386-linux-gnu/libc.so.6`);
   the robot layout is flat — bridged with targeted symlinks.
3. The robot ships no unversioned `.so` names (`libboost_thread.so` etc.) — created
   for every boost/ssl/systemd runtime lib.

## Verification (inverted ABI check!)

`tests/verify-toolchain.sh` asserts: GCC 14.x identity; ELF32/i386 +
`/lib/ld-linux.so.2`; glibc ceiling ≤ 2.28; **`__cxx11` symbols PRESENT** (the
2.1 verifier asserts the opposite!); binary's GLIBCXX ceiling covered by the
shipped `runtime-libs`; and the probe **runs** under the sysroot's own
glibc-2.28 loader.

## Scope

NAO **V6** with the **stock** NAOqi 2.8 image. Not V4/V5 (that's
[`../naoqi-2.1/`](../naoqi-2.1/)); not the B-Human runtime (x86_64 — B-Human
ships its own buildchain).
