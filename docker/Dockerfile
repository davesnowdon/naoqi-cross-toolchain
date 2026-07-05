# NAO builder images — hermetic C++ build environments for NAO robot software.
#
# Every input is public and pinned: the released relocatable toolchains from
# this repo's GitHub releases, gRPC from source, Go from go.dev. No Aldebaran
# IP enters any image — consumers provide the proprietary bits (libnaoqi SDK,
# robot app sysroot) under /opt/nao/aldebaran/ themselves (see README.md).
#
# Targets (docker build --target <t>):
#   host     — native tools + gRPC host install (protoc, grpc_cpp_plugin)
#   nao-2.1  — + ctc-2.1 toolchain + gRPC for NAO V4/V5 (i686, old ABI, glibc 2.13)
#   nao-2.8  — + ctc-2.8 toolchain + gRPC for NAO V6   (i686, new ABI, glibc 2.28)
#
# Layout contract baked into all images (mirrored by symlink farm on dev boxes):
#   /opt/nao/ctc-2.1  /opt/nao/ctc-2.8  /opt/nao/grpc/{host,v5,v6}
#   /opt/nao/aldebaran/            <- left absent; private overlay mounts here

# Base needs glibc >= 2.38: the released toolchains' host-side compiler
# binaries are built on a modern host (ubuntu-24.04-class). bookworm (2.36)
# is too old; ubuntu:24.04 ships 2.39.
ARG BASE_IMAGE=ubuntu:24.04

