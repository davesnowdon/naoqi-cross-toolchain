# NAO6 examples

Built by [`build-examples.sh`](build-examples.sh) (and
[`build-grpc-naoqi.sh`](build-grpc-naoqi.sh)) with the naoqi-2.8 toolchain.
Everything is `-std=gnu++17`, new C++11 ABI (both toolchain defaults).

| Source | Demonstrates | Needs |
|---|---|---|
| `src/plain_hello_v6.cpp` | toolchain output runs on the robot OS (built **and run** in CI) | — |
| `src/say_hello_v6.cpp` | TTS via the **qi framework** (`session→service("ALTextToSpeech")→call("say")`) | `ROBOT_SYSROOT` |
| `src/robot_info_v6.cpp` | read-only qi calls, several return types (string/float/vector) | `ROBOT_SYSROOT` |
| [`src/grpc_naoqi_v6/`](src/grpc_naoqi_v6/) | **modern gRPC + NAOqi 2.8 in one binary** — fetch a phrase over the network, speak it | stubs by default; real per side with `GRPC_ROOT` / `ROBOT_SYSROOT` |

```sh
# CI case (no robot): plain_hello builds AND runs; grpc demo builds all-stub AND runs
./build-examples.sh && ./build-grpc-naoqi.sh

# full local build against your robot's stack
ROBOT_SYSROOT=~/nao6-app-sysroot ./build-examples.sh
ROBOT_SYSROOT=~/nao6-app-sysroot GRPC_ROOT=... PROTOC=... GRPC_CPP_PLUGIN=... ./build-grpc-naoqi.sh
```

`build-examples.sh` also assembles a ready-to-scp bundle at
`deploy/nao6-modern-examples/` (binaries + newer libstdc++ + `run.sh` +
[`DEPLOY-V6.md`](DEPLOY-V6.md)).

Every binary is checked: ELF32/i686, glibc ≤ 2.28, and `__cxx11` **present**
(new ABI — required to link NAOqi 2.8; the naoqi-2.1 examples check the exact
opposite). The `grpc_naoqi_v6` sources `bridge.h`/`main.cpp`/`grpc_side*.cpp`/
`speaker.proto`/`test_server.py` are shared with
[`naoqi-2.1/examples/src/grpc_naoqi/`](../../naoqi-2.1/examples/src/grpc_naoqi/) —
only the NAOqi side differs (qi API vs ALProxy).

**All four binaries are validated on a real NAO V6** ("romulus", 2026-07-03):
plain ran, info read robot data, say spoke, and the gRPC demo fetched phrases
from a PC over the network and spoke them — each exit 0.
