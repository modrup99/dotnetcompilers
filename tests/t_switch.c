int printf(int f, ...);
int f(int x){ int r=0; switch(x){ case 1: r=r+1; case 2: r=r+10; break; default: r=99; break; case 3: r=r+100; } return r; }
int main(void){ printf("sw: %d %d %d %d (exp 11 10 100 99)\n", f(1),f(2),f(3),f(5)); return 0; }
