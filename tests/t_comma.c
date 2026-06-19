int printf(int f, ...);
int main(void){ int i, j, s=0; for(i=0,j=10; i<j; i++,j--) s++; printf("comma: s=%d (exp 5)\n", s); int a=(1,2,3); printf("comma expr: %d (exp 3)\n", a); return 0; }
