int printf(int f, ...);
int main(void){
    unsigned int a = 4000000000;   /* > INT_MAX */
    unsigned int b = 3;
    printf("udiv=%u ucmp=%d shr=%u\n", a / b, (a > 5), a >> 1);
    int s = -1; printf("signed shr=%d\n", s >> 1);   /* arithmetic: stays -1 */
    return 0;
}
