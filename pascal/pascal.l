%{
/* Pascal scanner (lex). Comments are pre-stripped by the driver. Keywords are
 * matched case-insensitively (Pascal folds case); identifiers are lowercased so
 * MyVar and myvar map to the same C name. pline tracks the source line; tokln is
 * the line where the latest token began (used for #line / PDB). */
int pline = 1;
int tokln = 1;

char *lc(char *s) { int i = 0; while (s[i]) { if (s[i] >= 'A' && s[i] <= 'Z') s[i] = s[i] + 32; i++; } return s; }

int kw(char *s)
{
    char b[64]; int i = 0;
    while (s[i] && i < 63) { b[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i]; i++; }
    b[i] = 0;
    if (strcmp(b, "program") == 0) return KPROGRAM;
    if (strcmp(b, "var") == 0) return KVAR;
    if (strcmp(b, "const") == 0) return KCONST;
    if (strcmp(b, "type") == 0) return KTYPE;
    if (strcmp(b, "begin") == 0) return KBEGIN;
    if (strcmp(b, "end") == 0) return KEND;
    if (strcmp(b, "if") == 0) return KIF;
    if (strcmp(b, "then") == 0) return KTHEN;
    if (strcmp(b, "else") == 0) return KELSE;
    if (strcmp(b, "while") == 0) return KWHILE;
    if (strcmp(b, "do") == 0) return KDO;
    if (strcmp(b, "for") == 0) return KFOR;
    if (strcmp(b, "to") == 0) return KTO;
    if (strcmp(b, "downto") == 0) return KDOWNTO;
    if (strcmp(b, "repeat") == 0) return KREPEAT;
    if (strcmp(b, "until") == 0) return KUNTIL;
    if (strcmp(b, "case") == 0) return KCASE;
    if (strcmp(b, "of") == 0) return KOF;
    if (strcmp(b, "procedure") == 0) return KPROCEDURE;
    if (strcmp(b, "function") == 0) return KFUNCTION;
    if (strcmp(b, "and") == 0) return KAND;
    if (strcmp(b, "or") == 0) return KOR;
    if (strcmp(b, "not") == 0) return KNOT;
    if (strcmp(b, "div") == 0) return KDIV;
    if (strcmp(b, "mod") == 0) return KMOD;
    if (strcmp(b, "true") == 0) return KTRUE;
    if (strcmp(b, "false") == 0) return KFALSE;
    if (strcmp(b, "array") == 0) return KARRAY;
    if (strcmp(b, "record") == 0) return KRECORD;
    if (strcmp(b, "nil") == 0) return KNIL;
    if (strcmp(b, "goto") == 0) return KGOTO;
    if (strcmp(b, "label") == 0) return KLABEL;
    if (strcmp(b, "with") == 0) return KWITH;
    if (strcmp(b, "forward") == 0) return KFORWARD;
    if (strcmp(b, "in") == 0) return KIN;
    if (strcmp(b, "object") == 0) return KOBJECT;
    if (strcmp(b, "constructor") == 0) return KCONSTRUCTOR;
    if (strcmp(b, "destructor") == 0) return KDESTRUCTOR;
    if (strcmp(b, "virtual") == 0) return KVIRTUAL;
    if (strcmp(b, "set") == 0) return KSET;
    return 0;
}

/* process a 'string literal': strip the quotes and collapse '' -> ' */
char *pstr(char *y)
{
    int n = strlen(y);
    char *r = (char *)malloc(n + 1);
    int i = 1, j = 0;                 /* skip leading quote */
    while (i < n - 1)
    {
        if (y[i] == '\'' && y[i + 1] == '\'') { r[j++] = '\''; i += 2; }
        else { r[j++] = y[i]; i++; }
    }
    r[j] = 0;
    return r;
}
%}
%%
[ \t\r]+        { }
\n              { pline++; }
[A-Za-z_][A-Za-z0-9_]*   { tokln = pline; int k = kw(yytext); if (k) return k; yylval = (int)lc((char *)strdup((int)yytext)); return IDENT; }
[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?   { tokln = pline; yylval = (int)strdup((int)yytext); return REALLIT; }
[0-9]+          { tokln = pline; yylval = atoi((int)yytext); return INTLIT; }
'([^']|'')*'    { tokln = pline; char *s = pstr(yytext); yylval = (int)s; return strlen(s) == 1 ? CHARLIT : STRLIT; }
":="            { return ASSIGN; }
"<="            { return LE; }
">="            { return GE; }
"<>"            { return NE; }
".."            { return DOTDOT; }
[-+*/=<>(),;:.\[\]^@]   { return yytext[0]; }
.               { return yytext[0]; }
%%
