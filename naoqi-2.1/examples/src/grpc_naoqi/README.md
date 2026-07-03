# grpc_naoqi — modern gRPC and NAOqi in one binary

Proof that a **modern gRPC client (C++17)** and **NAOqi code (gnu++11)** can live in
the *same* executable built with this toolchain, and do real work together: fetch a
string over gRPC, then speak it on the robot via NAOqi.

This has been carried all the way through — and **validated on a real NAO V5**: gRPC
v1.60.0 was cross-built for the target with this toolchain, and one old-ABI binary
fetched a string over gRPC on the robot's 2.6.33 kernel and **spoke it via NAOqi**
(see *How this is tested* below).

## Why two modules

The two libraries cannot share a translation unit:

- NAOqi 2.1 / boost 1.55 headers **do not compile under C++17** (removed
  `std::auto_ptr`/`unary_function`) → the NAOqi TU must be `-std=gnu++11`.
- Modern gRPC / abseil **require C++17** → the gRPC TU must be `-std=c++17`.

They *can* share a binary because everything is built with the toolchain's default
**old libstdc++ ABI** (`_GLIBCXX_USE_CXX11_ABI=0`), so `std::string` has one layout
everywhere and passes freely across the boundary.

```
bridge.h            ABI-neutral interface (std::string only; compiles under both standards)
main.cpp            orchestration; includes bridge.h only            (-std=c++17)
grpc_side.cpp       real gRPC client                                  (-std=c++17)
grpc_side_stub.cpp  gRPC side w/o the gRPC stack (uses real C++17)     (-std=c++17)
naoqi_side.cpp      real ALTextToSpeechProxy::say()                    (-std=gnu++11)
naoqi_side_stub.cpp NAOqi side w/o the SDK                             (-std=gnu++11)
speaker.proto       the tiny gRPC service          test_server.py    host test server
```

## Build

From the repo root, after `./build-toolchain.sh`:

```sh
./examples/build-grpc-naoqi.sh
```

Each side is real when its SDK is present, else a stub (the binary is always built,
linked and — in the all-stub case — run):

| env | NAOqi side | gRPC side |
|---|---|---|
| *(none — the CI case)* | stub | stub |
| `CTC=/path/to/ctc-linux64-atom-2.1.4.13` | **real** (NAOqi SDK) | stub |
| `GRPC_ROOT=/path/to/target-grpc` | stub | **real** (gRPC) |
| both | **real** | **real** |

The script always verifies the binary is **uniformly old-ABI** (`objdump -T | grep
__cxx11` is empty) — the coexistence proof.

### Building a target gRPC (`GRPC_ROOT`) — verified recipe

The real gRPC side needs gRPC cross-built **for the target** with this toolchain.
This recipe was run against **gRPC v1.60.0** and produces old-ABI, i686,
glibc≤2.13 static archives. Two source-level fixes are needed because the target
sysroot is glibc 2.13 (2011) and the demo's own link needs a couple of extra libs;
all are baked into `build-grpc-naoqi.sh` for the demo link, and into the CMake
invocation for gRPC itself:

