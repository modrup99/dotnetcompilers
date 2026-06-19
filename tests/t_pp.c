#include "inc.h"
#include <stdio.h>          /* system header: no-op */
#define MAX 100
#define MIN 10
#define ADD(a,b) ((a)+(b))
#define DBG 0
int printf(int f, ...);
int main(void){
    int r = ADD(3, 4) + SQUARE(5);     /* 7 + 25 = 32 */
    printf("macros: %d (exp 32), range=%d\n", r, MAX - MIN);
#if DBG
    printf("debug on\n");
#else
    printf("debug off\n");
#endif
#ifdef MAX
    printf("MAX defined\n");
#endif
#if defined(MIN) && MAX > 50
    printf("cond ok\n");
#endif
    return 0;
}
