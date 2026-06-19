%{
/* `bc` — a text-based scientific calculator (lex + yacc -> our C -> .NET IL).
 *   bc            interactive REPL (q / quit to exit)
 *   bc "EXPR"     evaluate the argument(s) and print
 * Doubles are boxed as int handles since yacc's value stack is int; the grammar
 * below is the lex+yacc showcase, with full operator precedence + functions. */

double *yyvald;
int num(double d) { double *p = (double *)malloc(8); *p = d; return (int)p; }     /* box */
double val(int h) { return *((double *)h); }                                       /* unbox */

/* variables */
char *vn[4000]; double vv[4000]; int nv;
double getvar(char *n) { int i; for (i = 0; i < nv; i++) if (strcmp(vn[i], n) == 0) return vv[i]; return 0; }
void setvar(char *n, double v) { int i; for (i = 0; i < nv; i++) if (strcmp(vn[i], n) == 0) { vv[i] = v; return; } vn[nv] = (char *)strdup((int)n); vv[nv] = v; nv++; }

int eq(char *a, char *b) { return strcmp(a, b) == 0; }
double call1(char *f, double x)
{
    if (eq(f, "sqrt")) return sqrt(x);
    if (eq(f, "sin") || eq(f, "s")) return sin(x);
    if (eq(f, "cos") || eq(f, "c")) return cos(x);
    if (eq(f, "tan")) return tan(x);
    if (eq(f, "asin")) return asin(x);
    if (eq(f, "acos")) return acos(x);
    if (eq(f, "atan") || eq(f, "a")) return atan(x);
    if (eq(f, "exp")) return exp(x);
    if (eq(f, "ln") || eq(f, "l")) return log(x);
    if (eq(f, "log")) return log10(x);
    if (eq(f, "log2")) return log(x) / log(2.0);
    if (eq(f, "abs")) return fabs(x);
    if (eq(f, "floor")) return floor(x);
    if (eq(f, "ceil")) return ceil(x);
    if (eq(f, "round")) return round(x);
    if (eq(f, "int") || eq(f, "trunc")) return (double)(int)x;
    if (eq(f, "sign")) return x > 0 ? 1 : (x < 0 ? -1 : 0);
    if (eq(f, "rad")) return x * 3.14159265358979 / 180.0;
    if (eq(f, "deg")) return x * 180.0 / 3.14159265358979;
    printf((int)"bc: unknown function %s\n", (int)f); return 0;
}
double call2(char *f, double a, double b)
{
    if (eq(f, "pow")) return pow(a, b);
    if (eq(f, "atan2")) return atan2(a, b);
    if (eq(f, "hypot")) return sqrt(a * a + b * b);
    if (eq(f, "max")) return a > b ? a : b;
    if (eq(f, "min")) return a < b ? a : b;
    if (eq(f, "mod")) return fmod(a, b);
    if (eq(f, "logn")) return log(b) / log(a);     /* logn(base, x) */
    if (eq(f, "root")) return pow(b, 1.0 / a);      /* root(n, x) = x^(1/n) */
    printf((int)"bc: unknown function %s\n", (int)f); return 0;
}
void yyerror(char *m) { printf((int)"bc: %s\n", (int)m); }
int yylex();
%}
%token NUMBER NAME QUIT EQ NE LE GE AND OR PLUSEQ MINUSEQ STAREQ SLASHEQ PCTEQ CARETEQ
%right '=' PLUSEQ MINUSEQ STAREQ SLASHEQ PCTEQ CARETEQ
%left OR
%left AND
%left EQ NE '<' '>' LE GE
%left '+' '-'
%left '*' '/' '%'
%right UMINUS '!'
%right '^'
%%
input : /* empty */
      | input item ;
item  : '\n'
      | ';'
      | stmt '\n'
      | stmt ';'
      | stmt ;
stmt  : QUIT             { exit(0); }
      | expr             { printf((int)"%.10g\n", val($1)); } ;

expr  : NUMBER                      { $$ = $1; }
      | NAME                        { $$ = num(getvar((char *)$1)); }
      | NAME '=' expr               { setvar((char *)$1, val($3)); $$ = $3; }
      | NAME PLUSEQ expr            { double v = getvar((char *)$1) + val($3); setvar((char *)$1, v); $$ = num(v); }
      | NAME MINUSEQ expr           { double v = getvar((char *)$1) - val($3); setvar((char *)$1, v); $$ = num(v); }
      | NAME STAREQ expr            { double v = getvar((char *)$1) * val($3); setvar((char *)$1, v); $$ = num(v); }
      | NAME SLASHEQ expr           { double v = getvar((char *)$1) / val($3); setvar((char *)$1, v); $$ = num(v); }
      | NAME PCTEQ expr             { double v = fmod(getvar((char *)$1), val($3)); setvar((char *)$1, v); $$ = num(v); }
      | NAME CARETEQ expr           { double v = pow(getvar((char *)$1), val($3)); setvar((char *)$1, v); $$ = num(v); }
      | NAME '(' expr ')'           { $$ = num(call1((char *)$1, val($3))); }
      | NAME '(' expr ',' expr ')'  { $$ = num(call2((char *)$1, val($3), val($5))); }
      | expr '+' expr               { $$ = num(val($1) + val($3)); }
      | expr '-' expr               { $$ = num(val($1) - val($3)); }
      | expr '*' expr               { $$ = num(val($1) * val($3)); }
      | expr '/' expr               { $$ = num(val($1) / val($3)); }
      | expr '%' expr               { $$ = num(fmod(val($1), val($3))); }
      | expr '^' expr               { $$ = num(pow(val($1), val($3))); }
      | '-' expr %prec UMINUS       { $$ = num(-val($2)); }
      | '!' expr                    { $$ = num(val($2) == 0 ? 1 : 0); }
      | expr EQ expr                { $$ = num(val($1) == val($3)); }
      | expr NE expr                { $$ = num(val($1) != val($3)); }
      | expr '<' expr               { $$ = num(val($1) < val($3)); }
      | expr '>' expr               { $$ = num(val($1) > val($3)); }
      | expr LE expr                { $$ = num(val($1) <= val($3)); }
      | expr GE expr                { $$ = num(val($1) >= val($3)); }
      | expr AND expr               { $$ = num((val($1) != 0 && val($3) != 0) ? 1 : 0); }
      | expr OR expr                { $$ = num((val($1) != 0 || val($3) != 0) ? 1 : 0); }
      | '(' expr ')'                { $$ = $2; } ;
%%

int main(int argc, char **argv)
{
    setvar("pi", 3.14159265358979);
    setvar("e", 2.71828182845905);

    if (argc > 1)
    {
        char buf[8192]; buf[0] = 0; int i;
        for (i = 1; i < argc; i++) { if (i > 1) strcat(buf, " "); strcat(buf, (char *)argv[i]); }
        strcat(buf, "\n");
        yy_scan_string((int)buf);
        yyparse();
        return 0;
    }

    /* interactive REPL: read a line, evaluate, repeat; q/quit exits */
    char line[8192];
    while (1)
    {
        int n = 0, ch;
        while ((ch = getchar()) != -1 && ch != '\n') { if (ch != '\r' && n < 8190) line[n++] = ch; }
        if (ch == -1 && n == 0) break;
        line[n++] = '\n'; line[n] = 0;
        yy_scan_string((int)line);
        yyparse();
        if (ch == -1) break;
    }
    return 0;
}
