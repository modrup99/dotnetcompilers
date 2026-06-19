int printf(int f, ...);
void qsort_(int *a, int lo, int hi){
    if (lo >= hi) return;
    int pivot = a[(lo+hi)/2]; int i = lo; int j = hi;
    while (i <= j){
        while (a[i] < pivot) i++;
        while (a[j] > pivot) j--;
        if (i <= j){ int t=a[i]; a[i]=a[j]; a[j]=t; i++; j--; }
    }
    qsort_(a, lo, j); qsort_(a, i, hi);
}
int main(void){
    int a[8]; a[0]=5;a[1]=2;a[2]=8;a[3]=1;a[4]=9;a[5]=3;a[6]=7;a[7]=4;
    qsort_(a, 0, 7);
    int i; for (i=0;i<8;i++) printf("%d ", a[i]); printf("\n");
    return 0;
}
