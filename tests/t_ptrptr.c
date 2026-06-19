int printf(int f, ...);
int main(void){ int x=7; int *p=&x; int **pp=&p; **pp=42; printf("ptrptr: %d (exp 42)\n", x); return 0; }
