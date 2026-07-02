# Vendored reuse blob

`aldebaran-reuse.tar.xz` contains the only pieces of the original Aldebaran NAO
toolchain that this project reuses when building the modern toolchain. Everything
else is built from upstream GNU sources.

## Contents

Extracts to:

```
sysroot/     the glibc-2.13 sysroot (glibc runtime + startup files + system and
             Linux-2.6.33 headers) — target i686-aldebaran-linux-gnu
gdbserver    static ELF 32-bit i386 gdbserver, "for GNU/Linux 2.6.33"
```

The modern GCC/binutils are built with `--with-sysroot` pointing at `sysroot/`, so
the produced binaries share the robot's exact glibc 2.13 ABI. `gdbserver` is
deployed to the robot for remote debugging (see `docs/usage.md`).

## Provenance

Extracted, unmodified, from **Aldebaran `ctc-linux64-atom-2.1.4.13`**:

- `sysroot/` ← `cross/i686-aldebaran-linux-gnu/sysroot`, with the redundant
  `lib32/` and `lib64/` directories removed (they were byte-for-byte duplicates of
  `lib/` and are unused by this single-arch `-m32` toolchain).
- `gdbserver` ← `cross/i686-aldebaran-linux-gnu/debug-root/usr/bin/gdbserver`.

The `.sha256` file records the archive checksum.

## Copyright & licensing

> **The contents of `aldebaran-reuse.tar.xz` are NOT part of this repository's
> own source and are NOT covered by the repository's license (GPLv3).**
>
> These binaries are **© Aldebaran Robotics** (now SoftBank Robotics) — they are
> extracted verbatim from Aldebaran's proprietary NAO cross-toolchain
> (`ctc-linux64-atom-2.1.4.13`) and remain the copyright of Aldebaran Robotics and
> of the respective upstream authors of the individual components. This project
> claims no ownership over them and does not relicense them; the repository's
> LICENSE does not apply to this archive.

The individual components inside the archive retain their own upstream licenses,
under which redistribution of the binaries is permitted:

- **glibc** (the bulk of `sysroot/`): GNU LGPL v2.1.
- **libgcc / libgfortran** runtime bits in the sysroot: GPL with the **GCC Runtime
  Library Exception**.
- **Linux kernel headers** in `sysroot/usr/include`: GPLv2 with the Linux syscall
  note (headers are freely usable to build userspace).
- **gdbserver**: GNU GPL.

The archive is included here only to make the modern-toolchain build reproducible
without requiring a separate copy of the original Aldebaran ctc. If you redistribute
it, keep this attribution and honor the upstream licenses above.
