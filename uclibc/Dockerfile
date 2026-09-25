# The uClibc-ng toolchain for the RLX5281: binutils 2.47 (with the Lexra
# opcodes), gcc 16.2.0 and uClibc-ng 1.0.59, targeting mips-linux-uclibc,
# big-endian, o32, soft float, prefix /opt/oss. uclibc/build.sh has the why
# of every choice; flags.mk has the target flags.
#
# Also the container everything linked against it is built in -- the kernel
# included -- so the published stage keeps the host build tools: bc for
# timeconst, mkimage for the uImage, kmod for the module tools.
#
# Build context is the repository root:
#     docker build -f uclibc/Dockerfile -t odi-toolchain-uclibc:local .
# About an hour on four cores; JOBS sets the parallelism.
#
# The library audit (uclibc/audit-libs.sh) runs as part of the build, so an
# image with an illegal instruction in libc.a or libgcc.a cannot be produced.

# Two bases. The build stage has everything it takes to compile gcc; the
# published stage has only what it takes to USE the result -- the stripped
# /opt/oss, the libraries cc1 links against, and the host tools the kernel
# and package builds call -- so a consumer pulls a fraction of it.

FROM debian:bookworm@sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26 AS build
ARG SNAPSHOT=20260925T000000Z
ARG JOBS=4
COPY common/apt-snapshot.sh /usr/local/sbin/apt-snapshot.sh
RUN apt-snapshot.sh "$SNAPSHOT" \
	&& apt-get update -qq \
	&& apt-get install -y -qq --no-install-recommends \
		build-essential bison flex texinfo \
		libgmp-dev libmpfr-dev libmpc-dev libisl-dev zlib1g-dev \
		curl ca-certificates xz-utils bzip2 file rsync python3 perl patch \
		gawk \
	&& rm -rf /var/lib/apt/lists/*
COPY uclibc/build.sh uclibc/audit-libs.sh /src/
COPY uclibc/patches /src/patches
# One layer: the work tree (several GB of objects) is deleted in the same
# step that makes it, so it never reaches a layer.
RUN JOBS="$JOBS" bash /src/build.sh \
	&& bash /src/audit-libs.sh \
	&& rm -rf /opt/oss/work /dl

# What a consumer runs. The host tools are the ones the kernel and the
# package builds use: a host C compiler for kbuild and kconfig, bison and
# flex, bc for timeconst, perl, mkimage for the uImage, kmod, xz for the lzma
# kernel compression, and the usual text tools; the math libraries are the
# runtime halves of the -dev packages above.
FROM debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251
ARG SNAPSHOT=20260925T000000Z
COPY common/apt-snapshot.sh /usr/local/sbin/apt-snapshot.sh
RUN apt-snapshot.sh "$SNAPSHOT" \
	&& apt-get update -qq \
	&& apt-get install -y -qq --no-install-recommends \
		build-essential bison flex bc perl patch gawk file \
		xz-utils bzip2 u-boot-tools kmod \
		libgmp10 libmpfr6 libmpc3 libisl23 zlib1g \
	&& rm -rf /var/lib/apt/lists/*
COPY --from=build /opt/oss /opt/oss
COPY uclibc/audit-libs.sh /usr/local/bin/odi-audit-libs
COPY isa/isa-audit isa/isa-allowlist /usr/local/bin/
COPY flags.mk /usr/local/share/odi-toolchain/flags.mk
ENV PATH=/opt/oss/bin:$PATH
# A missing runtime library would only show on the first compile; refuse it
# here instead, and prove the compiler runs.
RUN ! find /opt/oss/bin /opt/oss/libexec -type f -exec ldd {} + 2>/dev/null | grep "not found" \
	&& mips-linux-uclibc-gcc --version | head -1

LABEL org.opencontainers.image.source="https://github.com/AndreZiviani/odi-toolchain" \
      org.opencontainers.image.description="uClibc-ng cross toolchain for the RLX5281: binutils 2.47 with the Lexra opcodes, gcc 16.2.0, uClibc-ng 1.0.59, Linux 6.18 headers; prefix /opt/oss" \
      org.opencontainers.image.title="odi-toolchain-uclibc"

WORKDIR /work
