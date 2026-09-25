# Target flags for the RLX5281 (ODI DFP-34X-2C2, RTL9601C/RTL9602C class),
# one place for every project that builds for it. Installed in both images as
# /usr/local/share/odi-toolchain/flags.mk; a Makefile can `include` it, or
# copy the values and cite this file.
#
# Two baselines, one per image, and the split is deliberate.
#
# FREESTANDING: -march=mips1. This is the baseline for everything built with
# the freestanding image (diag, nv, omcid and friends, metricsd, confd).
#
#   - Those binaries must run on the STOCK OEM image as well as ours: the
#     exporter override path and dropping a recovery tool onto a stock stick
#     both depend on it. mips1 is the one ISA level whose every instruction is
#     confirmed to execute on this core -- the vendor userland itself is
#     built -march=mips1.
#   - At mips1 gcc cannot emit any of the five instructions measured illegal:
#     mul and clz are SPECIAL2 (mips32), beql/bnel are MIPS-II, and the
#     divide-by-zero check becomes `break` rather than `teq`. Nothing needs
#     suppressing, so no flag can be forgotten.
#   - The one thing mips2 would add that works on this core is ll/sc.
#     Freestanding code is single-threaded and has no use for it.
#
# UCLIBC: -march=mips2 -mno-branch-likely -mdivide-breaks. This is the
# baseline for the libc, the kernel and everything linked against uClibc-ng.
#
#   - uClibc-ng needs native ll/sc for its atomics, and ll, sc and sync are
#     measured present. The kernel wants them too.
#   - mips2 alone is NOT safe on this core: it brings teq (every divide-by-zero
#     check, 147 of them in one dropbear build) and beql/bnel (109 more).
#     -mdivide-breaks and -mno-branch-likely take those back out, and they
#     must reach the target libraries, not only the application (the uclibc
#     image bakes them into libgcc and libc and audits both at build time).
#   - The kernel additionally predefines itself as MIPS I
#     (-U_MIPS_ISA -D_MIPS_ISA=_MIPS_ISA_MIPS1) so asm/bug.h does not build
#     BUG_ON() on tne; that belongs to the kernel build, not here.
#
# Both: big-endian (-EB), o32 (-mabi=32), soft float (the core has no FPU).
# Neither level is trusted: every binary still goes through isa-audit and
# isa-allowlist, which disassemble at mips32 so a slipped mul shows up.

ODI_ENDIAN_ABI_FLAGS := -mabi=32 -EB -msoft-float

# Freestanding: add -G0 (the _start stubs never set up $gp), no PIC, no GOT,
# no libc, and no turning loops back into libc calls.
ODI_FREESTANDING_ARCH_FLAGS := -march=mips1 $(ODI_ENDIAN_ABI_FLAGS)
ODI_FREESTANDING_CFLAGS := $(ODI_FREESTANDING_ARCH_FLAGS) -G0 \
	-fno-pic -mno-abicalls -ffreestanding -fno-builtin -fno-stack-protector
ODI_FREESTANDING_LDFLAGS := -nostdlib -nostartfiles -static -Wl,-e,_start \
	-Wl,--build-id=none
ODI_FREESTANDING_CROSS := mips-linux-gnu-

# uClibc-ng: the libraries in the image were built with exactly these.
ODI_UCLIBC_ARCH_FLAGS := -march=mips2 -mno-branch-likely -mdivide-breaks \
	$(ODI_ENDIAN_ABI_FLAGS)
ODI_UCLIBC_CROSS := mips-linux-uclibc-
ODI_UCLIBC_PREFIX := /opt/oss
