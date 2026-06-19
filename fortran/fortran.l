%{
/* Scanner for Fortran 90 (free-form subset). Free-form means whitespace is
 * significant, so the classic fixed-form DO-loop lexing pathology is gone. `!` to
 * end-of-line is a comment; a trailing `&` continues a line; `;` separates
 * statements; a newline ends a statement (EOL). Fortran is case-insensitive, so
 * identifiers are lower-cased and keywords matched case-insensitively. Multi-word
 * forms (`end if`, `else if`, `select case`, `do while`, ...) are single tokens. */
int pline = 1;

int kw(char *s)
{
    char b[64]; int i = 0;
    while (s[i] && i < 63) { b[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i]; i++; }
    b[i] = 0;
    if (strcmp(b, "program") == 0) return KPROGRAM;
    if (strcmp(b, "subroutine") == 0) return KSUBROUTINE;
    if (strcmp(b, "function") == 0) return KFUNCTION;
    if (strcmp(b, "end") == 0) return KEND;
    if (strcmp(b, "if") == 0) return KIF;
    if (strcmp(b, "then") == 0) return KTHEN;
    if (strcmp(b, "else") == 0) return KELSE;
    if (strcmp(b, "do") == 0) return KDO;
    if (strcmp(b, "case") == 0) return KCASE;
    if (strcmp(b, "call") == 0) return KCALL;
    if (strcmp(b, "return") == 0) return KRETURN;
    if (strcmp(b, "stop") == 0) return KSTOP;
    if (strcmp(b, "exit") == 0) return KEXIT;
    if (strcmp(b, "cycle") == 0) return KCYCLE;
    if (strcmp(b, "print") == 0) return KPRINT;
    if (strcmp(b, "read") == 0) return KREAD;
    if (strcmp(b, "integer") == 0) return KINTEGER;
    if (strcmp(b, "real") == 0) return KREAL;
    if (strcmp(b, "logical") == 0) return KLOGICAL;
    if (strcmp(b, "character") == 0) return KCHARACTER;
    if (strcmp(b, "parameter") == 0) return KPARAMETER;
    if (strcmp(b, "dimension") == 0) return KDIMENSION;
    if (strcmp(b, "len") == 0) return KLEN;
    if (strcmp(b, "result") == 0) return KRESULT;
    return 0;
}

char *unq(char *y)   /* strip surrounding quotes of a string literal */
{
    int n = strlen(y); char *r = (char *)malloc(n + 1); int i = 1, j = 0;
    while (i < n - 1) { r[j++] = y[i++]; } r[j] = 0; return r;
}
%}
%%
[ \t]+              { }
"!"[^\n]*           { }
&[ \t]*\n[ \t]*&?   { pline++; }            /* line continuation */
&[ \t]*\n           { pline++; }
\n                  { pline++; return EOL; }
;                   { return EOL; }
[Ee][Nn][Dd][ \t]+[Ii][Ff]                         { return ENDIF; }
[Ee][Nn][Dd][Ii][Ff]                               { return ENDIF; }
[Ee][Nn][Dd][ \t]+[Dd][Oo]                         { return ENDDO; }
[Ee][Nn][Dd][Dd][Oo]                               { return ENDDO; }
[Ee][Nn][Dd][ \t]+[Ss][Ee][Ll][Ee][Cc][Tt]         { return ENDSELECT; }
[Ee][Nn][Dd][ \t]+[Ss][Uu][Bb][Rr][Oo][Uu][Tt][Ii][Nn][Ee]   { return ENDSUB; }
[Ee][Nn][Dd][ \t]+[Ff][Uu][Nn][Cc][Tt][Ii][Oo][Nn]          { return ENDFUNC; }
[Ee][Nn][Dd][ \t]+[Pp][Rr][Oo][Gg][Rr][Aa][Mm]             { return ENDPROG; }
[Ee][Ll][Ss][Ee][ \t]+[Ii][Ff]                     { return ELSEIF; }
[Ee][Ll][Ss][Ee][Ii][Ff]                           { return ELSEIF; }
[Ss][Ee][Ll][Ee][Cc][Tt][ \t]+[Cc][Aa][Ss][Ee]    { return SELECTCASE; }
[Dd][Oo][ \t]+[Ww][Hh][Ii][Ll][Ee]                 { return DOWHILE; }
[Cc][Aa][Ss][Ee][ \t]+[Dd][Ee][Ff][Aa][Uu][Ll][Tt]  { return CASEDEFAULT; }
[Dd][Oo][Uu][Bb][Ll][Ee][ \t]+[Pp][Rr][Ee][Cc][Ii][Ss][Ii][Oo][Nn]  { return KREAL; }
[Ii][Mm][Pp][Ll][Ii][Cc][Ii][Tt][ \t]+[Nn][Oo][Nn][Ee]   { return IMPLICITNONE; }
\.[Tt][Rr][Uu][Ee]\.       { return TRUE; }
\.[Ff][Aa][Ll][Ss][Ee]\.   { return FALSE; }
\.[Aa][Nn][Dd]\.           { return AND; }
\.[Oo][Rr]\.               { return OR; }
\.[Nn][Oo][Tt]\.           { return NOT; }
\.[Ee][Qq]\.               { return EQ; }
\.[Nn][Ee]\.               { return NE; }
\.[Ll][Tt]\.               { return LT; }
\.[Ll][Ee]\.               { return LE; }
\.[Gg][Tt]\.               { return GT; }
\.[Gg][Ee]\.               { return GE; }
[0-9]+\.[0-9]*([eEdD][+-]?[0-9]+)?  { yylval = (int)strdup((int)yytext); return REALLIT; }
\.[0-9]+([eEdD][+-]?[0-9]+)?        { yylval = (int)strdup((int)yytext); return REALLIT; }
[0-9]+[eEdD][+-]?[0-9]+              { yylval = (int)strdup((int)yytext); return REALLIT; }
[0-9]+              { yylval = atoi((int)yytext); return INTLIT; }
'[^']*'             { yylval = (int)unq(yytext); return STRLIT; }
\"[^\"]*\"          { yylval = (int)unq(yytext); return STRLIT; }
[A-Za-z][A-Za-z0-9_]*   { int k = kw(yytext); if (k) return k; char *s = (char *)strdup((int)yytext); int i = 0; while (s[i]) { if (s[i] >= 'A' && s[i] <= 'Z') s[i] = s[i] + 32; i++; } yylval = (int)s; return NAME; }
"**"                { return POW; }
"=="                { return EQ; }
"/="                { return NE; }
"<="                { return LE; }
">="                { return GE; }
"//"                { return CONCAT; }
"::"                { return DCOLON; }
"<"                 { return LT; }
">"                 { return GT; }
[-+*/()=,:%]        { return yytext[0]; }
.                   { return yytext[0]; }
%%
