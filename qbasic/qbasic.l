%{
/* QBasic scanner (lex). Lines matter: a newline (or ':') separates statements,
 * so we return EOL for newlines and ':' as a separator. Keywords fold case.
 * Identifiers keep their type-suffix ($ % ! # &). Comments: ' to end of line and
 * REM. Comments are NOT pre-stripped (apostrophe handling lives here). */
int pline = 1;
int tokln = 1;

int kw(char *s)
{
    char b[64]; int i = 0;
    while (s[i] && i < 63) { b[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i]; i++; }
    b[i] = 0;                       /* b = uppercased copy */
    if (strcmp(b, "PRINT") == 0) return KPRINT;
    if (strcmp(b, "INPUT") == 0) return KINPUT;
    if (strcmp(b, "LET") == 0) return KLET;
    if (strcmp(b, "DIM") == 0) return KDIM;
    if (strcmp(b, "AS") == 0) return KAS;
    if (strcmp(b, "IF") == 0) return KIF;
    if (strcmp(b, "THEN") == 0) return KTHEN;
    if (strcmp(b, "ELSE") == 0) return KELSE;
    if (strcmp(b, "ELSEIF") == 0) return KELSEIF;
    if (strcmp(b, "END") == 0) return KEND;
    if (strcmp(b, "ENDIF") == 0) return KENDIF;
    if (strcmp(b, "FOR") == 0) return KFOR;
    if (strcmp(b, "TO") == 0) return KTO;
    if (strcmp(b, "STEP") == 0) return KSTEP;
    if (strcmp(b, "NEXT") == 0) return KNEXT;
    if (strcmp(b, "WHILE") == 0) return KWHILE;
    if (strcmp(b, "WEND") == 0) return KWEND;
    if (strcmp(b, "DO") == 0) return KDO;
    if (strcmp(b, "LOOP") == 0) return KLOOP;
    if (strcmp(b, "UNTIL") == 0) return KUNTIL;
    if (strcmp(b, "SELECT") == 0) return KSELECT;
    if (strcmp(b, "CASE") == 0) return KCASE;
    if (strcmp(b, "IS") == 0) return KIST;
    if (strcmp(b, "GOTO") == 0) return KGOTO;
    if (strcmp(b, "SUB") == 0) return KSUB;
    if (strcmp(b, "FUNCTION") == 0) return KFUNCTION;
    if (strcmp(b, "CALL") == 0) return KCALL;
    if (strcmp(b, "STOP") == 0) return KSTOP;
    if (strcmp(b, "REM") == 0) return KREM;
    if (strcmp(b, "MOD") == 0) return KMOD;
    if (strcmp(b, "AND") == 0) return KAND;
    if (strcmp(b, "OR") == 0) return KOR;
    if (strcmp(b, "XOR") == 0) return KXOR;
    if (strcmp(b, "NOT") == 0) return KNOT;
    if (strcmp(b, "CLS") == 0) return KCLS;
    if (strcmp(b, "SCREEN") == 0) return KSCREEN;
    if (strcmp(b, "PSET") == 0) return KPSET;
    if (strcmp(b, "LINE") == 0) return KLINE;
    if (strcmp(b, "CIRCLE") == 0) return KCIRCLE;
    if (strcmp(b, "COLOR") == 0) return KCOLOR;
    if (strcmp(b, "PAINT") == 0) return KPAINT;
    if (strcmp(b, "SLEEP") == 0) return KSLEEP;
    if (strcmp(b, "RANDOMIZE") == 0) return KRANDOMIZE;
    if (strcmp(b, "INTEGER") == 0) return KINTEGER;
    if (strcmp(b, "LONG") == 0) return KLONG;
    if (strcmp(b, "SINGLE") == 0) return KSINGLE;
    if (strcmp(b, "DOUBLE") == 0) return KDOUBLE;
    if (strcmp(b, "STRING") == 0) return KSTRINGT;
    return 0;
}

/* a "string literal" with "" -> " collapsing; strip the surrounding quotes */
char *qstr(char *y)
{
    int n = strlen(y); char *r = (char *)malloc(n + 1); int i = 1, j = 0;
    while (i < n - 1) { if (y[i] == '"' && y[i + 1] == '"') { r[j++] = '"'; i += 2; } else { r[j++] = y[i]; i++; } }
    r[j] = 0; return r;
}
int hexval(char *y) { int v = 0, i = 2; while (y[i]) { int c = y[i], d = 0; if (c >= '0' && c <= '9') d = c - '0'; else if (c >= 'a' && c <= 'f') d = c - 'a' + 10; else if (c >= 'A' && c <= 'F') d = c - 'A' + 10; v = v * 16 + d; i++; } return v; }
%}
%%
[ \t]+                 { }
_[ \t]*\n              { pline++; }                 /* line continuation */
\r                     { }
\n                     { tokln = pline; pline++; return EOL; }
'[^\n]*                { }                           /* apostrophe comment */
[Rr][Ee][Mm]([ \t][^\n]*)?            { }           /* REM comment line */
[Dd][Ee][Cc][Ll][Aa][Rr][Ee][^\n]*   { }           /* ignore DECLARE (auto-generated) */
[Ee][Nn][Dd][ \t]+[Ii][Ff]                                  { return KENDIF; }
[Ee][Nn][Dd][ \t]+[Ss][Uu][Bb]                              { return KENDSUB; }
[Ee][Nn][Dd][ \t]+[Ff][Uu][Nn][Cc][Tt][Ii][Oo][Nn]         { return KENDFUNCTION; }
[Ee][Nn][Dd][ \t]+[Ss][Ee][Ll][Ee][Cc][Tt]                 { return KENDSELECT; }
[Ee][Xx][Ii][Tt][ \t]+[Ff][Oo][Rr]                          { return KEXITFOR; }
[Ee][Xx][Ii][Tt][ \t]+[Dd][Oo]                              { return KEXITDO; }
[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?   { tokln = pline; yylval = (int)strdup((int)yytext); return REALLIT; }
\.[0-9]+([eE][+-]?[0-9]+)?         { tokln = pline; yylval = (int)strdup((int)yytext); return REALLIT; }
[0-9]+[eE][+-]?[0-9]+              { tokln = pline; yylval = (int)strdup((int)yytext); return REALLIT; }
&[hH][0-9A-Fa-f]+      { tokln = pline; yylval = hexval(yytext); return INTLIT; }
[0-9]+                 { tokln = pline; yylval = atoi((int)yytext); return INTLIT; }
\"([^\"]|\"\")*\"      { tokln = pline; yylval = (int)qstr(yytext); return STRLIT; }
[A-Za-z_][A-Za-z0-9_]*[$%!#&]?   { tokln = pline; int k = kw(yytext); if (k) return k; yylval = (int)strdup((int)yytext); return IDENT; }
"<="                   { return LE; }
">="                   { return GE; }
"=<"                   { return LE; }
"=>"                   { return GE; }
"<>"                   { return NE; }
"><"                   { return NE; }
[-+*/\\^=<>(),;:.]      { return yytext[0]; }
.                      { return yytext[0]; }
%%
