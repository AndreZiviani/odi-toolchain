# odi-toolchain

Part of [odi-oss](https://github.com/AndreZiviani/odi-oss), the open
firmware for the ODI DFP-34X-2C2 GPON SFP stick.

The stick's CPU, a Realtek RLX5281 (a Lexra core, not a standard MIPS
implementation), traps on several MIPS instructions that stock
cross-compilers emit freely (`mul`, `clz`, branch-likely, and others — see
"The CPU, in one paragraph" below). Every binary shipped to the stick is
therefore built with pinned compiler flags and audited afterwards for
forbidden instructions. odi-oss needs a uClibc-ng toolchain targeting that
CPU plus a matching kernel build, and its freestanding userland tools
(`diag`, `nv`, `omcid`, `confd`, `metricsd`, ...) need a small, reproducible
build image. Building gcc, binutils and uClibc-ng from source takes about
45 minutes, so this repository publishes the results as prebuilt container
images, pinned by digest, shared by odi-oss, odi-ui and odi-sfp-exporter.

| image | what it is | used by |
|---|---|---|
| `ghcr.io/andreziviani/odi-toolchain-uclibc` | our own binutils 2.47 (with the Lexra opcodes), gcc 16.2.0 and uClibc-ng 1.0.59, `mips-linux-uclibc`, prefix `/opt/oss`, Linux 6.18 UAPI headers; plus the host tools a kernel build needs | odi-oss: the kernel, busybox, dropbear, iproute2 |
| `ghcr.io/andreziviani/odi-toolchain-freestanding` | Debian bookworm `gcc-mips-linux-gnu` + binutils + `qemu-mips-static`, for `-nostdlib` binaries | odi-oss `src/` (diag, nv, omcid, ...), odi-sfp-exporter (`metricsd`), odi-ui (`confd`) |
| `ghcr.io/andreziviani/odi-toolchain-qemu-kernel-malta` | a STOCK mainline Linux 6.18.53, `malta_defconfig` + `qemu-kernel-malta/config.fragment`, built with the same `gcc-mips-linux-gnu` as the freestanding image -- just `vmlinux` and its `.config`, no odi-oss kernel code at all | odi-oss `make test-qemu`: boots the real rootfs under `qemu-system-mips -M malta`, standing in for the RTL9602C board qemu cannot emulate |

Both toolchain images carry the shared ISA gate, `isa-audit` and
`isa-allowlist` (`isa/`), and `flags.mk`, the target flags with the
reasoning behind them; the qemu kernel image carries neither, since it
never runs odi-oss code, only odi-oss's rootfs on top of a stock kernel.

Both are **minimal**: they carry what it takes to use the toolchain, not
what it took to build it, so a consumer pulls a fraction of the build. The
uclibc image is `debian:bookworm-slim` with the stripped `/opt/oss` (the
host programs only -- the target libraries are untouched), the runtime
libraries `cc1` links against and the host tools a kernel build calls; the
compiler build happens in a stage that is never published. The freestanding
image carries one emulator, `qemu-mips-static`, out of the 370 MB
`qemu-user-static` package, and no python beyond `python3-minimal`.

## Using an image

Pin the **digest**, not the tag. A tag can be moved; a digest names exactly
one set of bytes, so a build that pulls it is the build that was verified.
Each consumer keeps its pin in one place:

    ghcr.io/andreziviani/odi-toolchain-freestanding:v2@sha256:<digest>

The digests of every published version are in the summary of the
`publish` job that built it (Actions, the tag run). Pull and use:

    docker pull ghcr.io/andreziviani/odi-toolchain-freestanding:v2@sha256:<digest>
    docker run --rm -v "$PWD":/src -w /src <that ref> make ...

The uclibc image is `linux/amd64` only (building gcc under arm64 emulation
does not fit a hosted runner); on an Apple Silicon Mac Docker runs it under
emulation, correctly and slower. The freestanding image is `linux/amd64` and
`linux/arm64`.

