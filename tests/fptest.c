typedef int (*fn)(int);
int add1(int x){ return x + 1; }
int mul2(int x){ return x * 2; }
struct Obj { int (*op)(int); int val; };
int main(void){
    fn table[2];
    table[0] = add1;
    table[1] = mul2;
    int i;
    for(i=0;i<2;i++) printf("table[%d](5)=%d\n", i, table[i](5));
    struct Obj o;
    o.op = add1;
    o.val = 10;
    printf("field call: %d\n", o.op(o.val));
    return 0;
}
