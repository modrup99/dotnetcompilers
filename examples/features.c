/* features.c — the gap-fillers: floats + math.h, aggregate initializers,
 * adjacent string concat, goto, sscanf, and struct-by-value. */

int printf(int fmt, ...);
int sscanf(int s, int fmt, ...);
double sqrt(double x);

typedef struct { double re; double im; } Complex;

double cmag(Complex c) { return sqrt(c.re * c.re + c.im * c.im); }   /* struct by value */
Complex cadd(Complex a, Complex b) { Complex r = { a.re + b.re, a.im + b.im }; return r; } /* sret */

int main(void)
{
    int primes[] = { 2, 3, 5, 7, 11, 13 };          /* inferred-length array init */
    double weights[3] = { 0.25, 0.5 };              /* partial init -> rest 0 */
    char *msg = "floating " "point " "world";       /* adjacent concatenation */
    Complex a = { 3.0, 4.0 };
    Complex b = { 1.0, 2.0 };
    Complex s = cadd(a, b);
    int i, total = 0;
    double wsum = 0.0;
    int n, m;

    for (i = 0; i < 6; i++) total += primes[i];
    for (i = 0; i < 3; i++) wsum += weights[i];
    printf("%s: prime sum=%d  weight sum=%.2f\n", msg, total, wsum);
    printf("|a|=%.1f  a+b=(%.1f, %.1f)\n", cmag(a), s.re, s.im);

    sscanf((int)"100 250", "%d %d", &n, &m);
    if (n + m != 350) goto bad;
    printf("sscanf ok: %d + %d = %d\n", n, m, n + m);
    return 0;
bad:
    printf("sscanf failed\n");
    return 1;
}
