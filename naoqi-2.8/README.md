# naoqi-2.8 — modern GCC-14 toolchain for NAO V6

Builds a **GCC 14.3 / binutils 2.44** cross-toolchain targeting the **stock NAO V6**
(NAOqi 2.8): `i686-nao6-linux-gnu`, glibc 2.28, **new C++11 ABI**,
Silvermont-tuned.

> **Yes, i686.** The stock OpenNAO 2.8 userland — every NAOqi 2.8 library
> included — is 32-bit, running on a 64-bit kernel (measured on a real V6:
> `file libqi.so` → ELF 32-bit, NEEDED `ld-linux.so.2`). Only replacement
> runtimes such as B-Human's are x86_64. See [docs/design.md](docs/design.md).

## What's different from [`naoqi-2.1/`](../naoqi-2.1/)

| | naoqi-2.1 (V4/V5) | **naoqi-2.8 (V6)** |
|---|---|---|
| C++ ABI default | old (gcc4-compatible) | **new C++11 ABI** (`__cxx11` must be PRESENT — the verify check is inverted) |
| glibc floor | 2.13 | 2.28 |
| CPU tuning | bonnell | silvermont |
| Sysroot | vendored Aldebaran blob | **fetched from public sources** (pinned Debian 10 debs) — no proprietary inputs |
| NAOqi C++ API | classic proxies, `-std=gnu++11` max | **qi framework**, `-std=gnu++17` works |
| NAOqi SDK for examples | your Aldebaran ctc (`CTC=`) | your robot rsync (`ROBOT_SYSROOT=`) |

## Build the toolchain (no robot needed)

```sh
./build-toolchain.sh
# -> output/ctc-linux64-nao6-2.8-modern/ (+ .tar.xz), self-verified:
#    ELF32/i686, glibc <= 2.28, __cxx11 present, runs under the glibc-2.28 loader
```

The build sysroot is assembled from checksum-pinned Debian 10 (glibc 2.28 — the
robot's exact version) by `sysroot-tools/fetch-build-sysroot.sh`. CI can build
this toolchain entirely from public sources.

> **Validated on hardware (2026-07-03, NAO V6 "romulus", NAOqi 2.8.7.4):**
> `plain_hello` ran on the stock OS; `robot_info_v6` read name/version/voices via
> the qi API; `say_hello_v6` **spoke**; and `grpc_naoqi_demo_v6` fetched phrases
> over **gRPC 1.60** from a PC and spoke them via qi TTS — all exit 0.

## Build NAOqi 2.8 programs (needs your robot, once)

```sh
# one-time: make an app sysroot from your robot (~1.1 GB rsync + dev overlay)
./sysroot-tools/make-robot-sysroot.sh --from-robot <ROBOT_IP> ~/nao6-app-sysroot
# (or --from-rsync <existing-rsync-dir> ~/nao6-app-sysroot)

ROBOT_SYSROOT=~/nao6-app-sysroot ./examples/build-examples.sh
```

Examples (see [examples/](examples/)): `plain_hello` (no NAOqi; always built + run
— the CI gate), `say_hello_v6` and `robot_info_v6` (the **qi framework** API —
NAOqi 2.8 ships no `AL*Proxy` headers), and `grpc_naoqi_v6` (modern gRPC client +
qi TTS in **one binary**; stubs swap in per side without `GRPC_ROOT` /
`ROBOT_SYSROOT`). Deploy to the robot per
[examples/DEPLOY-V6.md](examples/DEPLOY-V6.md).

## The qi API in one breath

```cpp
#include <qi/applicationsession.hpp>
#include <qi/anyobject.hpp>
qi::ApplicationSession app(argc, argv);          // --qi-url=tcp://IP:9559
app.startSession();
qi::AnyObject tts = app.session()->service("ALTextToSpeech").value();
tts.call<void>("say", "Hello from NAOqi 2.8");
```

Compile `-std=gnu++17` (strict `-std=c++17` breaks qi's log macros), link
`-lqi -lboost_thread -lboost_system -lboost_chrono` against the robot sysroot.
More in [docs/usage.md](docs/usage.md).