# ---- tools: shared build environment ----------------------------------------
FROM ${BASE_IMAGE} AS tools
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build pkg-config git curl ca-certificates \
      xz-utils bzip2 zstd file nasm python3 \
    && rm -rf /var/lib/apt/lists/*

# ---- grpc-src: pinned gRPC sources + Go (BoringSSL build dep) ----------------
FROM tools AS grpc-src
ARG GRPC_VERSION=v1.60.0
ARG GO_VERSION=1.22.5
ARG GO_SHA256=904b924d435eaea086515bc63235b192ea441bd8c9b198c507e85009e6e4c7f0
RUN curl -fsSL -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
    && tar -C /usr/local -xzf /tmp/go.tgz && rm /tmp/go.tgz
ENV PATH=/usr/local/go/bin:${PATH}
RUN git clone --branch "${GRPC_VERSION}" --depth 1 \
      --recurse-submodules --shallow-submodules \
      https://github.com/grpc/grpc /src/grpc
COPY build-grpc.sh /usr/local/bin/build-grpc.sh
RUN chmod +x /usr/local/bin/build-grpc.sh

# ---- grpc-host: native protoc + grpc_cpp_plugin + host libs ------------------
FROM grpc-src AS grpc-host
RUN build-grpc.sh host /src/grpc /opt/nao/grpc/host

# ---- toolchains: released relocatable archives, checksum-pinned --------------
FROM tools AS ctc21
ARG TOOLCHAIN_TAG=v0.1.3
ARG CTC21_SHA256=27df16dadc93e3766b74c1fd8be9344bf2ba48dfcac11706fb74ee7073525a19
RUN curl -fsSL -o /tmp/ctc.tar.xz \
      "https://github.com/davesnowdon/naoqi-cross-toolchain/releases/download/${TOOLCHAIN_TAG}/ctc-linux64-atom-2.1.4.14-modern-${TOOLCHAIN_TAG}.tar.xz" \
    && echo "${CTC21_SHA256}  /tmp/ctc.tar.xz" | sha256sum -c - \
    && mkdir -p /opt/nao/ctc-2.1 \
    && tar -xJf /tmp/ctc.tar.xz -C /opt/nao/ctc-2.1 --strip-components=1 \
    && rm /tmp/ctc.tar.xz
# Guard the "relocatable" claim: no absolute symlinks anywhere, no dangling
# links in the sysroot (v0.1.1 shipped host-absolute glibc dev links that
# broke -pthread in containers; overlay-lib.sh is fixed, this keeps it fixed).
RUN test "$(find /opt/nao/ctc-2.1 -type l -lname '/*' | wc -l)" = 0 \
    && test "$(find /opt/nao/ctc-2.1/cross/i686-aldebaran-linux-gnu/sysroot -xtype l | wc -l)" = 0

FROM tools AS ctc28
ARG TOOLCHAIN_TAG=v0.1.3
ARG CTC28_SHA256=85bd8f1b07610089ac4a75bb41aab0f9aaebc41b1ed8dbf3ec832faa91fd6c82
RUN curl -fsSL -o /tmp/ctc.tar.xz \
      "https://github.com/davesnowdon/naoqi-cross-toolchain/releases/download/${TOOLCHAIN_TAG}/ctc-linux64-nao6-2.8-modern-${TOOLCHAIN_TAG}.tar.xz" \
    && echo "${CTC28_SHA256}  /tmp/ctc.tar.xz" | sha256sum -c - \
    && mkdir -p /opt/nao/ctc-2.8 \
    && tar -xJf /tmp/ctc.tar.xz -C /opt/nao/ctc-2.8 --strip-components=1 \
    && rm /tmp/ctc.tar.xz
RUN test "$(find /opt/nao/ctc-2.8 -type l -lname '/*' | wc -l)" = 0 \
    && test "$(find /opt/nao/ctc-2.8/cross/i686-nao6-linux-gnu/sysroot -xtype l | wc -l)" = 0

# ---- gRPC cross builds --------------------------------------------------------
FROM grpc-src AS grpc-v5
COPY --from=ctc21 /opt/nao/ctc-2.1 /opt/nao/ctc-2.1
COPY --from=grpc-host /opt/nao/grpc/host /opt/nao/grpc/host
RUN build-grpc.sh v5 /src/grpc /opt/nao/grpc/v5

FROM grpc-src AS grpc-v6
COPY --from=ctc28 /opt/nao/ctc-2.8 /opt/nao/ctc-2.8
COPY --from=grpc-host /opt/nao/grpc/host /opt/nao/grpc/host
RUN build-grpc.sh v6 /src/grpc /opt/nao/grpc/v6

# ---- final images --------------------------------------------------------------
FROM tools AS host
COPY --from=grpc-host /opt/nao/grpc/host /opt/nao/grpc/host
LABEL org.opencontainers.image.source="https://github.com/davesnowdon/naoqi-cross-toolchain" \
      org.opencontainers.image.description="NAO builder: native tools + gRPC host install (protoc, grpc_cpp_plugin)"

FROM tools AS nao-2.1
COPY --from=ctc21 /opt/nao/ctc-2.1 /opt/nao/ctc-2.1
COPY --from=grpc-host /opt/nao/grpc/host /opt/nao/grpc/host
COPY --from=grpc-v5 /opt/nao/grpc/v5 /opt/nao/grpc/v5
LABEL org.opencontainers.image.source="https://github.com/davesnowdon/naoqi-cross-toolchain" \
      org.opencontainers.image.description="NAO V4/V5 builder: ctc-2.1 (GCC 14, i686 old-ABI glibc 2.13) + gRPC 1.60. Proprietary NAOqi SDK NOT included — overlay /opt/nao/aldebaran yourself."

FROM tools AS nao-2.8
COPY --from=ctc28 /opt/nao/ctc-2.8 /opt/nao/ctc-2.8
COPY --from=grpc-host /opt/nao/grpc/host /opt/nao/grpc/host
COPY --from=grpc-v6 /opt/nao/grpc/v6 /opt/nao/grpc/v6
LABEL org.opencontainers.image.source="https://github.com/davesnowdon/naoqi-cross-toolchain" \
      org.opencontainers.image.description="NAO V6 builder: ctc-2.8 (GCC 14, i686 new-ABI glibc 2.28) + gRPC 1.60. Proprietary robot app sysroot NOT included — overlay /opt/nao/aldebaran yourself."
