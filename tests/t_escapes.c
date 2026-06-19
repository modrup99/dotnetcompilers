int printf(int f, ...);
int main(void){ char c1='\101'; char c2='\x42'; printf("oct=%c hex=%c nl-then[%s]\n", c1, c2, "a\tb"); return 0; }
