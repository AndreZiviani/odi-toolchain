/* At -march=mips32 a multiply is the SPECIAL2 mul the RLX5281 traps on. */
volatile int a = 6, b = 7;
int main(void) { return a * b == 42 ? 0 : 1; }
