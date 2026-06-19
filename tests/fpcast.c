int addxy(int x, int y){ return x + y; }
int neg(int x){ return -x; }
int main(void){
    int vt[2];
    vt[0] = (int)addxy;
    vt[1] = (int)neg;
    int r1 = ((int(*)(int,int))vt[0])(3, 4);
    int r2 = ((int(*)(int))vt[1])(9);
    printf("r1=%d r2=%d\n", r1, r2);
    return 0;
}
