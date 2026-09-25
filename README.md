# odi-toolchain

The cross toolchains for the ODI DFP-34X-2C2 GPON SFP stick (RTL9601C /
RTL9602C class, a Lexra **RLX5281** big-endian MIPS core), published as
container images so the projects that build for it pull one pinned image
instead of each building its own.

| image | what it is | used by |
|---|---|---|
| `ghcr.io/andreziviani/odi-toolchain-uclibc` | our own binutils 2.47 (with the Lexra opcodes), gcc 16.2.0 and uClibc-ng 1.0.59, `mips-linux-uclibc`, prefix `/opt/oss`, Linux 6.18 UAPI headers; plus the host tools a kernel build needs | odi-oss: the kernel, busybox, dropbear, iproute2 |
| `ghcr.io/andreziviani/odi-toolchain-freestanding` | Debian bookworm `gcc-mips-linux-gnu` + binutils + `qemu-user-static`, for `-nostdlib` binaries | odi-oss `src/` (diag, nv, omcid, ...), sfp-exporter (`metricsd`), odi-ui (`confd`) |

Both images carry the shared ISA gate, `isa-audit` and `isa-allowlist`
(`isa/`), and `flags.mk`, the target flags with the reasoning behind them.

## Using an image

Pin the **digest**, not the tag. A tag can be moved; a digest names exactly
one set of bytes, so a build that pulls it is the build that was verified.
Each consumer keeps its pin in one place:

    ghcr.io/andreziviani/odi-toolchain-freestanding:v1@sha256:<digest>

The digests of every published version are in the summary of the
`publish` job that built it (Actions, the tag run). Pull and use:

    docker pull ghcr.io/andreziviani/odi-toolchain-freestanding:v1@sha256:<digest>
    docker run --rm -v "$PWD":/src -w /src <that ref> make ...

The uclibc image is `linux/amd64` only (building gcc under arm64 emulation
does not fit a hosted runner); on an Apple Silicon Mac Docker runs it under
emulation, correctly and slower. The freestanding image is `linux/amd64` and
`linux/arm64`.

**While the packages are private** a pull needs a login first, with a token
that has `read:packages`:

    echo "$TOKEN" | docker login ghcr.io -u <github user> --password-stdin

Nothing in this repository or its consumers depends on that login; once the
packages are public an anonymous pull by digest works.

## Building an image locally

Every image can be built from this repository instead of pulled -- the
fallback when the registry is unreachable, and the way to test a change here:

    make freestanding    # odi-toolchain-freestanding:local, about two minutes
    make uclibc          # odi-toolchain-uclibc:local, about an hour (JOBS=4)
    make test            # the ISA audit self-test, in the freestanding image
    make lint

A consumer then uses the local tag in place of its pinned reference (each
consumer documents the variable). A local build is the same recipe but not
the same image: its digest differs from the published one, since layer
timestamps differ. The binaries it produces are the same: sfp-exporter
v1.0.3 and odi-ui v1.0.4 rebuild byte-for-byte identical to their releases
with it.

## What is pinned

- **Sources** by URL and SHA-256 (`uclibc/build.sh`): binutils, gcc and
  uClibc-ng, and the kernel.org Linux 6.18 release the UAPI headers come
  from. The GNU tarballs were checked against their signatures when pinned.
- **Base images** by digest.
- **Debian packages** by snapshot.debian.org timestamp (`SNAPSHOT` in each
  Dockerfile, `common/apt-snapshot.sh`), and in the freestanding image the
  packages that decide code generation also by exact version, so drift is a
  build failure rather than a quietly different binary.

## The CPU, in one paragraph

The RLX5281 implements ISA levels in pieces. Measured by executing each
instruction on the device: `lwl lwr swl swr`, `movz movn`, `ll sc sync`,
`bltzl` and `madd` run; `mul`, `clz`, `teq`, `beql` and `bnel` trap. So the
freestanding baseline is `-march=mips1`, which can emit none of the five and
runs on the stock OEM image too, and the uClibc baseline is `-march=mips2
-mno-branch-likely -mdivide-breaks`, which keeps `ll`/`sc` for the libc and
suppresses the rest -- in the target libraries as well as the application,
which the uclibc image build proves by auditing `libc.a` and `libgcc.a`
before it can finish. `flags.mk` has the full argument. Neither baseline is
trusted on its own: every binary goes through `isa-audit` (deny list,
disassembled at mips32 so a stray `mul` decodes) and `isa-allowlist` (only
mnemonics confirmed on the hardware).

## Releasing

    git tag -s freestanding-v2 && git push origin freestanding-v2
    git tag -s uclibc-v2 && git push origin uclibc-v2

The workflow builds and pushes the image and prints its digest; update the
pin in each consumer by hand, in its own branch, and rebuild there. Versions
are plain integers and never reused.

## Layout

    uclibc/Dockerfile        the uclibc image: build stage, then base + /opt/oss
    uclibc/build.sh          binutils, headers, gcc (two stages), uClibc-ng
    uclibc/audit-libs.sh     the target-library audit; odi-audit-libs in the image
    uclibc/patches/          binutils (the Lexra opcodes) and uClibc-ng patches
    freestanding/Dockerfile  the freestanding image
    isa/isa-audit            the ISA gate; isa-allowlist is the same script
    flags.mk                 target flags for both baselines, and why
    common/apt-snapshot.sh   freezes apt at a snapshot.debian.org timestamp
    test/run.sh              ISA audit self-test (make test)
    .github/workflows/ci.yml lint + self-test on every push; publish on tags

## Licensing

The components keep their upstream licenses: gcc and binutils GPL-3.0 (gcc
with the runtime library exception), uClibc-ng LGPL-2.1, the Linux UAPI
headers GPL-2.0 with the syscall-note exception, the Debian packages their
own. `uclibc/patches/binutils/` is a change to binutils and is GPL-3.0 like
it; `uclibc/patches/uclibc-ng/` is LGPL-2.1 like uClibc-ng. The build
scripts, Dockerfiles, the ISA audit and the docs are written for this
project and, like the rest of the odi-oss tree, carry no license grant yet:
that is a decision for the maintainer, not one to infer from its absence.
