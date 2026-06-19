%{
/* Scanner for a free-format COBOL subset. Free-format (vs the columnar fixed format)
 * is the Fortran-style escape from the column pathology: columns don't matter, `*>`
 * starts a comment. COBOL is case-insensitive, so words are upper-cased before keyword
 * lookup and names are stored upper-cased.
 *
 * Two COBOL-specific lexer problems, handled without start-conditions (our lex has
 * none): (1) the PICTURE clause is grabbed as ONE token by a self-contained regex that
 * allows an internal `.` only when glued to a following picture char, so the
 * sentence-ending period is NOT swallowed; (2) the period is a terminator only when it
 * is a lone `.` (a decimal point is matched first, by the numeric-literal rule). */
int pline = 1;

char *upcopy(char *s) { char *r = (char *)strdup((int)s); int i = 0; while (r[i]) { if (r[i] >= 'a' && r[i] <= 'z') r[i] = r[i] - 32; i++; } return r; }

int kw(char *raw)
{
    char *b = upcopy(raw);
    if (strcmp(b, "IDENTIFICATION") == 0 || strcmp(b, "ID") == 0) return KIDENT;
    if (strcmp(b, "DIVISION") == 0) return KDIVISION;
    if (strcmp(b, "PROGRAM-ID") == 0) return KPROGRAMID;
    if (strcmp(b, "ENVIRONMENT") == 0) return KENVIRONMENT;
    if (strcmp(b, "CONFIGURATION") == 0) return KCONFIG;
    if (strcmp(b, "DATA") == 0) return KDATA;
    if (strcmp(b, "WORKING-STORAGE") == 0) return KWORKING;
    if (strcmp(b, "LINKAGE") == 0) return KLINKAGE;
    if (strcmp(b, "SECTION") == 0) return KSECTION;
    if (strcmp(b, "PROCEDURE") == 0) return KPROCEDURE;
    if (strcmp(b, "IS") == 0) return KIS;
    if (strcmp(b, "VALUE") == 0 || strcmp(b, "VALUES") == 0) return KVALUE;
    if (strcmp(b, "OCCURS") == 0) return KOCCURS;
    if (strcmp(b, "TIMES") == 0) return KTIMES;
    if (strcmp(b, "DISPLAY") == 0) return KDISPLAY;
    if (strcmp(b, "ACCEPT") == 0) return KACCEPT;
    if (strcmp(b, "MOVE") == 0) return KMOVE;
    if (strcmp(b, "TO") == 0) return KTO;
    if (strcmp(b, "FROM") == 0) return KFROM;
    if (strcmp(b, "GIVING") == 0) return KGIVING;
    if (strcmp(b, "ADD") == 0) return KADD;
    if (strcmp(b, "SUBTRACT") == 0) return KSUBTRACT;
    if (strcmp(b, "MULTIPLY") == 0) return KMULTIPLY;
    if (strcmp(b, "DIVIDE") == 0) return KDIVIDE;
    if (strcmp(b, "INTO") == 0) return KINTO;
    if (strcmp(b, "BY") == 0) return KBY;
    if (strcmp(b, "COMPUTE") == 0) return KCOMPUTE;
    if (strcmp(b, "ROUNDED") == 0) return KROUNDED;
    if (strcmp(b, "IF") == 0) return KIF;
    if (strcmp(b, "THEN") == 0) return KTHEN;
    if (strcmp(b, "ELSE") == 0) return KELSE;
    if (strcmp(b, "END-IF") == 0) return KENDIF;
    if (strcmp(b, "PERFORM") == 0) return KPERFORM;
    if (strcmp(b, "END-PERFORM") == 0) return KENDPERF;
    if (strcmp(b, "UNTIL") == 0) return KUNTIL;
    if (strcmp(b, "VARYING") == 0) return KVARYING;
    if (strcmp(b, "EVALUATE") == 0) return KEVALUATE;
    if (strcmp(b, "WHEN") == 0) return KWHEN;
    if (strcmp(b, "OTHER") == 0) return KOTHER;
    if (strcmp(b, "END-EVALUATE") == 0) return KENDEVAL;
    if (strcmp(b, "STOP") == 0) return KSTOP;
    if (strcmp(b, "RUN") == 0) return KRUN;
    if (strcmp(b, "GOBACK") == 0) return KGOBACK;
    if (strcmp(b, "GO") == 0) return KGO;
    if (strcmp(b, "NOT") == 0) return KNOT;
    if (strcmp(b, "AND") == 0) return KAND;
    if (strcmp(b, "OR") == 0) return KOR;
    if (strcmp(b, "EQUAL") == 0 || strcmp(b, "EQUALS") == 0) return KEQUAL;
    if (strcmp(b, "GREATER") == 0) return KGREATER;
    if (strcmp(b, "LESS") == 0) return KLESS;
    if (strcmp(b, "THAN") == 0) return KTHAN;
    if (strcmp(b, "THRU") == 0 || strcmp(b, "THROUGH") == 0) return KTHRU;
    if (strcmp(b, "ZERO") == 0 || strcmp(b, "ZEROS") == 0 || strcmp(b, "ZEROES") == 0) return KZERO;
    if (strcmp(b, "SPACE") == 0 || strcmp(b, "SPACES") == 0) return KSPACES;
    if (strcmp(b, "CONTINUE") == 0) return KCONTINUE;
    return 0;
}

char *unq(char *y) { int n = strlen(y); char *r = (char *)malloc(n + 1); int i = 1, j = 0; while (i < n - 1) r[j++] = y[i++]; r[j] = 0; return r; }

/* From a matched "PIC ... <body>" lexeme, drop PIC/PICTURE, optional IS, and whitespace */
char *pic_of(char *y)
{
    int i = 0;
    while (y[i] && y[i] != ' ' && y[i] != '\t') i++;       /* skip PIC / PICTURE */
    while (y[i] == ' ' || y[i] == '\t') i++;
    char *up = upcopy(y + i);
    if (up[0] == 'I' && up[1] == 'S' && (up[2] == ' ' || up[2] == '\t')) { int k = 2; while (up[k] == ' ' || up[k] == '\t') k++; return up + k; }
    return up;
}
%}
%%
[ \t\r]+            { }
"*>"[^\n]*          { }
\n                  { pline++; }
[Pp][Ii][Cc]([Tt][Uu][Rr][Ee])?[ \t]+([Ii][Ss][ \t]+)?([Xx9AaZzBbSsVvPpGgNn0$*/,+-]|\([0-9]+\)|\.[Xx9AaZzBbSsVvPpGgNn0$*/,+-])+   { yylval = (int)pic_of(yytext); return PICTURE; }
[0-9]+\.[0-9]+      { yylval = (int)strdup((int)yytext); return REALLIT; }
[0-9]+              { yylval = atoi((int)yytext); return INTLIT; }
\"[^\"]*\"          { yylval = (int)unq(yytext); return STRLIT; }
'[^']*'             { yylval = (int)unq(yytext); return STRLIT; }
[A-Za-z][A-Za-z0-9]*(-[A-Za-z0-9]+)*   { int k = kw(yytext); if (k) return k; yylval = (int)upcopy(yytext); return NAME; }
">="                { return KGE; }
"<="                { return KLE; }
"<>"                { return KNE; }
"**"                { return POW; }
"="                 { return '='; }
"<"                 { return '<'; }
">"                 { return '>'; }
\.                  { return PERIOD; }
[-+*/()]            { return yytext[0]; }
.                   { return yytext[0]; }
%%
