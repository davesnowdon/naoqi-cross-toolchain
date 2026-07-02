# grpc_naoqi — modern gRPC and NAOqi in one binary

Proof that a **modern gRPC client (C++17)** and **NAOqi code (gnu++11)** can live in
the *same* executable built with this toolchain, and do real work together: fetch a
string over gRPC, then speak it on the robot via NAOqi.

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

### Building a target gRPC (`GRPC_ROOT`)

The real gRPC side needs gRPC cross-built **for the target** with this toolchain
(old ABI is automatic; C++17 is gRPC's default). Sketch:

```sh
git clone --recurse-submodules -b vX.Y.Z https://github.com/grpc/grpc
# 1) host build -> protoc + grpc_cpp_plugin (codegen runs on the host)
cmake -S grpc -B grpc/host -DgRPC_INSTALL=ON -DCMAKE_INSTALL_PREFIX=$PWD/grpc-host && cmake --build grpc/host -j
# 2) target build with the toolchain file (old ABI is the default)
cmake -S grpc -B grpc/target -DgRPC_INSTALL=ON \
  -DCMAKE_TOOLCHAIN_FILE=$PWD/output/ctc-linux64-atom-2.1.4.14-modern/cross-config.cmake \
  -DCMAKE_INSTALL_PREFIX=$PWD/grpc-target \
  -DgRPC_BUILD_CODEGEN=OFF -DgRPC_SSL_PROVIDER=package  # adjust deps as needed
cmake --build grpc/target -j && cmake --install grpc/target
# 3) build the demo against it
GRPC_ROOT=$PWD/grpc-target PROTOC=$PWD/grpc-host/bin/protoc \
GRPC_CPP_PLUGIN=$PWD/grpc-host/bin/grpc_cpp_plugin \
CTC=/path/to/ctc-linux64-atom-2.1.4.13 ./examples/build-grpc-naoqi.sh
```

Mind the runtime caveats for the 2.6.33 kernel (disable `SO_REUSEPORT` via
`GRPC_ARG_ALLOW_REUSEPORT=0`) and duplicate OpenSSL/protobuf vs the robot's copies —
see [`../../docs/usage.md`](../../docs/usage.md) → *Combining gRPC and NAOqi*.

## Run

```sh
# on your PC: start the test server (pip install grpcio grpcio-tools)
python3 examples/src/grpc_naoqi/test_server.py 0.0.0.0:50051

# on the robot (real build): fetch from the PC, speak on the robot
./grpc_naoqi_demo <PC_IP>:50051 127.0.0.1 9559 NAO
```

The all-stub binary just runs locally and prints the flow (no server/robot needed).
