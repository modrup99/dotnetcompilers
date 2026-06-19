int printf(int f, ...);
int add(int a,int b){return a+b;} int sub(int a,int b){return a-b;} int mul(int a,int b){return a*b;}
typedef int (*Op)(int,int);
int main(void){
    Op ops[3]; ops[0]=add; ops[1]=sub; ops[2]=mul;
    int i; for(i=0;i<3;i++) printf("%d ", ops[i](12,4)); printf("(exp 16 8 48)\n");
    return 0;
}
