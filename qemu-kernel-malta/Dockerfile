# The stock mainline test kernel for odi-oss qemu full-system harness
# (`make test-qemu`, odi-oss docs/HACKING.md): linux-6.18.53, QEMU `-M
# malta`, big-endian MIPS o32, built malta_defconfig + config.fragment with
# the same Debian gcc-mips-linux-gnu cross toolchain as
# odi-toolchain-freestanding. It carries NONE of odi-oss own kernel
# (kernel/extra, the odi_* drivers, the Lexra flags) -- it stands in for
# the board qemu cannot emulate, so odi-oss rootfs can be exercised
# end to end without real hardware.
#
# Published stage is just the two files a boot needs: vmlinux and the
# .config that produced it, on the smallest base that can hold them.
#
# Build context is the repository root:
#     docker build -f qemu-kernel-malta/Dockerfile -t odi-toolchain-qemu-kernel-malta:local .
FROM debian:bookworm@sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26 AS build
ARG SNAPSHOT=20260925T000000Z
ARG JOBS=4
COPY common/apt-snapshot.sh /usr/local/sbin/apt-snapshot.sh
# Same cross-toolchain package set and exact versions as
# freestanding/Dockerfile: one gcc-mips-linux-gnu pin for both images.
RUN apt-snapshot.sh "$SNAPSHOT" \
	&& apt-get update -qq \
	&& apt-get install -y -qq --no-install-recommends \
		gcc-mips-linux-gnu \
		gcc-12-mips-linux-gnu=12.2.0-14cross5 \
		cpp-12-mips-linux-gnu=12.2.0-14cross5 \
		binutils-mips-linux-gnu=2.40-2cross2 \
		libc6-dev-mips-cross=2.36-8cross2 \
		linux-libc-dev-mips-cross=6.1.8-1cross2 \
		build-essential bc bison flex libssl-dev libelf-dev \
		curl ca-certificates xz-utils file \
	&& rm -rf /var/lib/apt/lists/*
COPY qemu-kernel-malta/build.sh qemu-kernel-malta/config.fragment /src/
RUN mkdir -p /out && JOBS="$JOBS" sh /src/build.sh && rm -rf /src/linux-*

FROM debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251
COPY --from=build /out/vmlinux /boot/vmlinux
COPY --from=build /out/config /boot/config

LABEL org.opencontainers.image.source="https://github.com/AndreZiviani/odi-toolchain" \
      org.opencontainers.image.description="Stock mainline Linux 6.18.53 for QEMU -M malta, built for odi-oss's qemu full-system test harness (test-qemu); no odi-oss kernel code" \
      org.opencontainers.image.title="odi-toolchain-qemu-kernel-malta"

WORKDIR /boot
