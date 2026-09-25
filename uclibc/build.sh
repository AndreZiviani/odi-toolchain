#!/usr/bin/env bash
#
# Build the uClibc-ng cross toolchain for the RLX5281: binutils, gcc and
# uClibc-ng, from current free software, into /opt/oss. Runs INSIDE the image
# build (uclibc/Dockerfile); it is not meant to be run on a host.
#
# WHY our own, rather than a vendor prebuilt toolchain (gcc 4.4.5 and uClibc
# 0.9.30.3, both from 2010): that libc has holes that cost real
# functionality. busybox had to give up nslookup, fallocate, nsenter, unshare
# and sync -F for missing symbols; dropbear needed openpty disabled; iproute2
# needed a hand-written unshare wrapper; and root passwords were stuck on MD5
# crypt because that libc has no SHA-512. gcc 4.4.5 is a second, independent
# ceiling: it cannot compile C11 anonymous struct or union members at all,
# which is what stops iproute2 newer than 5.10.
#
# THE TARGET ISA, which is the whole difficulty. The RLX5281 is a Lexra core
# that implements ISA levels in pieces. Measured by executing each instruction
# on the device:
#
#     ok:       lwl lwr swl swr, movz movn, ll sc sync, bltzl, madd
#     ILLEGAL:  mul, clz, teq, beql, bnel
#
# So the target is mips2 -- which gives the libc native ll/sc atomics -- with
# the three illegal MIPS-II instructions suppressed by flags (flags.mk has
# the same set, for consumers):
#
#     -march=mips2        no mul, no clz (those are SPECIAL2/mips32)
#     -mno-branch-likely  no beql/bnel
#     -mdivide-breaks     break instead of teq for divide-by-zero
#
# THE TRAP THAT SANK AN EARLIER ATTEMPT: those flags must reach the TARGET
# LIBRARIES, not just the final compile. A crosstool-NG build with the flags
# applied only to the application left 64 teq in libgcc.a and 95 in libc.a.
# Here they are baked into the gcc configuration (--with-arch) AND passed as
# CFLAGS_FOR_TARGET, and uclibc/audit-libs.sh checks the built libraries
# rather than trusting either -- the image build fails if it finds one.
#
# Kernel headers come from a pristine kernel.org Linux 6.18 release, the
# kernel this toolchain builds, so no header declares a syscall that kernel
# lacks. headers_install exports only the UAPI headers, which the device
# kernel patches do not touch.
set -euo pipefail

BINUTILS=2.47
BINUTILS_SHA256=154ab23b60070e8f27013c22977f1129425d67d1e8acd6e13010e617811e4cff
GCC=16.2.0
GCC_SHA256=e6738e29597f733270731aa90600f37ffdc045079dfc27ec7e8192cc81085c3e
UCLIBC=1.0.59
UCLIBC_SHA256=86c6f15971bfb14156850f2e36906dac5a69df7b3e688216d1aea09d2db54174
LINUX=6.18.53
LINUX_SHA256=4d6fba95c2244b08a7b4144a4d38b9be4fb31abb5e7682ae40bb5cb11374cfe0

TARGET=mips-linux-uclibc
PREFIX=${PREFIX:-/opt/oss}
SYSROOT=$PREFIX/$TARGET/sysroot
# Inside the prefix, as it always was: the build paths end up in debug
# strings and assert messages of the target libraries, and keeping them
# unchanged keeps the libraries byte-identical to earlier builds. The image
# build deletes it before the prefix is copied into the final stage.
WORK=${WORK:-$PREFIX/work}
DL=${DL:-/dl}
JOBS=${JOBS:-4}
SRC=${SRC:-$(cd "$(dirname "$0")" && pwd)}

# The target flags, in one place. TFLAGS reaches every target library.
TARCH="-march=mips2 -mno-branch-likely -mdivide-breaks"
TFLAGS="$TARCH -Os -mabi=32 -EB -msoft-float"

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
# Every configure and make goes through this: the full output lands in
# $WORK/logs, and only a failure prints its tail. A gcc build writes tens of
# megabytes of command lines, which clips the CI log (BuildKit stops at
# 2 MiB) long before the audit result that matters is printed.
LOGS=$WORK/logs
q() {
	name=$1; shift
	mkdir -p "$LOGS"
	echo "  $name"
	if ! "$@" > "$LOGS/$name.log" 2>&1; then
		echo "FAILED: $name -- last lines of $LOGS/$name.log:" >&2
		tail -60 "$LOGS/$name.log" >&2
		exit 1
	fi
}
die()  { echo "$*" >&2; exit 1; }
have() { [ -e "$1" ]; }

