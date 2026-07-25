%{
/* calc — a four-function calculator with variables, in about 60 lines of grammar.
 *
 * The point of the exercise: precedence and associativity are declared, not coded.
 * The expression grammar below is deliberately ambiguous (expr : expr '+' expr),
 * and the %left/%right lines are what make it deterministic.
 *
 * Semantic values are int (there is no %union in our yacc), so doubles are boxed:
 * num() allocates 8 bytes and returns the address as an int handle, val() reads it
 * back. Casts like (int)yytext and (int)"..." are what our C subset wants for
 * pointer-to-int arguments.
 */

double *dummy;                                   /* forces `double` into scope early */

int num(double d) { double *p = (double *)malloc(8); *p = d; return (int)p; }   /* box   */
double val(int h) { return *((double *)h); }                                    /* unbox */

/* variables: two parallel arrays, linear search. 26 letters would do; 512 is plenty. */
char *vname[512]; double vval[512]; int nvar;

double getvar(char *n)
{
    int i;
    for (i = 0; i < nvar; i++) if (strcmp(vname[i], n) == 0) return vval[i];
    return 0;                                    /* undefined reads as 0, like real bc */
}
void setvar(char *n, double v)
{
    int i;
    for (i = 0; i < nvar; i++) if (strcmp(vname[i], n) == 0) { vval[i] = v; return; }
    vname[nvar] = (char *)strdup((int)n); vval[nvar] = v; nvar++;
}

int yylex();
%}

%token NUMBER NAME

/* Precedence, lowest line first. `=` is right-associative so a = b = 3 works;
 * '*' and '/' bind tighter than '+' and '-'; UMINUS is a pseudo-token that exists
 * only to give the unary-minus rule a precedence of its own via %prec. */
%right '='
%left  '+' '-'
%left  '*' '/'
%right UMINUS

%start input
%%
input   : /* empty */
        | input line
        ;

line    : '\n'
        | expr '\n'            { printf((int)"%.10g\n", val($1)); }
        ;

expr    : NUMBER               { $$ = $1; }
        | NAME                 { $$ = num(getvar((char *)$1)); }
        | NAME '=' expr        { setvar((char *)$1, val($3)); $$ = $3; }
        | expr '+' expr        { $$ = num(val($1) + val($3)); }
        | expr '-' expr        { $$ = num(val($1) - val($3)); }
        | expr '*' expr        { $$ = num(val($1) * val($3)); }
        | expr '/' expr        { $$ = num(val($1) / val($3)); }
        | '-' expr %prec UMINUS { $$ = num(-val($2)); }
        | '(' expr ')'         { $$ = $2; }
        ;
%%

/* A REPL: one line per yyparse() call, so a syntax error costs only that line.
 * yy_scan_string() points the generated scanner at a buffer; without it the
 * scanner would slurp all of stdin on the first yylex().
 */
int main(int argc, char **argv)
{
    char line[4096];
    while (1)
    {
        int n = 0; int ch;
        while ((ch = getchar()) != -1 && ch != '\n') { if (ch != 13 && n < 4090) line[n++] = (char)ch; }
        if (ch == -1 && n == 0) break;
        line[n++] = '\n'; line[n] = 0;
        yy_scan_string((int)line);
        yyparse();
        if (ch == -1) break;
    }
    return 0;
}
