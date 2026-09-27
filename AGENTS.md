# AGENTS.md

Guidance for any coding agent (or human) working in this repository. Read
`README.md` first for what the images are and who uses them; this file is
about changing them without breaking a consumer.

## What this is

Two container images, built from this repository by CI and pulled by digest
by three projects: odi-oss (the firmware image), odi-sfp-exporter (`metricsd`)
and odi-ui (`confd`). Nothing here builds a firmware or a binary for the
stick; it builds the compilers that do.

## Build and test commands

    make lint           # shellcheck + the no-apostrophe-in-comments rule
    make freestanding   # the freestanding image, :local
    make test           # builds it, then runs test/run.sh inside it
    make uclibc         # the uclibc image, :local -- about an hour

CI (`.github/workflows/ci.yml`) runs lint and `make test` on every push and
pull request; the uclibc image is built on a tag, or on demand through
workflow_dispatch with `uclibc: true`.

## House rules

- **A published version is immutable.** Never move or reuse a tag
  (`uclibc-v<N>`, `freestanding-v<N>`). A change is a new integer, and each
  consumer moves its digest pin in its own reviewed branch. Consumers pin
  the digest, so a moved tag would not even reach them -- it would only make
  the tag lie.
- **Anything that changes code generation is a new version and a rebuild
  check in every consumer.** That means a compiler, binutils or libc
  version, a configure flag, a uClibc-ng `.config` line, a patch, the kernel
  headers, or a pinned Debian package. The check is: rebuild the consumer
  with the new image and compare its binaries to the ones built with the
  old one -- identical, or every difference explained.
- **The target flags must reach the libraries.** `-march=mips2
  -mno-branch-likely -mdivide-breaks` is baked into gcc and passed as
  `CFLAGS_FOR_TARGET`; `uclibc/audit-libs.sh` runs inside the image build
  and fails it on any trapping instruction in `libc.a` or `libgcc.a`. Never
  weaken that step to get a build through.
- **The ISA allowlist grows only by execution on the device**, never from a
  datasheet or an ISA level. An unverified mnemonic is exit 2 from
  `isa-allowlist`: execute it on a stick, then add it to `ALLOW` in
  `isa/isa-audit` with the date and what was run. `flags.mk` and
  `isa/isa-audit` explain the two baselines (mips1 freestanding, mips2 for
  uClibc-ng); do not unify them without a measurement that says otherwise.
- **Pin every input.** Sources by URL and SHA-256, base images by digest,
  apt by snapshot timestamp. A new source without a pinned hash is refused
  by `fetch()` in `uclibc/build.sh`, on purpose.
- **This repository is meant to be public.** No tokens or credentials, no
  private paths (home directories, investigation workspaces, internal
  hostnames), no vendor SDK or firmware source and no text derived from it.
  Describing how the stock firmware or its binaries behave, observed as a
  black box, is fine. A registry login is an optional step for the period
  the packages are private; never make a script depend on one.
- **No apostrophes in shell-script comments.** One inside a single-quoted
  inline block (`bash -c '...'`) ends the block and runs the rest of the
  line in the outer shell. `make lint` enforces it; rephrase, do not escape.
- **Scripts run on macOS and Linux hosts**, but everything that compiles
  runs inside an image, where the environment is Debian bookworm.
- **Every change that affects users, the build, or the docs adds an entry
  under `## Unreleased` in `CHANGELOG.md`**, in the same commit as the
  change. A release moves `Unreleased` into a version section named after
  the tag that publishes it.

## Commit style

Imperative subject naming the area (`uclibc:`, `freestanding:`, `isa:`,
`ci:`, `docs:`), a body that says why. Signed commits.
