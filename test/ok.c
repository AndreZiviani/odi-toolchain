/* Division and a loop: at -march=mips1 the divide-by-zero check is break,
 * not teq, and nothing on the deny list is emitted. */
volatile int a = 84, b = 2;
int main(void) { int s = 0; for (int i = 0; i < b; i++) s += a / b; return s == 84 ? 0 : 1; }
