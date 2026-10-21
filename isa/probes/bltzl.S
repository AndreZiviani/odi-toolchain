/*
 * bltzl probe: does a branch-likely instruction execute correctly on the
 * RLX5281? A SIGILL-only probe (run it, see no signal, call it ok) cannot
 * tell: the instruction can decode and still misexecute. This one checks the
 * two things that define a branch-likely, for both operand signs:
 *
 *   taken     (operand < 0):  the delay slot runs, control goes to the target
 *   not taken (operand >= 0): the delay slot is NULLIFIED, control falls through
 *
 * Per case it prints "<case> slot=<0|1> fell=<0|1>" followed by OK or WRONG:
 *   taken      correct: slot=1 fell=0
 *   not taken  correct: slot=0 fell=1
 * The process exits 0 only when both cases are correct, 1 when any is wrong.
 *
 * Freestanding, big-endian o32, raw syscalls; build with the freestanding
 * image (the line below) and run from /tmp on the device;
 * nothing is written to flash.
 *
 *   mips-linux-gnu-gcc -march=mips2 -mabi=32 -EB -msoft-float -G0 -fno-pic \
 *     -mno-abicalls -nostdlib -nostartfiles -static -Wl,-e,_start \
 *     -Wl,--build-id=none -o bltzl bltzl.S
 *   mips-linux-gnu-objdump -d bltzl | grep bltzl   # must show the instruction
 */
	.set	noreorder
	.set	mips2
	.text
	.globl	_start
	.ent	_start
_start:
	li	$s7, 0			# overall verdict: nonzero = a case was wrong

	# --- taken: -5 < 0 ---
	li	$a0, -5
	move	$t0, $zero		# slot ran?
	move	$t1, $zero		# fell through?
	bltzl	$a0, 1f
	 addiu	$t0, $t0, 1		# delay slot
	addiu	$t1, $t1, 1		# only reached when NOT taken
1:	move	$s0, $t0
	move	$s1, $t1
	la	$a1, msg_taken
	li	$a2, 12			# "taken     " + trailing space
	jal	report
	 nop
	# expect slot=1 fell=0
	xori	$t2, $s0, 1
	or	$t2, $t2, $s1
	jal	verdict
	 move	$a3, $t2

	# --- not taken: 7 >= 0 ---
	li	$a0, 7
	move	$t0, $zero
	move	$t1, $zero
	bltzl	$a0, 2f
	 addiu	$t0, $t0, 1		# must be nullified
	addiu	$t1, $t1, 1		# fall-through
2:	move	$s0, $t0
	move	$s1, $t1
	la	$a1, msg_nottaken
	li	$a2, 12
	jal	report
	 nop
	# expect slot=0 fell=1
	xori	$t2, $s1, 1
	or	$t2, $t2, $s0
	jal	verdict
	 move	$a3, $t2

	li	$v0, 4001		# exit(s7 != 0)
	sltu	$a0, $zero, $s7
	syscall
	.end	_start

# report: write "<label>slot=<s0> fell=<s1> " (a1 = label, a2 = length).
# Takes the results in s0/s1: the kernel does not preserve the temporaries
# across a syscall, only the saved registers. Clobbers ra (kept in s6).
	.ent	report
report:
	move	$s6, $ra
	li	$v0, 4004
	li	$a0, 1
	syscall				# label
	la	$t3, buf
	li	$t4, 's'; sb $t4, 0($t3)
	li	$t4, 'l'; sb $t4, 1($t3)
	li	$t4, 'o'; sb $t4, 2($t3)
	li	$t4, 't'; sb $t4, 3($t3)
	li	$t4, '='; sb $t4, 4($t3)
	addiu	$t4, $s0, '0'; sb $t4, 5($t3)
	li	$t4, ' '; sb $t4, 6($t3)
	li	$t4, 'f'; sb $t4, 7($t3)
	li	$t4, 'e'; sb $t4, 8($t3)
	li	$t4, 'l'; sb $t4, 9($t3)
	li	$t4, 'l'; sb $t4, 10($t3)
	li	$t4, '='; sb $t4, 11($t3)
	addiu	$t4, $s1, '0'; sb $t4, 12($t3)
	li	$t4, ' '; sb $t4, 13($t3)
	li	$v0, 4004
	li	$a0, 1
	move	$a1, $t3
	li	$a2, 14
	syscall
	jr	$s6
	 nop
	.end	report

# verdict: a3 == 0 means the case was correct. Prints OK / WRONG.
	.ent	verdict
verdict:
	move	$s6, $ra
	li	$v0, 4004
	li	$a0, 1
	beqz	$a3, 3f
	 nop
	la	$a1, msg_wrong
	li	$a2, 6
	li	$s7, 1
	b	4f
	 nop
3:	la	$a1, msg_ok
	li	$a2, 3
4:	syscall
	jr	$s6
	 nop
	.end	verdict

	.data
msg_taken:	.ascii	"taken     "
		.ascii	"  "
msg_nottaken:	.ascii	"not taken "
		.ascii	"  "
msg_ok:		.ascii	"OK\n"
msg_wrong:	.ascii	"WRONG\n"
buf:		.space	16
