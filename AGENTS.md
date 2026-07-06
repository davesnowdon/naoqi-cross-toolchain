# AGENTS.md — what you can't see from the file tree

Context for AI agents (and new humans) working on this repo. It skips anything
obvious from reading the code and records the **decisions, invariants and traps**
— the "why", and what will break if you "fix" it.

## The one-sentence model

Two GCC-14 cross-toolchains for NAO robots that differ **only** where the robots
differ; every constraint below was measured on real hardware (all three fleet
robots: V4 "robbie", V5 "rommie", V6 "romulus"), not taken from documentation —
the documentation is frequently wrong (see *Counterintuitive facts*).

## Counterintuitive facts — do not "correct" them

- **Stock NAO V6 is 32-bit.** Everything you'll read online says V6 is x86_64.
  The *kernel* is; the stock userland including all 444 NAOqi 2.8 libraries is
  ELF32 i686 (measured from a robot rsync). Only replacement runtimes (B-Human)
  are 64-bit. If you change the 2.8 target away from i686, nothing will link
  against NAOqi.
- **The two trees' C++ ABI defaults are opposite, on purpose.** NAOqi 2.1 libs
  were built with GCC 4.5 → old ABI (`--with-default-libstdcxx-abi=gcc4-compatible`
  in `naoqi-2.1`); NAOqi 2.8 libs are `__cxx11` → new ABI (the flag's *absence*
  in `naoqi-2.8`). Consequently the verify scripts assert **inverted conditions**:
  2.1 fails if `__cxx11` symbols are present, 2.8 fails if they are absent. Both
  assertions are load-bearing; a well-meaning "make the checks consistent" patch
  breaks a robot generation.
- **`-march` is not interchangeable.** V4/V5 are Atom Z530 (Bonnell, single
  core); V6 is Atom E3845 (Silvermont). Silvermont code SIGILLs on V4/V5 (SSE4).
  Much online documentation claims V5 is Silvermont; it is not.
- **NAOqi headers demand `gnu++` dialects.** 2.1: hard ceiling `-std=gnu++11`
  (boost 1.55 uses `auto_ptr`/`unary_function`, removed in C++17). 2.8: any
  standard, but strict `-std=c++NN` breaks the `qiLog*` macros'
  `_QI_LOG_ISEMPTY` trick (~205 cascade errors) — use `gnu++14/17`. Non-NAOqi
  TUs in the same binary may use whatever standard they like; that is the whole
  point of the grpc_naoqi examples' bridge/TU-split pattern.

## Why the sysroots are sourced the way they are

- **Never rebuild old glibc.** The repo's origin story: a crosstool-NG attempt to
  rebuild glibc 2.13 with a modern GCC failed (see the pre-restructure git
  history). The working approach is *reuse*: 2.1 vendors a trimmed byte-for-byte
  copy of the Aldebaran sysroot (redistributable: LGPL glibc + GPL-with-exception
  runtime + gdbserver); GCC is built *against* it, never replacing it.
- **2.8's sysroot is deliberately 100% public.** Robot glibc 2.28 + GCC 8 ==
  exactly Debian 10, so the build sysroot is assembled from checksum-pinned
  `archive.debian.org` debs. This is why 2.8 CI can build the full toolchain
  with no secrets or blobs — keep it that way.
- **The proprietary boundary is absolute.** The Aldebaran CTC (2.1 SDK) and any
  robot rsync (the 2.8 NAOqi stack) must NEVER be committed or included in
  release archives. Examples consume them via `CTC=` / `ROBOT_SYSROOT=` env at
  build time. Release archives were explicitly verified to contain zero NAOqi
  entries — preserve that property.

## Traps already encoded in the code — don't simplify them away

- `naoqi-2.8/sysroot-tools/overlay-lib.sh` `fix_symlinks`: the multiarch bridge
  symlinks must be created **before** the absolute-symlink rewrite loop. Debian's
  dev symlinks are absolute; at link time the OS resolves them against the
  **host** filesystem — on a modern host `-lpthread` silently picks up the
  host's *placeholder* libpthread and libgomp/libatomic configure dies with
  "Pthreads are required". Reordering these loops reintroduces that bug.
