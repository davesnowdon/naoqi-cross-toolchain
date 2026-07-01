# Deploy & test the examples on a real robot

`examples/build-examples.sh` produces `examples/deploy/nao-modern-examples/`, a
ready-to-copy bundle. This file is included in that bundle and explains how to run
it on a NAO **V4 / V5** (NAOqi 2.1.x, 32-bit Atom).

| Program | What it does | NAOqi needed? |
|---|---|---|
| `bin/plain_hello` | Prints one line. No NAOqi. | No — runs on the bare robot OS |
| `bin/say_hello`   | `ALTextToSpeechProxy::say()` — the robot speaks | Yes (naoqi running) |
| `bin/robot_info`  | Reads robot name, system version, TTS volume & voices (read-only) | Yes (naoqi running) |

> `say_hello` / `robot_info` are only in the bundle if it was built with the NAOqi
> SDK available (`CTC=` set). A CI-built bundle contains `plain_hello` only.

## Why the bundle ships `lib/`

The programs are compiled by GCC 14, so their C++ runtime references symbols up to
`GLIBCXX_3.4.32`. The robot's stock `libstdc++.so.6` (GCC 4.5-era, ~`3.4.14`) is
too old. The `libstdc++.so.6` shipped in `lib/` is a backward-compatible superset
that still needs only `glibc 2.13`, so it serves the new programs and the robot's
existing binaries. Everything else the programs need — `libqi`, `libalproxies`,
`libboost_*`, `libc`, ... — is already on the robot as part of NAOqi.

## 1. Copy to the robot

```sh
scp -r nao-modern-examples nao@<ROBOT_IP>:/home/nao/
```

## 2. Find the robot's NAOqi lib dir (once)

```sh
ssh nao@<ROBOT_IP>
find / -name 'libqi.so' 2>/dev/null      # e.g. /opt/aldebaran/lib
```

Use the directory containing `libqi.so`. On NAOqi 2.1 it is usually
`/opt/aldebaran/lib`, which is `run.sh`'s default (`NAOQI_LIB`).

## 3. Run

```sh
cd /home/nao/nao-modern-examples && chmod +x run.sh bin/*
./run.sh plain                 # no NAOqi needed — prints a line, exit 0
./run.sh say                   # robot speaks (naoqi must be running; localhost)
./run.sh say 127.0.0.1 9559 "Modern toolchain online."
./run.sh info                  # read-only robot info
# different naoqi lib path:  NAOQI_LIB=/path/to/naoqi/lib ./run.sh say
```

Equivalent without `run.sh`:

```sh
export LD_LIBRARY_PATH=$PWD/lib:/opt/aldebaran/lib:$LD_LIBRARY_PATH
./bin/say_hello 127.0.0.1 9559 "hello"
```

## Expected results

- `plain` → prints `Hello from the modern NAO cross-toolchain ...`, exit 0. Confirms
  the toolchain's binaries run on the robot's OS.
- `say`   → the robot speaks. Confirms a GCC-14 binary correctly calls into the
  GCC-4.5-built NAOqi libraries — i.e. the C++ ABI matches.
- `info`  → prints robot name, system version, TTS volume and voice list.

## Troubleshooting

- **`cannot open shared object libqi.so`** → `NAOQI_LIB` is wrong; set it to the dir
  from step 2.
- **`libstdc++.so.6: version 'GLIBCXX_3.4.NN' not found`** → launch via `run.sh`
  (or put this bundle's `lib/` **first** on `LD_LIBRARY_PATH`).
- **`say`/`info` connection error** → naoqi isn't running / wrong IP:port. Test with
  `plain` first (needs no naoqi). Default port is `9559`.
- **Illegal instruction** → binaries are Atom-tuned (`-march=bonnell`, SSSE3);
  correct for NAO V4/V5, will not run on a non-Atom i686 host.
