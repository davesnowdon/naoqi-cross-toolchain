# naoqi-cross-toolchain

Modern **GCC 14** cross-toolchains for Aldebaran/SoftBank **NAO** robots — build
current C++ (and modern libraries like gRPC) that runs on the robots and links
against their NAOqi stacks.

One compiler across the fleet, two configured targets:

| | [`naoqi-2.1/`](naoqi-2.1/) | [`naoqi-2.8/`](naoqi-2.8/) |
|---|---|---|
| Robots | **NAO V4 / V5** | **NAO V6** |
| NAOqi | 2.1.x | 2.8.x |
| Target triple | `i686-aldebaran-linux-gnu` | `i686-nao6-linux-gnu` |
| Arch / tune | i686, `-march=bonnell` | i686, `-march=silvermont` |
| glibc floor | 2.13 | 2.28 |
| C++ ABI default | **old** (gcc4-compatible — matches the GCC-4.5-built NAOqi 2.1 libs) | **new** C++11 ABI (matches NAOqi 2.8's `__cxx11` libs) |
| NAOqi C++ API | classic proxies (`ALTextToSpeechProxy`, …) | **qi framework** (`qi::Session` / `AnyObject`) |
| Sysroot source | vendored trimmed Aldebaran sysroot (in-repo) | **public**: Debian 10 archive + boost headers (fetched, pinned) |
| NAOqi SDK for examples | your Aldebaran ctc (`CTC=`) | your robot rsync (`ROBOT_SYSROOT=`) |
| Validated | ✅ on real NAO V4 **and** V5 robots (incl. gRPC + TTS end-to-end) | ✅ on a real NAO V6 (incl. gRPC + TTS end-to-end) |

> **Yes, NAO V6 is 32-bit too.** The stock OpenNAO 2.8 userland — every NAOqi
> library included — is i686 running on a 64-bit kernel. Only replacement runtimes
> (e.g. B-Human's) are x86_64. Both toolchains here therefore target i686; what
> differs is the C++ ABI, glibc floor, CPU tuning and the NAOqi API.

## Quick start

```sh
# NAO V4/V5 (NAOqi 2.1)
./naoqi-2.1/build-toolchain.sh          # ~60-90 min on CI hardware, minutes on many cores
./naoqi-2.1/examples/build-examples.sh  # + CTC=/path/to/aldebaran-ctc for the NAOqi examples

# NAO V6 (NAOqi 2.8) — toolchain builds from public sources only
./naoqi-2.8/build-toolchain.sh
./naoqi-2.8/examples/build-examples.sh  # + ROBOT_SYSROOT=... for the NAOqi examples
```

Each tree has its own README, docs (`docs/design.md`, `docs/usage.md`), examples
(including a **gRPC + NAOqi in one binary** demo per generation) and CI workflow.

## License

GPLv3 for the build system (see [LICENSE](LICENSE)). The vendored NAOqi-2.1
sysroot pieces are © Aldebaran Robotics and redistributed under their own
licenses (glibc LGPL-2.1, GCC runtime under the GCC Runtime Library Exception,
gdbserver GPL) — see [`naoqi-2.1/vendor/README.md`](naoqi-2.1/vendor/README.md).
Nothing proprietary is vendored for 2.8: the NAOqi 2.8 stack comes from *your own
robot* at example-build time.