mkdir -p "$WORK" "$PREFIX" "$SYSROOT" "$DL"
export PATH=$PREFIX/bin:$PATH

# Every source is fetched by URL and refused unless its SHA-256 matches.
fetch() {
	url=$1; sha=$2; f=$DL/$(basename "$url")
	[ -n "$sha" ] || die "no sha256 pinned for $url"
	if [ ! -f "$f" ]; then
		echo "fetching $(basename "$url")" >&2
		curl -fsSL --retry 5 -o "$f.part" "$url"
		mv "$f.part" "$f"
	fi
	got=$(sha256sum "$f" | cut -d' ' -f1)
	[ "$got" = "$sha" ] || die "sha256 mismatch for $f: $got, want $sha"
	echo "$f"
}

# ---------------------------------------------------------------- 1. binutils
if ! have "$PREFIX/bin/$TARGET-as"; then
	say "binutils $BINUTILS"
	t=$(fetch "https://ftpmirror.gnu.org/gnu/binutils/binutils-$BINUTILS.tar.xz" "$BINUTILS_SHA256")
	rm -rf "$WORK/binutils"; mkdir -p "$WORK/binutils"
	tar xf "$t" -C "$WORK/binutils" --strip-components=1
	# The Lexra opcodes the RLX5281 has and no binutils ever had.
	for pat in "$SRC"/patches/binutils/*.patch; do
		[ -f "$pat" ] || continue
		echo "  patch: $(basename "$pat")"
		patch -d "$WORK/binutils" -p1 --batch --forward < "$pat"
	done
	mkdir -p "$WORK/build-binutils"; cd "$WORK/build-binutils"
	q binutils-configure "$WORK/binutils/configure" \
		--target="$TARGET" --prefix="$PREFIX" --with-sysroot="$SYSROOT" \
		--disable-nls --disable-werror --disable-multilib
	q binutils-make make -j"$JOBS"
	q binutils-install make install
	cd /
fi

# ------------------------------------------------------- 2. kernel headers
if ! have "$SYSROOT/usr/include/linux/unistd.h"; then
	say "kernel headers from Linux $LINUX"
	t=$(fetch "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$LINUX.tar.xz" "$LINUX_SHA256")
	rm -rf "$WORK/ktree"; mkdir -p "$WORK/ktree"
	tar xf "$t" -C "$WORK/ktree" --strip-components=1
	mkdir -p "$SYSROOT/usr"
	make -C "$WORK/ktree" ARCH=mips INSTALL_HDR_PATH="$SYSROOT/usr" \
		headers_install >/dev/null
	rm -rf "$WORK/ktree"
fi

# -------------------------------------------------------- 3. gcc, stage one
gcc_src() {
	have "$WORK/gcc/configure" && return
	t=$(fetch "https://ftpmirror.gnu.org/gnu/gcc/gcc-$GCC/gcc-$GCC.tar.xz" "$GCC_SHA256")
	rm -rf "$WORK/gcc"; mkdir -p "$WORK/gcc"
	tar xf "$t" -C "$WORK/gcc" --strip-components=1
	# gmp, mpfr, mpc and isl come from the image (uclibc/Dockerfile), not
	# from download_prerequisites: one less network fetch that can fail.
}

GCC_COMMON="--target=$TARGET --prefix=$PREFIX --with-sysroot=$SYSROOT
	--with-arch=mips2 --with-abi=32 --with-float=soft --with-endian=big
	--disable-multilib --disable-nls --disable-libssp --disable-libgomp
	--disable-libmudflap --disable-libquadmath --disable-libsanitizer"

if ! have "$PREFIX/bin/$TARGET-gcc"; then
	say "gcc $GCC, stage one (C only, no libc yet)"
	gcc_src
	mkdir -p "$WORK/build-gcc1"; cd "$WORK/build-gcc1"
	# shellcheck disable=SC2086  # GCC_COMMON is a deliberate word list
	q gcc1-configure "$WORK/gcc/configure" $GCC_COMMON \
		--enable-languages=c --without-headers --with-newlib \
		--disable-shared --disable-threads --disable-libatomic \
		CFLAGS_FOR_TARGET="$TFLAGS"
	q gcc1-make make -j"$JOBS" all-gcc all-target-libgcc
	q gcc1-install make install-gcc install-target-libgcc
	cd /
fi

# ------------------------------------------------------------- 4. uClibc-ng
if ! have "$SYSROOT/usr/lib/libc.a"; then
	say "uClibc-ng $UCLIBC"
	t=$(fetch "https://downloads.uclibc-ng.org/releases/$UCLIBC/uClibc-ng-$UCLIBC.tar.xz" "$UCLIBC_SHA256")
	rm -rf "$WORK/uclibc"; mkdir -p "$WORK/uclibc"
	tar xf "$t" -C "$WORK/uclibc" --strip-components=1
	# Patches against upstream, each with its reasoning in the header. They
	# exist because old-kernel code paths nobody exercises any more still
	# get compiled, not because of anything local.
	for pat in "$SRC"/patches/uclibc-ng/*.patch; do
		[ -f "$pat" ] || continue
		echo "  patch: $(basename "$pat")"
		patch -d "$WORK/uclibc" -p1 --batch --forward < "$pat"
	done
	cd "$WORK/uclibc"
	make ARCH=mips defconfig >/dev/null

	set_cfg() {
		sed -i "/^$1=/d; /^# $1 is not set/d" .config
		printf '%s\n' "$2" >> .config
	}
	set_cfg TARGET_ARCH            'TARGET_ARCH="mips"'
	set_cfg CONFIG_MIPS_O32_ABI    'CONFIG_MIPS_O32_ABI=y'
	set_cfg ARCH_BIG_ENDIAN        'ARCH_BIG_ENDIAN=y'
	set_cfg ARCH_WANTS_BIG_ENDIAN  'ARCH_WANTS_BIG_ENDIAN=y'
	set_cfg UCLIBC_HAS_FPU         '# UCLIBC_HAS_FPU is not set'
	# 64-bit time_t is ON by default in 1.0.59 for mips o32, and its stat
	# path goes through statx. The 6.18 headers carry __NR_statx, but
	# flipping this changes the width of time_t across the whole userland
	# ABI, which is its own review. This userland stays Y2038-limited until
	# that review happens.
	set_cfg UCLIBC_USE_TIME64      '# UCLIBC_USE_TIME64 is not set'
	# defconfig leaves DO_C99_MATH off while UCLIBC_HAS_FLOATS is on, and on
	# MIPS that combination cannot link: printf float formatting
	# (_fpmaxtostr) calls __signbit, whose out-of-line definition is built
	# only with C99 math. Architectures carrying a bits/mathinline.h --
	# i386, sparc, m68k, alpha, ia64, x86_64, csky -- resolve it inline and
	# never notice. MIPS has no mathinline.h.
	set_cfg DO_C99_MATH            'DO_C99_MATH=y'
	# pref is MIPS-IV; this core is not.
	set_cfg UCLIBC_USE_MIPS_PREFETCH '# UCLIBC_USE_MIPS_PREFETCH is not set'
	set_cfg KERNEL_HEADERS         "KERNEL_HEADERS=\"$SYSROOT/usr/include\""
	set_cfg RUNTIME_PREFIX         'RUNTIME_PREFIX="/"'
	set_cfg DEVEL_PREFIX           'DEVEL_PREFIX="/usr"'
	set_cfg CROSS_COMPILER_PREFIX  "CROSS_COMPILER_PREFIX=\"$TARGET-\""
	set_cfg UCLIBC_EXTRA_CFLAGS    "UCLIBC_EXTRA_CFLAGS=\"$TARCH\""
	set_cfg DOSTRIP                '# DOSTRIP is not set'
	# The holes in the 2010 libc that motivated all of this.
	set_cfg UCLIBC_HAS_RESOLVER_SUPPORT 'UCLIBC_HAS_RESOLVER_SUPPORT=y'
	set_cfg UCLIBC_HAS_LIBRESOLV_STUB   'UCLIBC_HAS_LIBRESOLV_STUB=y'
	set_cfg UCLIBC_HAS_CRYPT            'UCLIBC_HAS_CRYPT=y'
	set_cfg UCLIBC_HAS_CRYPT_IMPL       'UCLIBC_HAS_CRYPT_IMPL=y'
	set_cfg UCLIBC_HAS_SHA256_CRYPT_IMPL 'UCLIBC_HAS_SHA256_CRYPT_IMPL=y'
	set_cfg UCLIBC_HAS_SHA512_CRYPT_IMPL 'UCLIBC_HAS_SHA512_CRYPT_IMPL=y'
	set_cfg UCLIBC_HAS_PTY              'UCLIBC_HAS_PTY=y'
	set_cfg UNIX98PTY_ONLY              '# UNIX98PTY_ONLY is not set'
	set_cfg ASSUME_DEVPTS               '# ASSUME_DEVPTS is not set'
	# Four features the packages used to shim around in their own trees
	# (busybox mktemp, dropbear openpty and the stack-protector runtime,
	# iproute2 nftw). Provided by the libc now, so the shims are gone:
	#   SUSV3_LEGACY   mktemp(3), the one legacy call busybox still makes
	#   LIBUTIL        openpty/forkpty, so dropbear allocates ptys the normal way
	#   SSP            __stack_chk_fail and a per-process random guard, so
	#                  -fstack-protector-strong in dropbear links against the
	#                  libc rather than a constant-canary stand-in
	#   FTW, NFTW      nftw(), which iproute2 lib/cg_map.c calls
	set_cfg UCLIBC_SUSV3_LEGACY         'UCLIBC_SUSV3_LEGACY=y'
	set_cfg UCLIBC_SUSV4_LEGACY         'UCLIBC_SUSV4_LEGACY=y'
	set_cfg UCLIBC_HAS_FTW              'UCLIBC_HAS_FTW=y'
	set_cfg UCLIBC_HAS_NFTW             'UCLIBC_HAS_NFTW=y'
	set_cfg UCLIBC_HAS_LIBUTIL          'UCLIBC_HAS_LIBUTIL=y'
	set_cfg UCLIBC_HAS_SSP              'UCLIBC_HAS_SSP=y'
	set_cfg SSP_QUICK_CANARY            '# SSP_QUICK_CANARY is not set'
	set_cfg PROPOLICE_BLOCK_ABRT        'PROPOLICE_BLOCK_ABRT=y'
	set_cfg UCLIBC_BUILD_SSP            '# UCLIBC_BUILD_SSP is not set'

	# `< /dev/null`, never an empty-line `yes` pipe: kconfig takes the default
	# for every new symbol on EOF just the same, and a `yes` producer gets
	# SIGPIPE the moment
	# make exits -- which under `set -o pipefail` kills the whole script with
	# 141 and no message at all.
	make ARCH=mips oldconfig </dev/null >/dev/null
	q uclibc-make make -j"$JOBS" \
		CROSS_COMPILE="$TARGET-" ARCH=mips \
		PREFIX="$SYSROOT" install
	cd /
fi

# -------------------------------------------------------- 5. gcc, stage two
# Stamped rather than probed. The obvious guards do not work: we build C only,
# so libstdc++.a and $TARGET-g++ never exist, and libgcc.a exists after stage
# ONE, so neither can tell the stages apart.
STAGE2_STAMP=$PREFIX/.stage2-complete
if ! have "$STAGE2_STAMP"; then
	say "gcc $GCC, stage two (against uClibc-ng)"
	gcc_src
	rm -rf "$WORK/build-gcc2"; mkdir -p "$WORK/build-gcc2"; cd "$WORK/build-gcc2"
	# --disable-threads matches the libc: uClibc-ng defconfig selects
	# HAS_NO_THREADS for this target, and nothing built with it needs them --
	# busybox, dropbear and iproute2 are single-threaded or
	# fork-per-connection. Enabling NPTL would mean exercising uClibc-ng
	# thread support on MIPS o32 on this core, the unexercised-combination
	# territory every other problem in this build came from.
	# shellcheck disable=SC2086  # GCC_COMMON is a deliberate word list
	q gcc2-configure "$WORK/gcc/configure" $GCC_COMMON \
		--enable-languages=c --enable-shared --disable-threads \
		--disable-libatomic \
		CFLAGS_FOR_TARGET="$TFLAGS"
	q gcc2-make make -j"$JOBS"
	q gcc2-install make install
	touch "$STAGE2_STAMP"
	cd /
fi

# ------------------------------------------------ 6. strip the HOST programs
# cc1, lto1 and lto-dump alone are 300 MB each with their debug info, which
# is most of the image. Only executables and shared objects for the build
# host are stripped, recognised by their ELF machine; the target libraries
# (libc.a, libgcc.a, crt*.o) are MIPS objects and are never touched, so
# nothing the toolchain links into a binary changes.
say "stripping the host programs"
host_machine=$(readelf -h /bin/sh | sed -n 's/^ *Machine: *//p')
find "$PREFIX/bin" "$PREFIX/libexec" "$PREFIX/$TARGET/bin" -type f |
while read -r f; do
	m=$(readelf -h "$f" 2>/dev/null | sed -n 's/^ *Machine: *//p') || true
	[ "$m" = "$host_machine" ] || continue
	strip --strip-unneeded "$f"
	echo "$f"
done | wc -l | sed "s/\$/ host programs stripped ($host_machine)/;s/^ */  /"

say "built"
"$PREFIX/bin/$TARGET-gcc" --version | head -1
echo "prefix:  $PREFIX"
echo "sysroot: $SYSROOT"
