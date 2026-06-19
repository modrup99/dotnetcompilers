int printf(int f, ...);
struct P { int x; int y; int z; };
int main(void){
    struct P p = { .y = 20, .x = 10 };          /* out of order */
    int a[6] = { [5] = 99, [1] = 11, 22 };       /* [1]=11 then 22 at [2] */
    printf("struct: x=%d y=%d z=%d (exp 10 20 0)\n", p.x, p.y, p.z);
    printf("array: a1=%d a2=%d a5=%d a0=%d (exp 11 22 99 0)\n", a[1], a[2], a[5], a[0]);
    return 0;
}