- **`ROBOT_SYSROOT` must be passed as `--sysroot`, not merely `-L`**: Debian's
  `libc.so` is a linker *script* with absolute multiarch paths, and ld only
  re-roots script paths when the script lies inside the *active* sysroot.
- **2.1 deploys against the robot's `/opt/aldebaran/lib`, never a copied CTC
  dir**: binaries record boost's plain SONAMEs (`libboost_system.so.1.55.0`) but
  the CTC ships differently-named files (`libboost_system-mt-1_55.so.1.55.0`) —
  the CTC dir cannot satisfy the SONAMEs at runtime.
- **The long boost link line in 2.1 is required**, not cargo cult: modern ld
  defaults to `--no-copy-dt-needed-entries`, so nothing links transitively; the
  set comes from `alproxies-config.cmake`'s `*_DEPENDS`.
- **The examples are CI gates, not demos.** `plain_hello` is built *and run*
  (under the toolchain's own sysroot loader) on every CI toolchain build; the
  grpc_naoqi demos use a stub-swap so the two-TU link is exercised in CI without
  proprietary inputs. Removing stubs, `SKIP_RUN`, or the run steps weakens the
  gate that catches a toolchain that compiles but produces broken binaries.
- **Testing without a robot**: run target binaries on the x86-64 host via the
  *target sysroot's* loader — `$SYSROOT/lib/ld-linux.so.2 --library-path
  $RUNTIME_LIBS:$SYSROOT/lib:... ./bin`. This proves arch + userland ABI + basic
  function (it even carried a live gRPC fetch), but NOT old-kernel behavior —
  kernel-level claims need the physical robot.

## Release invariants

- **The workflow owns releases end-to-end.** Cut releases by pushing a `v*` tag
  only. Creating a release in the GitHub UI publishes it empty → immutable →
  assets can never be attached, **and the tag name is burned permanently** (this
  is why v0.1.0 has no release and v0.1.1 exists).
- `release.yml` must keep the **draft → upload assets → publish** order; that is
  the only sequence immutable releases accept.
- One tag releases **both** toolchains onto **one** release page (the repo
  versions the build system, not a robot generation).

## Git workflow (required — Dave, 2026-07-06)

- All new work happens on a feature branch cut from main and lands via a PR.
  **NEVER push directly to main.** Dave reviews after each feature/milestone lands.
- Scope work so each PR is reviewable — one feature or coherent slice per PR. If a
  change genuinely cannot be split and will be large, check with Dave FIRST.
- Push shape (SSH remote has no keys in the agent environment):
  `git -c credential.helper='!gh auth git-credential' push
  https://github.com/davesnowdon/naoqi-cross-toolchain.git <branch>`, then
  `gh pr create`. Fetch the same way — plain `git fetch origin` fails and the
  local `origin/main` ref goes stale.

## Repo/tooling quirks

- `gh pr edit` fails on this repo (Projects-classic GraphQL deprecation) — edit
  PR bodies with `gh api --method PATCH repos/<owner>/<repo>/pulls/<n> -F body=@file`.
- No AI attribution in commits or PRs (owner preference, enforced in their
  global settings).
- `output/`, `.build/`, `examples/bin/`, `examples/deploy/` are gitignored
  per-tree; example deploy bundles are rebuilt by the `build-*.sh` scripts.

## Validation provenance (don't regress it)

Every headline claim was verified on physical robots (2026-07-03/04): TTS and a
live gRPC-1.60 fetch+speak from a single binary on V4, V5 (kernel 2.6.33 — the
`SO_REUSEPORT` disable in the 2.1 gRPC client is required there) and V6. The
verify scripts' assertions (ELF class, interpreter, glibc ceiling, ABI
direction, GLIBCXX-vs-runtime-libs coverage, run-under-loader) encode exactly
the properties those robots proved; treat any change that relaxes them as a
regression until re-proven on hardware.
