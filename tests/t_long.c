int printf(int f, ...);
long factL(int n){ long r=1; int i; for(i=2;i<=n;i++) r=r*i; return r; }
int main(void){
    long big = 1000000000;        /* 1e9 */
    long prod = big * 1000;       /* 1e12 — overflows int32 */
    printf("prod=%ld (exp 1000000000000)\n", prod);
    printf("20! = %ld (exp 2432902008176640000)\n", factL(20));
    long a = 9000000000;          /* > INT_MAX literal */
    printf("a=%ld a/7=%ld a>>1=%ld\n", a, a/7, a>>1);
    int small = (int)(prod % 1000000);   /* long -> int cast */
    printf("mod-cast=%d (exp 0)\n", small);
    double d = (double)a / 4;            /* long -> double */
    printf("d=%.1f (exp 2250000000.0)\n", d);
    return 0;
}
