# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
adapted for this repository's independently versioned image tracks
(`uclibc-vN`, `freestanding-vN`, `qemu-malta-vN`). Entries below are grouped
by track, newest first within each track, because the tracks change for
unrelated reasons (a uClibc-ng bump versus a Debian toolchain bump versus a
kernel.org release) and reading them interleaved by date would mix those
stories together.

## Unreleased

## qemu-malta-v1 (2026-09-27)

### Added
- First release: a STOCK mainline linux-6.18.53 for QEMU `-M malta`,
  `malta_defconfig` + `qemu-kernel-malta/config.fragment` (initramfs,
  devtmpfs/tmpfs, pcnet32/virtio-net, big-endian to match odi-oss's own
  rootfs binaries -- malta_defconfig defaults to little-endian, which
  would refuse to exec the first big-endian ELF), built with the same
  `gcc-mips-linux-gnu` cross toolchain as `odi-toolchain-freestanding`.
  Published stage is just `vmlinux` and the `.config` that produced it --
  no odi-oss kernel code, no odi_* driver, nothing Lexra-specific.
- Built for odi-oss's qemu full-system test harness (`make test-qemu`,
  odi-oss `docs/HACKING.md`): odi-oss boots its own rootfs unmodified on
  top of this kernel, standing in for the RTL9602C board qemu cannot
  emulate.
- Boot-tested locally: odi-oss's own prebuilt big-endian busybox as
  `rdinit`, `qemu-system-mips -M malta -m 64M`, reaches a shell and prints
  `/proc/cpuinfo` (MIPS 24Kc, the qemu malta CPU model) before a clean
  `poweroff`.

## uclibc-v2 (2026-09-25)

Pinned digest: `sha256:5305427b3e87eb2e3f2416778e68cbbb46c3f8b3dfb1317b52eedad803115910`

### Changed
- Minimal published stage: the compiler is now built in a stage that is
  never published; the final stage is `bookworm-slim` with only the host
  tools a kernel/package build calls, the runtime halves of the
  gmp/mpfr/mpc/isl `-dev` packages, and `/opt/oss` with its host programs
  stripped (`cc1`, `lto1`, `lto-dump` were 300 MB each with debug info).
  Target libraries and crt objects are untouched, so nothing linked into a
  binary changes -- confirmed byte-for-byte identical rebuilds against v1.
- `uclibc/build.sh` now sends each configure/make step to a log file and
  prints only a failing tail, since v1 clipped the CI log at the 2 MiB
  BuildKit limit before the library audit result printed.
- On a local amd64 build, the image goes from 749 MB to 196 MB compressed.

## uclibc-v1 (2026-09-25)

Pinned digest: `sha256:804c8b4b30d61c93663a6bf3986c075680bb1894d81a95d0fff4738ef4472ed1`

### Added
- First release: binutils 2.47 with the Lexra opcodes, gcc 16.2.0,
  uClibc-ng 1.0.59 at `/opt/oss`, with Linux 6.18.53 UAPI headers from a
  pinned kernel.org tarball. Moved from odi-oss `toolchain/`
  (`build-oss-toolchain.sh`, `Dockerfile.oss`, `audit-toolchain.sh` and the
  patches), unchanged in what it builds; the target-library audit now runs
  inside the image build and fails it on a trapping instruction.
- `isa/isa-audit` and `isa/isa-allowlist`, merging the odi-oss deny/allow
  lists with the floating-point check from the sfp-exporter census,
  installed in the image.
- Every source pinned by URL and SHA-256, the base image by digest, apt by
  snapshot.debian.org timestamp, and code-generating Debian packages by
  version.

## freestanding-v2 (2026-09-25)

Pinned digest: `sha256:a0342d9662553d725b29be891d5647393f76768c7cf3decb34b4f4bb2e0de611`

### Changed
- Minimal published stage: `qemu-mips-static` alone instead of the 370 MB
  `qemu-user-static` package, `python3-minimal` for the odi-ui smoke test,
  and no `xxd` or full python, none of which anything runs in the
  container.
- On a local amd64 build, the image goes from 184 MB to 89 MB compressed.
  Same compiler as v1; an odi-oss image built with it is identical file
  for file to one built with v1, and odi-sfp-exporter v1.0.3 and odi-ui
  v1.0.4 still rebuild byte-for-byte to their releases.

## freestanding-v1 (2026-09-25)

Pinned digest: `sha256:e1e6ae4da43a9246347b39a50241a2eca953e383e7c5624492d82c034ec90686`

### Added
- First release: Debian bookworm `gcc-mips-linux-gnu`, binutils and
  `qemu-user-static`, one Dockerfile replacing three near-identical ones
  (odi-oss `src/diag/Dockerfile`, sfp-exporter and odi-ui).
- `flags.mk` records the two ISA baselines and why they differ: `mips1`
  for freestanding code, which must run on the stock OEM image too, and
  `mips2` with the `teq`/branch-likely suppressions for uClibc-ng, which
  needs `ll`/`sc`.
- CI (`.github/workflows/ci.yml`) lints and self-tests on every push, and
  a `uclibc-v*` or `freestanding-v*` tag publishes to ghcr.io.
