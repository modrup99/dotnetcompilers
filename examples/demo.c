/* demo.c — exercises the Stage-1 C subset: globals, recursion, loops,
 * conditionals, the full operator set, break/continue, and prototypes.
 *
 * putint/putchar are temporary intrinsics until the libc subset lands. */

int putint(int x);
int putchar(int c);

int counter = 0;        /* global with initializer */

int fib(int n)
{
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

int gcd(int a, int b)
{
    while (b != 0) {
        int t = b;
        b = a % b;
        a = t;
    }
    return a;
}

int count_primes(int limit)
{
    int n, d, found;
    for (n = 2; n <= limit; n++) {
        int is_prime = 1;
        for (d = 2; d * d <= n; d++) {
            if (n % d == 0) { is_prime = 0; break; }
        }
        if (is_prime) counter = counter + 1;
    }
    return counter;
}

int main(void)
{
    putint(fib(15));            /* 610 */
    putint(gcd(48, 36));        /* 12  */
    putint(count_primes(50));   /* 15  */
    putint(7 > 3 && 2 <= 2);    /* 1   */
    putchar(65);                /* A   */
    putchar(10);                /* newline */
    return 0;
}
