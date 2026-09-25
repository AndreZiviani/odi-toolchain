# The uClibc-ng toolchain for the RLX5281: binutils 2.47 (with the Lexra
# opcodes), gcc 16.2.0 and uClibc-ng 1.0.59, targeting mips-linux-uclibc,
# big-endian, o32, soft float, prefix /opt/oss. uclibc/build.sh has the why
# of every choice; flags.mk has the target flags.
#
# Also the container everything linked against it is built in -- the kernel
# included -- so the final stage keeps the host build tools: bc for
# timeconst, mkimage for the uImage, kmod for the module tools.
#
# Build context is the repository root:
#     docker build -f uclibc/Dockerfile -t odi-toolchain-uclibc:local .
# About an hour on four cores; JOBS sets the parallelism.
#
# The library audit (uclibc/audit-libs.sh) runs as part of the build, so an
# image with an illegal instruction in libc.a or libgcc.a cannot be produced.

FROM debian:bookworm@sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26 AS base
ARG SNAPSHOT=20260925T000000Z
COPY common/apt-snapshot.sh /usr/local/sbin/apt-snapshot.sh
RUN apt-snapshot.sh "$SNAPSHOT" \
	&& apt-get update -qq \
	&& apt-get install -y -qq --no-install-recommends \
		build-essential bison flex texinfo \
		libgmp-dev libmpfr-dev libmpc-dev libisl-dev zlib1g-dev \
		curl ca-certificates xz-utils bzip2 file rsync python3 perl patch \
		gawk \
		bc u-boot-tools kmod \
	&& rm -rf /var/lib/apt/lists/*

FROM base AS build
ARG JOBS=4
COPY uclibc/build.sh uclibc/audit-libs.sh /src/
COPY uclibc/patches /src/patches
# One layer: the work tree (several GB of objects) is deleted in the same
# step that makes it, so it never reaches a layer.
RUN JOBS="$JOBS" bash /src/build.sh \
	&& bash /src/audit-libs.sh \
	&& rm -rf /opt/oss/work /dl

FROM base
COPY --from=build /opt/oss /opt/oss
COPY uclibc/audit-libs.sh /usr/local/bin/odi-audit-libs
COPY isa/isa-audit isa/isa-allowlist /usr/local/bin/
COPY flags.mk /usr/local/share/odi-toolchain/flags.mk
ENV PATH=/opt/oss/bin:$PATH

LABEL org.opencontainers.image.source="https://github.com/AndreZiviani/odi-toolchain" \
      org.opencontainers.image.description="uClibc-ng cross toolchain for the RLX5281: binutils 2.47 with the Lexra opcodes, gcc 16.2.0, uClibc-ng 1.0.59, Linux 6.18 headers; prefix /opt/oss" \
      org.opencontainers.image.title="odi-toolchain-uclibc"

WORKDIR /work