```sh
git clone --depth 1 -b v1.60.0 --recurse-submodules --shallow-submodules \
    https://github.com/grpc/grpc
export PATH="$PWD/go/bin:$PATH"        # modern BoringSSL needs Go on PATH

# 1) HOST build -> protoc + grpc_cpp_plugin (codegen runs on the host)
cmake -S grpc -B grpc/host -DCMAKE_BUILD_TYPE=Release \
      -DgRPC_INSTALL=ON -DCMAKE_INSTALL_PREFIX=$PWD/grpc-host \
      -DgRPC_BUILD_TESTS=OFF -DABSL_PROPAGATE_CXX_STD=ON
cmake --build grpc/host -j --target install

# 2) TARGET build with the toolchain file. The two glibc-2.13 fixes:
#    - -Dstatic_assert=_Static_assert : glibc 2.13 <assert.h> predates the C11
#      static_assert macro and GCC 14's default gnu17 C dialect isn't C23, so
#      BoringSSL's err_data.c won't compile without it.
#    - -lrt as a standard library : clock_gettime lived in librt until glibc 2.17,
#      so BoringSSL's tools fail to link without it.
cmake -S grpc -B grpc/target -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE=$PWD/output/ctc-linux64-atom-2.1.4.14-modern/cross-config.cmake \
      -DgRPC_INSTALL=ON -DCMAKE_INSTALL_PREFIX=$PWD/grpc-target \
      -DgRPC_BUILD_TESTS=OFF -DABSL_PROPAGATE_CXX_STD=ON \
      -DCMAKE_C_FLAGS="-Dstatic_assert=_Static_assert" \
      -DCMAKE_C_STANDARD_LIBRARIES="-lrt" -DCMAKE_CXX_STANDARD_LIBRARIES="-lrt" \
      -DgRPC_BUILD_CODEGEN=OFF \
      -Dprotobuf_PROTOC_EXECUTABLE=$PWD/grpc-host/bin/protoc \
      -D_gRPC_PROTOBUF_PROTOC_EXECUTABLE=$PWD/grpc-host/bin/protoc \
      -D_gRPC_CPP_PLUGIN=$PWD/grpc-host/bin/grpc_cpp_plugin
cmake --build grpc/target -j --target install

# 3) gRPC installs no .pc for its *bundled* re2/zlib/openssl, yet grpc.pc lists them
#    in Requires.private. Drop in shims (the static libs are already installed):
for p in re2:-lre2 zlib:-lz openssl:'-lssl -lcrypto'; do n=${p%%:*}; l=${p#*:}
  printf 'prefix=%s\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: %s\nVersion: 0\nLibs: -L${libdir} %s\nCflags: -I${includedir}\n' \
    "$PWD/grpc-target" "$n" "$l" > "$PWD/grpc-target/lib/pkgconfig/$n.pc"; done

# 4) build the demo against it (both sides real needs CTC too)
GRPC_ROOT=$PWD/grpc-target PROTOC=$PWD/grpc-host/bin/protoc \
GRPC_CPP_PLUGIN=$PWD/grpc-host/bin/grpc_cpp_plugin \
CTC=/path/to/ctc-linux64-atom-2.1.4.13 ./examples/build-grpc-naoqi.sh
```

`build-grpc-naoqi.sh` links the demo with `pkg-config --static grpc++ protobuf`
inside `--start-group`/`--end-group` (static abseil/gRPC have circular refs) plus
`-lpthread -ldl -lrt -lm`. gRPC's `grpc++.pc` deliberately omits protobuf, so
protobuf is queried explicitly.

## How this is tested — and what it does and does not prove

There is no NAO in CI or in this dev environment, so be precise about the method:

- **CI** (`build-toolchain-2.1.yml`, on dispatch / `v*` tags) builds the **all-stub**
  variant — no `CTC`, no `GRPC_ROOT` — links it, asserts `__cxx11 == 0`, and runs
  it. That continuously gates the **C++17↔gnu++11 old-ABI link + run** mechanic, but
  exercises neither real gRPC nor real NAOqi. (`pr-check.yml` only lints the script.)

- **Local full validation** runs the *target* i686 binary on an x86-64 host, but
  against the **robot's** userland, not the host's:

  ```sh
  $SYSROOT/lib/ld-linux.so.2 --library-path $RT:$SYSROOT/lib:$SYSROOT/usr/lib ./grpc_naoqi_demo …
  #   SYSROOT = output/ctc-*/cross/i686-aldebaran-linux-gnu/sysroot   (robot glibc 2.13)
  #   RT      = output/ctc-*/runtime-libs                             (newer libstdc++)
  ```

  x86-64 executes 32-bit i686 natively; invoking the **target sysroot's** loader with
  `--library-path` at the robot's libs makes userland calls resolve against
  glibc-2.13 + the deployed `libstdc++`, not the host's. It is a "sysroot-lite" run,
  not a native host run.

| Property | Host-loader run | How it's verified |
|---|---|---|
| i686 arch, binary executes | ✅ | it ran |
| resolves against **glibc-2.13** userland | ✅ | ran under target loader + robot libs |
| gRPC functional (connect, serialize, RPC round-trip) | ✅ | server logged `GetPhrase`; client got the reply |
| C++17↔gnu++11 **old-ABI** coexistence at runtime | ✅ | the `std::string` crossed the boundary intact |
| **glibc symbol ceiling ≤ 2.13** | ✅ (static) | `objdump -T` ⇒ max `GLIBC_2.12`, no run needed |
| **old C++ ABI** (interops with GCC-4.5 NAOqi) | ✅ (static) | `objdump -T … __cxx11` = 0 |
| behavior on the robot's **kernel 2.6.33** | ✅ *on hardware* | validated on a NAO V5 — real gRPC fetch on the 2.6.33 kernel |
| actual NAOqi **TTS speaking** | ✅ *on hardware* | validated on a NAO V5 — the robot spoke the fetched phrase |

