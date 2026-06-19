%{
/* Forth scanner (lex). Whitespace-delimited tokens. `:` and `;` are words;
 * control words (IF/THEN/...) are recognized as keywords; everything else is a
 * generic WORD resolved by the parser (primitive -> inline C, else user word).
 * `( ... )` and `\ ...` are comments; `." ..."` / `S" ..."` carry a string. */
int pline = 1;

int kw(char *s)
{
    char b[128]; int i = 0;
    while (s[i] && i < 127) { char c = s[i]; if (c >= 'a' && c <= 'z') c = c - 32; b[i] = c; i++; }
    b[i] = 0;
    if (strcmp(b, ":") == 0) return COLON;
    if (strcmp(b, ";") == 0) return SEMI;
    if (strcmp(b, "IF") == 0) return KIF;
    if (strcmp(b, "ELSE") == 0) return KELSE;
    if (strcmp(b, "THEN") == 0) return KTHEN;
    if (strcmp(b, "BEGIN") == 0) return KBEGIN;
    if (strcmp(b, "UNTIL") == 0) return KUNTIL;
    if (strcmp(b, "WHILE") == 0) return KWHILE;
    if (strcmp(b, "REPEAT") == 0) return KREPEAT;
    if (strcmp(b, "DO") == 0) return KDO;
    if (strcmp(b, "LOOP") == 0) return KLOOP;
    if (strcmp(b, "+LOOP") == 0) return KPLUSLOOP;
    if (strcmp(b, "VARIABLE") == 0) return KVARIABLE;
    if (strcmp(b, "CONSTANT") == 0) return KCONSTANT;
    return 0;
}

/* `." text"` or `S" text"` -> the text (drop the 2-char prefix, one delimiter
 * space, and the trailing quote) */
char *strbody(char *y)
{
    int n = strlen(y); int st = 2; if (y[st] == ' ') st++; int en = n - 1;
    char *r = (char *)malloc(en - st + 1); int i = 0;
    while (st < en) { r[i++] = y[st++]; } r[i] = 0; return r;
}
%}
%%
[ \t\r]+          { }
\n                { pline++; }
"("[^)]*")"       { }
\\[^\n]*          { }
\.\"[^\"]*\"      { yylval = (int)strbody(yytext); return DOTQ; }
[Ss]\"[^\"]*\"    { yylval = (int)strbody(yytext); return SQ; }
-?[0-9]+\.[0-9]*  { yylval = (int)strdup((int)yytext); return FLOAT; }
-?[0-9]+          { yylval = atoi((int)yytext); return INT; }
[^ \t\r\n]+       { int k = kw(yytext); if (k) return k; yylval = (int)strdup((int)yytext); return WORD; }
%%
