/* At -march=mips32r2 a sign extension is seb: not known to trap, never
 * executed on the device either, so isa-allowlist reports it (exit 2). */
volatile int a = 0x80;
int main(void) { return (signed char)a == -128 ? 0 : 1; }
