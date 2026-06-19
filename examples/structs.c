/* structs.c — Stage 2b: struct/union, typedef, enum, switch, member access,
 * struct copy, and function pointers (incl. a comparator-driven sort). */

int printf(int fmt, ...);

typedef struct Point { int x; int y; } Point;

enum Op { OP_ADD, OP_SUB, OP_MUL };

typedef int (*BinOp)(int, int);

int add(int a, int b) { return a + b; }
int sub(int a, int b) { return a - b; }
int mul(int a, int b) { return a * b; }

/* indirect call through a function-pointer parameter */
int apply(BinOp f, int a, int b) { return f(a, b); }

char *opname(enum Op o)
{
    switch (o) {
        case OP_ADD: return "add";
        case OP_SUB: return "sub";
        case OP_MUL: return "mul";
        default:     return "?";
    }
}

int ascending(int a, int b)  { return a - b; }
int descending(int a, int b) { return b - a; }

void bubble(int *a, int n, BinOp cmp)
{
    int i, j;
    for (i = 0; i < n; i++)
        for (j = 0; j < n - 1 - i; j++)
            if (cmp(a[j], a[j + 1]) > 0) {
                int t = a[j];
                a[j] = a[j + 1];
                a[j + 1] = t;
            }
}

void print_arr(int *a, int n)
{
    int i;
    for (i = 0; i < n; i++) printf("%d ", a[i]);
    printf("\n");
}

int main(void)
{
    Point p;
    Point *pp;
    Point q;
    BinOp ops[3];
    enum Op o;
    int arr[6];
    int i;

    p.x = 3;
    p.y = 4;
    pp = &p;
    q = p;                 /* struct copy */
    q.x = 99;
    printf("p=(%d,%d) via pp=(%d,%d) q=(%d,%d)\n", p.x, p.y, pp->x, pp->y, q.x, q.y);

    ops[0] = add;
    ops[1] = sub;
    ops[2] = mul;
    for (o = OP_ADD; o <= OP_MUL; o++)
        printf("%s(6,3) = %d\n", opname(o), ops[o](6, 3));

    printf("apply(add,10,20) = %d\n", apply(add, 10, 20));

    arr[0] = 5; arr[1] = 2; arr[2] = 8; arr[3] = 1; arr[4] = 9; arr[5] = 3;
    bubble(arr, 6, ascending);
    printf("ascending : "); print_arr(arr, 6);
    bubble(arr, 6, descending);
    printf("descending: "); print_arr(arr, 6);
    return 0;
}
