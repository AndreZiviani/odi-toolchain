/* The smallest freestanding program: exit(main()) through the o32 syscall. */
	.text
	.globl	_start
	.ent	_start
_start:
	jal	main
	nop
	move	$a0, $v0
	li	$v0, 4001	/* __NR_exit, o32 */
	syscall
	.end	_start
