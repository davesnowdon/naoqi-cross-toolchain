# Examples — building real NAO programs with the toolchain

These programs demonstrate (and, in CI, **gate**) that the modern toolchain builds
C/C++ that runs on the robot and interoperates with the NAOqi 2.1 C++ SDK. They
target **NAO V4 and V5** (NAOqi 2.1.x, 32-bit Intel Atom, glibc 2.13).

| Source | Demonstrates | NAOqi SDK? |
|---|---|---|
| `src/plain_hello.cpp` | Toolchain output runs on the bare robot OS (`std::string`) | no |
| `src/say_hello.cpp`   | Canonical NAOqi example — `ALTextToSpeechProxy::say()` | yes |
| `src/robot_info.cpp`  | Read-only `ALSystemProxy` + TTS getters | yes |

## Building

```sh
# after ./build-toolchain.sh has produced output/ctc-linux64-atom-2.1.4.14-modern
./examples/build-examples.sh
```

- **`plain_hello` is always built and *run*** (under the toolchain's own loader +
  runtime libs, no robot needed). If it doesn't run, the script fails — this is the
  CI gate.
- **`say_hello` / `robot_info` need the NAOqi 2.1 SDK**, which is Aldebaran's
  proprietary `libnaoqi/` and is **not** part of this repo. Point `CTC` at your
  original Aldebaran ctc to build them:

  ```sh
  CTC=/path/to/ctc-linux64-atom-2.1.4.13 ./examples/build-examples.sh
  ```

  The modern toolchain ships only the compiler + sysroot; NAOqi programs link the
  SDK from the original ctc (see [`../docs/usage.md`](../docs/usage.md)). The old
  (gcc4-compatible) C++ ABI is the compiler default, so a GCC-14 binary links
  cleanly against the GCC-4.5-built NAOqi libraries. `-std=gnu++11` keeps the
  boost 1.55 / NAOqi headers happy under GCC 14.

Outputs go to `examples/bin/` (git-ignored). The script also assembles a
ready-to-copy robot bundle at `examples/deploy/nao-modern-examples/` (binaries +
the newer `libstdc++`/`libgcc_s` + `run.sh` + `DEPLOY.md`).

## What this proves

For every binary the toolchain produces:
- **ELF 32-bit i386**, interpreter `/lib/ld-linux.so.2`, "for GNU/Linux 2.6.33";
- **glibc symbol ceiling ≤ 2.13** — runs on the robot's glibc;
- **old C++ ABI** (no `__cxx11` symbols) — the key interop proof: a GCC-14 binary
  resolving `ALTextToSpeechProxy::say(std::string)` against a GCC-4.5-built
  `libalproxies`;
- `plain_hello` actually **executes** under the reused glibc-2.13 loader.

The final robot-side confirmation (the robot speaking) needs a physical NAO — see
[`DEPLOY.md`](DEPLOY.md).

## CI

`.github/workflows/build-toolchain.yml` runs `examples/build-examples.sh`
immediately after building and verifying the toolchain, so a toolchain that cannot
compile+run a real program fails the build. (CI has no NAOqi SDK, so it gates on
the `plain_hello` build+run; the NAOqi examples build wherever the ctc is present.)

## Deploying to a robot

See [`DEPLOY.md`](DEPLOY.md) — copy `examples/deploy/nao-modern-examples/` (or its
tarball) to the robot and run via `run.sh`.
