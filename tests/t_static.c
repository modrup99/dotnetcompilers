int printf(int f, ...);
int next(void){ static int n=0; n=n+1; return n; }
int main(void){ printf("static: %d %d %d (exp 1 2 3)\n", next(), next(), next()); return 0; }
