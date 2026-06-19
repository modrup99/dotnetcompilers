int printf(int f, ...);
int main(void){ int a[5]; int i=0; int v; while((v = (i<5? i*i : -1)) >= 0){ a[i]=v; i++; } int t=0; for(i=0;i<5;i++)t+=a[i]; printf("expr: t=%d (exp 30)\n", t); return 0; }
