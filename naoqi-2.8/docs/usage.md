# naoqi-2.8 toolchain — usage

## Compile flags that matter

- **`-std=gnu++17`** (or gnu++14) for anything including qi headers. Strict
  `-std=c++17` breaks the `qiLog*` macros' `_QI_LOG_ISEMPTY` variadic trick
  (a cascade of errors in `qi/detail/log.hxx`). Your own non-qi TUs can use
  strict modes freely.
- The **new C++11 ABI and `-march=silvermont` are the toolchain defaults** —
  nothing to pass. Do NOT set `_GLIBCXX_USE_CXX11_ABI=0`; NAOqi 2.8 libs are
  new-ABI.
- Typical NAOqi link line (against a robot sysroot `$RS`):
  ```sh
  i686-nao6-linux-gnu-g++ -O2 -std=gnu++17 \
    -I$RS/opt/aldebaran/include -I$RS/usr/include app.cpp -o app \
    -L$RS/opt/aldebaran/lib -L$RS/usr/lib -Wl,-rpath-link,$RS/opt/aldebaran/lib \
    -lqi -lboost_thread -lboost_system -lboost_chrono
  ```
  (Modern ld links nothing transitively — boost must be explicit, and the
  sysroot's unversioned `.so` symlinks are created by `make-robot-sysroot.sh`.)

## The NAOqi 2.8 C++ API (qi framework)

The robot ships headers for `qi/` (+`qicore`, `ka`) only — **no `AL*Proxy`
headers**. The classic proxy classes survive only as libraries; the supported
API is dynamic services:

```cpp
#include <qi/applicationsession.hpp>
#include <qi/anyobject.hpp>

qi::ApplicationSession app(argc, argv);         // consumes --qi-url=tcp://IP:9559
app.startSession();
qi::AnyObject tts = app.session()->service("ALTextToSpeech").value();
tts.call<void>("say", "hello");                 // runtime-typed against MetaObject
float vol = tts.call<float>("getVolume");
auto voices = tts.call<std::vector<std::string>>("getAvailableVoices");
```

- `service()` returns `qi::FutureSync<qi::AnyObject>`; `.value()` throws on error.
- Async: `obj.async<R>(...)` → `qi::Future<R>`. Signals: `obj.connect(...)`.
- Same service names as 2.1: `ALTextToSpeech`, `ALMotion`, `ALMemory`, `ALSystem`…
- Migration from 2.1 proxies: `ALFooProxy p(ip, port); p.bar(x)` becomes
  `session->service("ALFoo").value().call<R>("bar", x)`.
- Outside a `main` that owns an ApplicationSession (e.g. in a library), construct
  a lazy `static qi::Application` with synthetic argv, then use `qi::Session`
  directly — see `examples/src/grpc_naoqi_v6/naoqi_side_v6.cpp`.
- **Do not** try to compile the NAOqi 2.1 `alproxies` headers against 2.8 libs:
  it fails at link (`qi::TypeInfo::TypeInfo(std::type_info const&)` is gone).

## Deploying binaries

GCC-14 binaries reference `GLIBCXX_3.4.32`; the robot's stock libstdc++ is
6.0.25 (3.4.25). Ship `runtime-libs/` (32-bit `libstdc++.so.6.0.33` +
`libgcc_s.so.1`) and put it **first** on `LD_LIBRARY_PATH`:

```sh
LD_LIBRARY_PATH=/home/nao/mylibs:/opt/aldebaran/lib ./my_app --qi-url=tcp://127.0.0.1:9559
```

Everything else (libqi, boost 1.64, glibc 2.28) is already on the robot.
`examples/build-examples.sh` assembles a ready-to-scp bundle with this layout.

## Modern libraries (gRPC etc.)

Cross-build with `cross-config.cmake`. gRPC v1.60 builds for this target **with
no source changes** (glibc 2.28 has C11 `static_assert`; `clock_gettime` is in
libc) — two-stage as usual: host build for `protoc`/`grpc_cpp_plugin`, then

```sh
cmake -S grpc -B build-target -DCMAKE_TOOLCHAIN_FILE=<ctc>/cross-config.cmake \
  -DCMAKE_BUILD_TYPE=Release -DgRPC_INSTALL=ON -DCMAKE_INSTALL_PREFIX=$PWD/grpc-target \
  -DgRPC_BUILD_TESTS=OFF -DABSL_PROPAGATE_CXX_STD=ON -DgRPC_BUILD_CODEGEN=OFF \
  -Dprotobuf_PROTOC_EXECUTABLE=<host>/bin/protoc \
  -D_gRPC_PROTOBUF_PROTOC_EXECUTABLE=<host>/bin/protoc \
  -D_gRPC_CPP_PLUGIN=<host>/bin/grpc_cpp_plugin
```

then add the bundled-dep `.pc` shims (re2/zlib/openssl) as in
`examples/build-grpc-naoqi.sh`, and link with
`pkg-config --static grpc++ protobuf` inside `--start-group` +
`-lpthread -ldl -lm`. The V6 kernel is 4.x, so the V4/V5-era old-kernel caveats
(`SO_REUSEPORT`, `getrandom`) do **not** apply. gRPC (C++17-friendly) and qi can
even share `-std=gnu++17` — the example still splits them into separate TUs for
header hygiene.

## Remote debugging

The toolchain is C/C++ only (no gdb build for the 2.8 tree yet). Use your host
gdb (`target remote`, `set sysroot` at the robot sysroot) with the robot's own
gdbserver if installed, or the naoqi-2.1 tree's gdb for i686 targets.
