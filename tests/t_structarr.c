int printf(int f, ...);
struct P{int x;int y;};
struct B{int n; int v[4];};
int main(void){ struct P a[3]; int i; for(i=0;i<3;i++){a[i].x=i;a[i].y=i*i;} struct B b; b.n=2; b.v[0]=10;b.v[1]=20; printf("sarr: %d %d %d %d\n", a[2].x, a[2].y, b.v[0]+b.v[1], b.n); return 0; }
