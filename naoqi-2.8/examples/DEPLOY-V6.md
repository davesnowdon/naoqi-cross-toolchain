# Deploy & test on Romulus (NAO V6, NAOqi 2.8)

Binaries built with the **GCC-14 nao6 toolchain** (`i686-nao6-linux-gnu`: 32-bit,
glibc 2.28, **new C++11 ABI**, Silvermont-tuned) against the sysroot rsync'd from
Romulus. Reminder: the stock v6 userland — NAOqi included — is **32-bit**, so
these are i686 binaries just like the v4/v5 ones (but new ABI + newer glibc floor).

| Program | What it does | Needs NAOqi? |
|---|---|---|
| `bin/plain_hello` | prints one line | no |
| `bin/say_hello_v6` | Romulus speaks, via the **qi framework** (`ALTextToSpeech`) | yes |
| `bin/robot_info_v6` | read-only: name, version, TTS volume + voices | yes |
| `bin/grpc_naoqi_demo_v6` | fetches a phrase from your PC over **gRPC 1.60** and speaks it | yes + PC server |

## Why the bundle ships `lib/`
GCC-14 binaries reference `GLIBCXX_3.4.32`; Romulus's stock libstdc++ is 6.0.25
(`3.4.25`). The bundled `libstdc++.so.6.0.33`/`libgcc_s.so.1` (32-bit, built by
this toolchain) are backward-compatible supersets — `run.sh` puts them first on
`LD_LIBRARY_PATH`. Everything else (libqi, boost 1.64, glibc) is the robot's own.
`plain_hello` from this bundle also wants the newer libstdc++ (run via `run.sh`).

## 1. Copy to Romulus
```sh
scp -r nao6-modern-examples nao@<ROMULUS_IP>:/home/nao/
```

## 2. Basic tests (on the robot)
```sh
ssh nao@<ROMULUS_IP>
cd /home/nao/nao6-modern-examples && chmod +x run.sh bin/*
./run.sh plain          # -> "Hello from the modern NAO6 toolchain (GCC 14, ...)"
./run.sh info           # -> Robot name / 2.8.7.4 / TTS volume / voices
./run.sh say "The NAO six toolchain is working."   # Romulus speaks
```
`say`/`info` default to `--qi-url=tcp://127.0.0.1:9559` (extra args are passed
through, so `./run.sh say --qi-url=tcp://127.0.0.1:9559 "hi"` also works — note
qi apps take text as the first *non-option* argument).

## 3. gRPC + NAOqi demo
On your **PC** (same server binary/protocol as the v5 demo — `speaker_server`
from the v4/v5 work, or `test_server.py` with grpcio installed):
```sh
./speaker_server 0.0.0.0:50051   # any Speaker-service server; see test_server.py in examples/src/grpc_naoqi_v6
```
On **Romulus**:
```sh
./run.sh grpc <PC_IP>:50051 Romulus
```
Expected: PC logs `GetPhrase(name="Romulus")`; Romulus says
*"Hello Romulus, this sentence was fetched over gRPC and spoken by NAOqi."*
On failure the demo exits non-zero with the gRPC/qi error (that's deliberate).

## Troubleshooting
- `GLIBCXX_... not found` → launch via `run.sh` (bundle `lib/` must be first).
- `Connect error` from say/info/grpc → NAOqi not running or wrong URL; test
  `plain` first (needs nothing).
- gRPC `connection refused` → check `<PC_IP>`, PC firewall allows tcp/50051.
- These binaries are for **NAO V6 only** (Silvermont + glibc 2.28 + new ABI);
  they will not run on V4/V5 (use the v4/v5 bundle there).
