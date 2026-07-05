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

## Getting the toolchains

Download the prebuilt archives from the
[latest release](https://github.com/davesnowdon/naoqi-cross-toolchain/releases/latest)
(both are self-contained and relocatable — unpack anywhere), or build from source:

```sh
# NAO V4/V5 (NAOqi 2.1)
./naoqi-2.1/build-toolchain.sh          # ~60-90 min on CI hardware, minutes on many cores
# NAO V6 (NAOqi 2.8) — builds from public sources only
./naoqi-2.8/build-toolchain.sh
```

Host prerequisites for building (Debian/Ubuntu):
`build-essential wget xz-utils bzip2 libgmp-dev file pkg-config dpkg-dev`.

Each tree has its own README, docs (`docs/design.md`, `docs/usage.md`), examples
(including a **gRPC + NAOqi in one binary** demo per generation) and CI workflow.

## What you need that is NOT in this repo

The toolchains are complete for plain C/C++. Linking against **NAOqi** needs the
proprietary SDK for your robot generation, which cannot be redistributed here:

| Generation | What | Where it comes from |
|---|---|---|
| 2.1 (V4/V5) | Aldebaran C++ CTC **`ctc-linux64-atom-2.1.4.13`** (the `libnaoqi/` SDK: AL\* headers + libs + boost 1.55 headers) | Aldebaran/SoftBank developer portal (defunct — use your existing copy, community archives, or Maxtronics support). Needed at **build time only**; the robot has the runtime libs. |
| 2.8 (V6) | An **app sysroot rsync'd from your own robot** (qi headers + libqi + boost 1.64 libs + glibc) | Your NAO V6, one command — see below. |

**Building the NAO6 app sysroot from a robot** (one-time, ~1.1 GB; the robot must
be on and reachable, you'll be prompted for the `nao` password):

```sh
./naoqi-2.8/sysroot-tools/make-robot-sysroot.sh --from-robot <ROBOT_IP> ~/nao6-app-sysroot
# already have an rsync copy? assemble from it instead (no robot needed):
./naoqi-2.8/sysroot-tools/make-robot-sysroot.sh --from-rsync ~/my-robot-rsync ~/nao6-app-sysroot
```

This rsyncs `/lib /usr/lib /usr/include /opt/aldebaran`, overlays the Debian 10
dev files (glibc 2.28 headers/CRT — checksum-pinned, fetched automatically),
fetches the boost 1.64 headers the robot doesn't ship, and repairs the symlink
traps (see `naoqi-2.8/docs/design.md`). There is **no 2.1 equivalent**: V4/V5
robots don't carry the SDK headers, so the Aldebaran CTC is required there.

Optional extras (only for the *real* gRPC demos): a gRPC build for the target and
host `protoc`/`grpc_cpp_plugin` — full recipes in
[`naoqi-2.1/examples/src/grpc_naoqi/README.md`](naoqi-2.1/examples/src/grpc_naoqi/README.md)
(2.1 needs two small glibc-2.13 fixes) and
[`naoqi-2.8/docs/usage.md`](naoqi-2.8/docs/usage.md) (2.8 builds unpatched).

## Using the toolchains — exact recipes

### NAO V4/V5 (naoqi-2.1) + Aldebaran CTC

```sh
# 0. unpack the toolchain (or use naoqi-2.1/output/ after building from source)
tar xf ctc-linux64-atom-2.1.4.14-modern-v0.1.1.tar.xz
MT=$PWD/ctc-linux64-atom-2.1.4.14-modern
CTC=/path/to/ctc-linux64-atom-2.1.4.13          # your Aldebaran CTC

# 1. plain C++ — no NAOqi, runs on the bare robot OS
$MT/cross/bin/i686-aldebaran-linux-gnu-g++ -O2 -std=c++17 hello.cpp -o hello

# 2. a NAOqi program (classic proxy API). MUST be -std=gnu++11 (boost 1.55
#    headers fail under C++17) — your own non-NAOqi TUs can still use C++17.
cat > say.cpp <<'EOF'
#include <alproxies/altexttospeechproxy.h>
int main(int argc, char** argv) {
    AL::ALTextToSpeechProxy tts(argc > 1 ? argv[1] : "127.0.0.1", 9559);
    tts.say(argc > 2 ? argv[2] : "Hello from the modern toolchain");
    return 0;
}
EOF
$MT/cross/bin/i686-aldebaran-linux-gnu-g++ -O2 -std=gnu++11 \
  -I$CTC/libnaoqi/include -I$CTC/libnaoqi/include/boost-1_55 \
  say.cpp -o say \
  -L$CTC/libnaoqi/lib -Wl,-rpath-link,$CTC/libnaoqi/lib \
  -lalproxies -lalcommon -lalvalue -lalerror -lqimessaging -lqitype -lqi -lrttools \
  -lboost_system-mt-1_55 -lboost_thread-mt-1_55 -lboost_signals-mt-1_55 \
  -lboost_program_options-mt-1_55 -lboost_regex-mt-1_55 -lboost_locale-mt-1_55 \
  -lboost_chrono-mt-1_55 -lboost_filesystem-mt-1_55 -lboost_date_time-mt-1_55 \
  -ldl -lrt -lpthread
# (modern ld links nothing transitively — the full boost set is required; it
#  comes from alproxies-config.cmake's *_DEPENDS. Or just use the helpers:)
CTC=$CTC ./naoqi-2.1/examples/build-examples.sh     # builds + bundles the examples

# 3. CMake projects instead of raw g++:
cmake -DCMAKE_TOOLCHAIN_FILE=$MT/cross-config.cmake -B build -S .

# 4. deploy & run on the robot (binaries need the NEWER libstdc++ shipped in
#    runtime-libs/; NAOqi's own libs come from the robot's /opt/aldebaran/lib —
#    NOT from a copied CTC dir: the ctc's boost filenames don't match the SONAMEs)
scp say nao@<ROBOT_IP>:/home/nao/
scp -r $MT/runtime-libs nao@<ROBOT_IP>:/home/nao/
ssh nao@<ROBOT_IP> 'LD_LIBRARY_PATH=$HOME/runtime-libs:/opt/aldebaran/lib \
  ./say 127.0.0.1 "It works"'
```

### NAO V6 (naoqi-2.8) + robot sysroot

```sh
# 0. unpack the toolchain; make the app sysroot once (see section above)
tar xf ctc-linux64-nao6-2.8-modern-v0.1.1.tar.xz
MT=$PWD/ctc-linux64-nao6-2.8-modern
RS=~/nao6-app-sysroot                               # from make-robot-sysroot.sh

# 1. plain C++ — uses the toolchain's embedded glibc-2.28 build sysroot
$MT/cross/bin/i686-nao6-linux-gnu-g++ -O2 -std=c++17 hello.cpp -o hello

# 2. a NAOqi 2.8 program (qi framework — V6 ships no AL*Proxy headers).
#    Use -std=gnu++17 (strict -std=c++17 breaks qi's log macros) and pass the
#    app sysroot as --sysroot (NOT just -L: Debian linker scripts only re-root
#    inside the active sysroot).
cat > say.cpp <<'EOF'
#include <qi/applicationsession.hpp>
#include <qi/anyobject.hpp>
int main(int argc, char** argv) {
    qi::ApplicationSession app(argc, argv);         // --qi-url=tcp://IP:9559
    app.startSession();
    qi::AnyObject tts = app.session()->service("ALTextToSpeech").value();
    tts.call<void>("say", argc > 1 ? argv[1] : "Hello from the modern toolchain");
    return 0;
}
EOF
$MT/cross/bin/i686-nao6-linux-gnu-g++ -O2 -std=gnu++17 --sysroot=$RS \
  -I$RS/opt/aldebaran/include \
  say.cpp -o say \
  -L$RS/opt/aldebaran/lib -Wl,-rpath-link,$RS/opt/aldebaran/lib \
  -lqi -lboost_thread -lboost_system -lboost_chrono
# or the helpers:
ROBOT_SYSROOT=$RS ./naoqi-2.8/examples/build-examples.sh

# 3. CMake projects: the toolchain file picks up the app sysroot from the env
NAO6_APP_SYSROOT=$RS cmake -DCMAKE_TOOLCHAIN_FILE=$MT/cross-config.cmake -B build -S .

# 4. deploy & run (same runtime-libs trick as 2.1)
scp say nao@<ROBOT_IP>:/home/nao/
scp -r $MT/runtime-libs nao@<ROBOT_IP>:/home/nao/
ssh nao@<ROBOT_IP> 'LD_LIBRARY_PATH=$HOME/runtime-libs:/opt/aldebaran/lib \
  ./say "It works" --qi-url=tcp://127.0.0.1:9559'
```

Both recipes end the same way on the robot: your binary + `runtime-libs/` first on
`LD_LIBRARY_PATH`, everything else from the robot's own NAOqi install. A binary
whose max `GLIBCXX` requirement is within the robot's stock libstdc++ (check with
`objdump -T bin | grep -o 'GLIBCXX_[0-9.]*' | sort -uV | tail -1`) doesn't even
need `runtime-libs`.

## Cutting a release

One repo release carries **both** toolchains. The entire process is pushing a tag:

```sh
git checkout main && git pull
git tag -a v0.2 -m "Release v0.2"
git push origin v0.2
```

`release.yml` then: builds both toolchains in parallel (each self-verifies and
gates on its examples), renames the archives to embed the tag, and publishes a
single release with both `.tar.xz` files + `SHA256SUMS` (~60–90 min; watch under
*Actions → Release (both toolchains)*).

**Rules (learned the hard way on v0.1.0):**
- **Never create the release in the GitHub UI first.** That publishes an empty
  release immediately; with GitHub's immutable releases the workflow can then
  never attach assets.
- **A tag whose release was published is burned forever** — it cannot be reused
  for another release even after deletion. If a release goes wrong, bump the
  version. (This is why the first release is v0.1.1.)
- Tags must match `v*` or nothing triggers. Fat-fingered a tag *before* anything
  published? `git push origin :refs/tags/vX.Y` removes it.

## License

GPLv3 for the build system (see [LICENSE](LICENSE)). The vendored NAOqi-2.1
sysroot pieces are © Aldebaran Robotics and redistributed under their own
licenses (glibc LGPL-2.1, GCC runtime under the GCC Runtime Library Exception,
gdbserver GPL) — see [`naoqi-2.1/vendor/README.md`](naoqi-2.1/vendor/README.md).
Nothing proprietary is vendored for 2.8: the NAOqi 2.8 stack comes from *your own
robot* at example-build time. Release archives contain no NAOqi components.
