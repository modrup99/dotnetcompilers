/* strings.c — exercises Stage 2: fat pointers, arrays, char*, casts, sizeof,
 * and the libc (printf / string.h / ctype.h / stdlib.h). */

int printf(int fmt, ...);
int strlen(int s);
int strcpy(int d, int s);
int strcmp(int a, int b);
int malloc(int n);
int toupper(int c);
int isalpha(int c);

/* reverse a C string in place using two pointers */
void reverse(int s)
{
    int i = 0;
    int j = strlen(s) - 1;
    while (i < j) {
        int t = ((char *)s)[i];
        ((char *)s)[i] = ((char *)s)[j];
        ((char *)s)[j] = t;
        i++;
        j--;
    }
}

/* count alphabetic characters via pointer walking */
int count_alpha(int s)
{
    int n = 0;
    char *p = (char *)s;
    while (*p) {
        if (isalpha(*p)) n++;
        p++;
    }
    return n;
}

int main(void)
{
    char buf[64];
    int i;
    int sum;
    int arr[5];

    strcpy((int)buf, (int)"Hello, IL world");
    printf("original : %s\n", buf);
    printf("length   : %d\n", strlen((int)buf));
    printf("alpha    : %d\n", count_alpha((int)buf));

    reverse((int)buf);
    printf("reversed : %s\n", buf);

    /* uppercase it in place */
    for (i = 0; i < strlen((int)buf); i++)
        buf[i] = toupper(buf[i]);
    printf("upper    : %s\n", buf);

    /* array + pointer arithmetic */
    sum = 0;
    for (i = 0; i < 5; i++) arr[i] = (i + 1) * (i + 1);
    for (i = 0; i < 5; i++) sum += *(arr + i);
    printf("squares sum to %d, sizeof(arr)=%d\n", sum, sizeof(arr));

    /* heap allocation */
    {
        char *dyn = (char *)malloc(32);
        strcpy((int)dyn, (int)"on the heap");
        printf("heap     : %s (strcmp vs buf = %d)\n", dyn, strcmp((int)dyn, (int)buf));
    }
    return 0;
}
