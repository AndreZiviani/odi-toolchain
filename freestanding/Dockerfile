# The freestanding toolchain: Debian gcc-mips-linux-gnu for big-endian MIPS
# o32, plus qemu-user-static to run the results on the build host.
#
# For binaries built -nostdlib -nostartfiles -static -ffreestanding (flags.mk
# has the full set and why the baseline is -march=mips1). The glibc these
# packages come with is never linked, so its age and its ISA do not matter;
# the headers from libc6-dev-mips-cross and linux-libc-dev-mips-cross are
# there for <asm/unistd.h> and friends -- the o32 syscall numbers are not the
# generic ones, and they are worth taking from the kernel headers rather than
# from memory.
#
# qemu-user-static proves logic and syscalls but NOT instruction legality: it
# emulates a full MIPS32 CPU, and mul and clz run fine under it and trap on
# the real RLX5281. isa-audit and isa-allowlist, installed here, are the ISA
# gate.
#
# Build context is the repository root:
#     docker build -f freestanding/Dockerfile -t odi-toolchain-freestanding:local .
#
# Pinned three ways: the base image by digest, apt by snapshot.debian.org
# timestamp, and the packages that decide code generation by exact version,
# so a drift in any of them is a build failure rather than a silently
# different binary.
FROM debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

ARG SNAPSHOT=20260925T000000Z
COPY common/apt-snapshot.sh /usr/local/sbin/apt-snapshot.sh
RUN apt-snapshot.sh "$SNAPSHOT" \
 && apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      gcc-mips-linux-gnu \
      gcc-12-mips-linux-gnu=12.2.0-14cross5 \
      cpp-12-mips-linux-gnu=12.2.0-14cross5 \
      binutils-mips-linux-gnu=2.40-2cross2 \
      libc6-dev-mips-cross=2.36-8cross2 \
      linux-libc-dev-mips-cross=6.1.8-1cross2 \
      qemu-user-static=1:7.2+dfsg-7+deb12u18+b3 \
      make file xxd python3 curl \
 && rm -rf /var/lib/apt/lists/*

COPY isa/isa-audit isa/isa-allowlist /usr/local/bin/
COPY flags.mk /usr/local/share/odi-toolchain/flags.mk

LABEL org.opencontainers.image.source="https://github.com/AndreZiviani/odi-toolchain" \
      org.opencontainers.image.description="Freestanding cross toolchain for the RLX5281 (big-endian MIPS o32): Debian gcc-mips-linux-gnu, qemu-user-static, the ISA audit" \
      org.opencontainers.image.title="odi-toolchain-freestanding"

WORKDIR /src
