#!/bin/sh
# build.sh -- fetch, verify and build the stock mainline kernel this image
# publishes: linux-6.18.53 for the QEMU malta board (-M malta), big-endian
# MIPS o32, cross-compiled with the same Debian gcc-mips-linux-gnu as the
# freestanding image. Runs inside qemu-kernel-malta/Dockerfile build stage;
# JOBS sets -j for make.
#
# The tarball URL and SHA-256 are the same pin odi-oss kernel/618/fetch.sh
# uses for its own (different, patched) kernel build -- one upstream
# release, two configurations built from it.
set -eu
JOBS=${JOBS:-4}
VERSION=6.18.53
BASE=https://cdn.kernel.org/pub/linux/kernel/v6.x
TARBALL="linux-$VERSION.tar.xz"
SHA256_XZ=4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0

cd /src
curl -fsSL --retry 3 --max-time 1800 -o "$TARBALL" "$BASE/$TARBALL"
echo "$SHA256_XZ  $TARBALL" | sha256sum -c -
tar xf "$TARBALL"
cd "linux-$VERSION"

export ARCH=mips
export CROSS_COMPILE=mips-linux-gnu-

make malta_defconfig
scripts/kconfig/merge_config.sh -m .config /src/config.fragment
make olddefconfig

make -j"$JOBS" vmlinux

install -D -m 0644 vmlinux /out/vmlinux
install -D -m 0644 .config /out/config
