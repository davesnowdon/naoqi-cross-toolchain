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

## Licensing

These are standard, freely redistributable GNU runtime components:

- **glibc** (the bulk of `sysroot/`): GNU LGPL v2.1.
- **libgcc / libgfortran** runtime bits in the sysroot: GPL with the **GCC Runtime
  Library Exception**.
- **Linux kernel headers** in `sysroot/usr/include`: Linux-syscall-note / GPLv2
  (headers are freely usable to build userspace).
- **gdbserver**: GNU GPL.

Redistribution of these binaries is permitted under their respective licenses. They
are included here only to make the modern-toolchain build reproducible without
requiring a copy of the original Aldebaran ctc.
