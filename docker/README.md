# NAO builder images

Hermetic Docker build environments for NAO robot software (e.g.
[robot-companion]-style projects): the released relocatable toolchains from this
repo, plus gRPC 1.60 cross-built for each robot generation, plus the host
codegen tools — everything a CI job needs except the proprietary Aldebaran bits.

| Target | Image contents | Builds for |
|---|---|---|
| `host` | native GCC/CMake/Ninja + gRPC host install (`protoc`, `grpc_cpp_plugin`) | build-host unit tests |
| `nao-2.1` | `host` + `ctc-2.1` toolchain + gRPC for i686/old-ABI/glibc 2.13 | NAO V4 / V5 (NAOqi 2.1) |
| `nao-2.8` | `host` + `ctc-2.8` toolchain + gRPC for i686/new-ABI/glibc 2.28 | NAO V6 (NAOqi 2.8) |

Every input is public and checksum-pinned (toolchain release archives, gRPC tag,
Go tarball), so the images can be published publicly and rebuilt from the
internet alone.

## Layout contract

All images bake this layout; dev machines mirror it with a symlink farm so the
same build presets work everywhere:

```
/opt/nao/
├── ctc-2.1/              released ctc-linux64-atom-2.1.4.14-modern
├── ctc-2.8/              released ctc-linux64-nao6-2.8-modern
├── grpc/{host,v5,v6}/    gRPC 1.60 installs
└── aldebaran/            NOT in any image — see below
```

## The proprietary overlay (`/opt/nao/aldebaran/`)

Linking against NAOqi needs Aldebaran material that cannot be redistributed
(see the top-level README). Images ship **without** it; consumers overlay it at
container start (untar a private artifact, or bind-mount):

```
/opt/nao/aldebaran/
├── ctc-2.1.4.13/     subset of the original Aldebaran CTC: libnaoqi/ (AL*
│                     headers + libs + boost 1.55) and its runtime dep dirs
│                     openssl/ zlib/ xml2/ iconv/
└── nao6-sysroot/     NAO6 app sysroot made by
                      naoqi-2.8/sysroot-tools/make-robot-sysroot.sh
```

Plain C/C++ (and gRPC) cross-builds work without the overlay.

## Building the images

```sh
cd docker
docker build --target host    -t nao-builder:host    .
docker build --target nao-2.1 -t nao-builder:2.1     .
docker build --target nao-2.8 -t nao-builder:2.8     .
```

Stages share layers: the gRPC source clone and host build happen once. A cold
build compiles gRPC three times (host + two targets) — expect ~30–60 min.

Pins are `ARG`s at the top of the Dockerfile / stage headers: `TOOLCHAIN_TAG`
(+ per-archive SHA-256s from the release's `SHA256SUMS`), `GRPC_VERSION`,
`GO_VERSION`. Bump deliberately and together.

## Using in CI (sketch)

```yaml
jobs:
  agent-v5:
    runs-on: ubuntu-latest
    container: ghcr.io/davesnowdon/nao-builder:2.1
    steps:
      - uses: actions/checkout@v4
      - name: proprietary overlay
        run: |
          gh release download sdk-v1 --repo <you>/<private-assets-repo> -p 'aldebaran-*.tar.zst'
          mkdir -p /opt/nao/aldebaran
          tar --zstd -xf aldebaran-ctc-2.1.4.13.tar.zst -C /opt/nao/aldebaran
        env:
          GH_TOKEN: ${{ secrets.SDK_ASSETS_TOKEN }}
      - run: third-party/build-all.sh v5
      - run: cd client && cmake --preset v5 && cmake --build --preset v5
```

The consuming project's ABI gates / sysroot-loader smoke run as usual inside the
container — they only need the overlay paths above.

[robot-companion]: https://github.com/davesnowdon
