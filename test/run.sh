#!/bin/sh
# Self-test for the freestanding image and the ISA audit, run inside the
# image (make test). Builds three tiny programs and checks that the audit
# says what it must about each: clean at mips1, a trap at mips32 (mul), and
# unverified at mips32r2 (seb). Then runs the clean one under qemu.
set -eu
cd "$(dirname "$0")"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT INT TERM
CC=mips-linux-gnu-gcc
F="-mabi=32 -EB -msoft-float -G0 -fno-pic -mno-abicalls -ffreestanding -fno-builtin -fno-stack-protector -Os"
L="-nostdlib -nostartfiles -static -Wl,-e,_start -Wl,--build-id=none"
# shellcheck disable=SC2086 # F and L are deliberate word lists
{
	$CC -march=mips1    $F $L -o "$out/ok"  start.S ok.c
	$CC -march=mips32   $F $L -o "$out/mul" start.S mul.c
	$CC -march=mips32r2 $F $L -o "$out/seb" start.S seb.c
}
fail=0
expect() {
	want=$1; shift
	set +e; "$@" >"$out/log" 2>&1; got=$?; set -e
	if [ "$got" = "$want" ]; then
		echo "ok    exit $got: $*"
	else
		echo "FAIL  exit $got, want $want: $*"; sed 's/^/      /' "$out/log"; fail=1
	fi
}
expect 0 isa-audit     "$out/ok"
expect 0 isa-allowlist "$out/ok"
expect 1 isa-audit     "$out/mul"
expect 1 isa-allowlist "$out/mul"
expect 0 isa-audit     "$out/seb"
expect 2 isa-allowlist "$out/seb"
expect 1 isa-audit     run.sh
expect 0 qemu-mips-static "$out/ok"
[ "$fail" = 0 ] && echo "selftest: all passed"
exit $fail
