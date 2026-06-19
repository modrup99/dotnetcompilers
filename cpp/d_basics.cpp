int main() {
    int    n = 42;
    double pi = 3.14159;
    char   c = 'A';
    printf("%d %g %c\n", n, pi, c);
    int sum = 0;
    int i;
    for (i = 1; i <= 5; i = i + 1) sum = sum + i;
    printf("sum 1..5 = %d\n", sum);
    if (sum > 10) printf("big\n"); else printf("small\n");
    int a[5];
    for (i = 0; i < 5; i = i + 1) a[i] = i * i;
    printf("a[3] = %d\n", a[3]);
    return 0;
}
