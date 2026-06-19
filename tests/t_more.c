int printf(int f, ...);
long strtol(int s, int e, int b); int strspn(int s, int set); int strpbrk(int s, int set);
#define STR(x) #x
#define CAT(a,b) a ## b
#define GREET "hi"
int main(void){
    int xy123 = 7;
    printf("stringize=[%s] paste=%d\n", STR(hello world), CAT(xy, 123));
    long v = strtol((int)"0xFF", 0, 0);
    printf("strtol(0xFF)=%ld span=%d\n", v, strspn((int)"aabbc", (int)"ab"));
    int pos = strpbrk((int)"hello,world", (int)",;");
    printf("pbrk char=%c\n", *((char*)pos));
    return 0;
}
