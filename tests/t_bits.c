int printf(int f, ...);
int main(void){
    int x = 0xF0; int y = 0x0F;
    printf("and=%d or=%d xor=%d shl=%d shr=%d (exp 0 255 255 480 15)\n", x&y, x|y, x^y, x<<1, x>>4);
    unsigned int u = 0xFFFFFFFF;
    printf("unsigned shr: %u (exp 15)\n", u >> 28);
    return 0;
}