The packages are public: an anonymous pull by digest works, no login or
token needed. A token is only useful to raise the anonymous rate limit:

    echo "$TOKEN" | docker login ghcr.io -u <github user> --password-stdin

## Building an image locally

Every image can be built from this repository instead of pulled -- the
fallback when the registry is unreachable, and the way to test a change here:

    make freestanding      # odi-toolchain-freestanding:local, about two minutes
    make uclibc            # odi-toolchain-uclibc:local, about an hour (JOBS=4)
    make qemu-kernel-malta  # odi-toolchain-qemu-kernel-malta:local, about ten minutes (JOBS=4)
    make test              # the ISA audit self-test, in the freestanding image
    make lint

A consumer then uses the local tag in place of its pinned reference (each
consumer documents the variable). A local build is the same recipe but not
the same image: its digest differs from the published one, since layer
timestamps differ. The binaries it produces are the same: odi-sfp-exporter
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

## Versions

| tag | reference | notes |
|---|---|---|
| `uclibc-v2` | `ghcr.io/andreziviani/odi-toolchain-uclibc:v2@sha256:5305427b3e87eb2e3f2416778e68cbbb46c3f8b3dfb1317b52eedad803115910` | minimal: bookworm-slim final stage, host programs stripped; same target libraries as v1 |
| `freestanding-v2` | `ghcr.io/andreziviani/odi-toolchain-freestanding:v2@sha256:a0342d9662553d725b29be891d5647393f76768c7cf3decb34b4f4bb2e0de611` | minimal: `qemu-mips-static` only, `python3-minimal`; same compiler as v1 |
| `qemu-malta-v1` | `ghcr.io/andreziviani/odi-toolchain-qemu-kernel-malta:v1@<see the tag run's job summary>` | first release: linux-6.18.53, `malta_defconfig` + `qemu-kernel-malta/config.fragment`, `vmlinux` + `.config` only |
| `uclibc-v1` | `ghcr.io/andreziviani/odi-toolchain-uclibc:v1@sha256:804c8b4b30d61c93663a6bf3986c075680bb1894d81a95d0fff4738ef4472ed1` | first release; superseded by v2 |
| `freestanding-v1` | `ghcr.io/andreziviani/odi-toolchain-freestanding:v1@sha256:e1e6ae4da43a9246347b39a50241a2eca953e383e7c5624492d82c034ec90686` | first release; superseded by v2 |

Every row builds the same binaries: an odi-oss image built with v1 or v2
is identical file for file to one built with the toolchain these images
replaced, build timestamps aside, and odi-sfp-exporter v1.0.3 and odi-ui v1.0.4
rebuild byte-for-byte to their releases.

## Releasing

    git tag -s freestanding-v3 && git push origin freestanding-v3
    git tag -s uclibc-v3 && git push origin uclibc-v3
    git tag -s qemu-malta-v2 && git push origin qemu-malta-v2

The workflow builds and pushes the image and prints its digest; update the
pin in each consumer by hand, in its own branch, and rebuild there. Versions
are plain integers and never reused.

## Layout

    uclibc/Dockerfile              the uclibc image: a build stage, then slim base + stripped /opt/oss
    uclibc/build.sh                binutils, headers, gcc (two stages), uClibc-ng
    uclibc/audit-libs.sh           the target-library audit; odi-audit-libs in the image
    uclibc/patches/                binutils (the Lexra opcodes) and uClibc-ng patches
    qemu-kernel-malta/Dockerfile   the qemu kernel image: cross-gcc build stage, then just vmlinux + .config
    qemu-kernel-malta/build.sh     fetch, verify, malta_defconfig + fragment, build vmlinux
    qemu-kernel-malta/config.fragment  the overrides on top of malta_defconfig (initramfs, net, console)
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
project and are GPL-2.0-or-later, like the rest of the odi-oss tree; see
[`LICENSE`](LICENSE).
