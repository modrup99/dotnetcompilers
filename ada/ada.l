%{
/* Scanner for an Ada subset. Ada is case-insensitive, so identifiers and keywords are
 * lower-cased. `--` starts a comment. The one lexer subtlety is the tick `'`: after a
 * value (identifier, ')', literal) it is an attribute marker (X'Image); otherwise it
 * opens a character literal ('x'). We disambiguate with g_val and read the char literal
 * straight out of the exposed input buffer (yy_buf/yy_pos). */
int pline = 1;
int g_val = 0;     /* 1 => a value just ended, so a following `'` is an attribute tick */

char *lc(char *s) { char *r = (char *)strdup((int)s); int i = 0; while (r[i]) { if (r[i] >= 'A' && r[i] <= 'Z') r[i] = r[i] + 32; i++; } return r; }

int kw(char *raw)
{
    char *b = lc(raw);
    if (strcmp(b, "with") == 0) return KWITH;
    if (strcmp(b, "use") == 0) return KUSE;
    if (strcmp(b, "procedure") == 0) return KPROCEDURE;
    if (strcmp(b, "function") == 0) return KFUNCTION;
    if (strcmp(b, "is") == 0) return KIS;
    if (strcmp(b, "begin") == 0) return KBEGIN;
    if (strcmp(b, "end") == 0) return KEND;
    if (strcmp(b, "return") == 0) return KRETURN;
    if (strcmp(b, "if") == 0) return KIF;
    if (strcmp(b, "then") == 0) return KTHEN;
    if (strcmp(b, "elsif") == 0) return KELSIF;
    if (strcmp(b, "else") == 0) return KELSE;
    if (strcmp(b, "case") == 0) return KCASE;
    if (strcmp(b, "when") == 0) return KWHEN;
    if (strcmp(b, "loop") == 0) return KLOOP;
    if (strcmp(b, "while") == 0) return KWHILE;
    if (strcmp(b, "for") == 0) return KFOR;
    if (strcmp(b, "in") == 0) return KIN;
    if (strcmp(b, "out") == 0) return KOUT;
    if (strcmp(b, "reverse") == 0) return KREVERSE;
    if (strcmp(b, "exit") == 0) return KEXIT;
    if (strcmp(b, "and") == 0) return KAND;
    if (strcmp(b, "or") == 0) return KOR;
    if (strcmp(b, "not") == 0) return KNOT;
    if (strcmp(b, "mod") == 0) return KMOD;
    if (strcmp(b, "rem") == 0) return KREM;
    if (strcmp(b, "abs") == 0) return KABS;
    if (strcmp(b, "null") == 0) return KNULL;
    if (strcmp(b, "constant") == 0) return KCONSTANT;
    if (strcmp(b, "type") == 0) return KTYPE;
    if (strcmp(b, "array") == 0) return KARRAY;
    if (strcmp(b, "of") == 0) return KOF;
    if (strcmp(b, "range") == 0) return KRANGE;
    if (strcmp(b, "others") == 0) return KOTHERS;
    if (strcmp(b, "true") == 0) return KTRUE;
    if (strcmp(b, "false") == 0) return KFALSE;
    return 0;
}

char *unq(char *y) { int n = strlen(y); char *r = (char *)malloc(n + 1); int i = 1, j = 0; while (i < n - 1) r[j++] = y[i++]; r[j] = 0; return r; }
%}
%%
[ \t\r]+            { }
"--"[^\n]*          { }
\n                  { pline++; }
"'"                 { if (g_val) { g_val = 0; return TICK; } int ch = yy_buf[yy_pos]; yy_pos++; if (yy_pos < yy_len && yy_buf[yy_pos] == 39) yy_pos++; yylval = ch; g_val = 1; return CHARLIT; }
[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?  { yylval = (int)strdup((int)yytext); g_val = 1; return FLOATLIT; }
[0-9]+              { yylval = atoi((int)yytext); g_val = 1; return INTLIT; }
\"[^\"]*\"          { yylval = (int)unq(yytext); g_val = 1; return STRINGLIT; }
[A-Za-z][A-Za-z0-9_]*  { int k = kw(yytext); if (k) { g_val = 0; return k; } yylval = (int)lc(yytext); g_val = 1; return NAME; }
":="                { g_val = 0; return ASSIGN; }
"/="                { g_val = 0; return NE; }
"<="                { g_val = 0; return LE; }
">="                { g_val = 0; return GE; }
"**"                { g_val = 0; return POW; }
"=>"                { g_val = 0; return ARROW; }
".."                { g_val = 0; return DOTDOT; }
")"                 { g_val = 1; return ')'; }
[(+\-*/&=<>;,:.]    { g_val = 0; return yytext[0]; }
.                   { return yytext[0]; }
%%