The two decisive robot-compatibility guarantees — **glibc ≤ 2.13** and **old ABI** —
are link-time properties of the ELF and hold whether or not it runs. The host run
only adds "…and it genuinely functions." What it **cannot** catch is kernel-version
behavior: the host kernel (6.x) has `SO_REUSEPORT`/`getrandom` that the robot's
2.6.33 lacks. The client already disables `SO_REUSEPORT` (see `grpc_side.cpp`); the
remaining old-kernel caveats are in [`../../docs/usage.md`](../../docs/usage.md).

> **Validated on hardware (2026-07-03).** On a NAO V5 ("rommie", NAOqi 2.1.4.13):
> `plain_hello` ran; `say_hello`/`robot_info` drove real NAOqi TTS + queries; and the
> both-real `grpc_naoqi_demo` — one old-ABI binary — fetched a string from a PC over
> modern gRPC 1.60 **on the robot's 2.6.33 kernel** and spoke it via NAOqi. The two
> rows marked "on hardware" above are confirmed end-to-end. NAO V4 is unproven but
> shares the ABI/arch.

## Running the complete test on a real NAO robot

This is the only way to prove the two ❌ rows above. Needs a NAO **V4/V5** (NAOqi
2.1.x) and a PC on the same network.

**1. Build both sides real** (host, with the NAOqi SDK and a target gRPC — see the
recipe above):

```sh
GRPC_ROOT=$PWD/grpc-target PROTOC=$PWD/grpc-host/bin/protoc \
GRPC_CPP_PLUGIN=$PWD/grpc-host/bin/grpc_cpp_plugin \
CTC=/path/to/ctc-linux64-atom-2.1.4.13 ./examples/build-grpc-naoqi.sh
# -> examples/bin/grpc_naoqi_demo  (ELF32 i386, glibc≤2.13, __cxx11=0,
#    with both grpc::CreateChannel and ALTextToSpeechProxy)
```

**2. Assemble a robot bundle.** gRPC is static, so the only extra runtime files are
the newer C++ runtime (the binary references `GLIBCXX > 3.4.14`, like `say_hello`):

```sh
mkdir -p nao-grpc/lib && cp examples/bin/grpc_naoqi_demo nao-grpc/
cp -P output/ctc-*/runtime-libs/libstdc++.so.6* output/ctc-*/runtime-libs/libgcc_s.so.1* nao-grpc/lib/
scp -r nao-grpc nao@<ROBOT_IP>:/home/nao/
```

**3. Start the gRPC server on the PC** (reachable from the robot):

```sh
pip install grpcio grpcio-tools           # a normal PC has working TLS/PyPI
python3 examples/src/grpc_naoqi/test_server.py 0.0.0.0:50051
```

`test_server.py` self-generates its stubs from `speaker.proto`. (A C++ server built
against `grpc-host` works too if you'd rather not use Python.)

**4. Run on the robot** — fetch from the PC, speak locally. NAOqi's own libs come
from the robot's install (its *plain* boost SONAMEs — see
[`../DEPLOY.md`](../DEPLOY.md) for why the robot's dir, not the ctc SDK):

```sh
ssh nao@<ROBOT_IP>
cd /home/nao/nao-grpc && chmod +x grpc_naoqi_demo
LD_LIBRARY_PATH=$PWD/lib:/opt/aldebaran/lib \
  ./grpc_naoqi_demo <PC_IP>:50051 127.0.0.1 9559 NAO
```

**Expected:** the PC server logs `GetPhrase(name="NAO")`, and **the robot says**
*"Hello NAO, this sentence was fetched over gRPC and spoken by NAOqi."* That closes
the loop the host run can't: real gRPC networking **and** NAOqi TTS, on the robot's
own kernel and userland, from one old-ABI binary.

**If the client misbehaves on the old kernel:** `SO_REUSEPORT` is already disabled;
for anything else (`getrandom`, `TCP_USER_TIMEOUT`) see
[`../../docs/usage.md`](../../docs/usage.md) → *Old kernel (2.6.33)*. Test reachability
first with `plain_hello`/`say_hello` from the main deploy bundle.

## Run (all-stub, no server/robot needed)

```sh
./examples/build-grpc-naoqi.sh          # builds + runs the all-stub binary
```

It prints the flow and proves the `std::string` returned by the C++17 module
survives the call into the gnu++11 module.
