%{
/* Scanner for a Lua subset. Lua tokens: -- line comments, "..."/'...' strings,
 * numbers, names, the keywords, and the operator/punctuation set including .. (concat). */
int pline = 1;

char *unesc(char *y)   /* "..." or '...' with backslash escapes */
{
    int n = strlen(y); char *r = (char *)malloc(n + 1); int i = 1, j = 0;
    while (i < n - 1) {
        if (y[i] == '\\') {
            i++;
            if (y[i] == 'n') r[j++] = 10;
            else if (y[i] == 't') r[j++] = 9;
            else if (y[i] == 'r') r[j++] = 13;
            else r[j++] = y[i];
            i++;
        } else r[j++] = y[i++];
    }
    r[j] = 0; return r;
}
%}
%%
[ \t\r]+            { }
"--"[^\n]*          { }
\n                  { pline++; }
\"([^\"\\]|\\.)*\"  { yylval = (int)unesc(yytext); return STRING; }
'([^'\\]|\\.)*'     { yylval = (int)unesc(yytext); return STRING; }
[0-9]+\.[0-9]+      { yylval = (int)strdup((int)yytext); return NUMBER; }
[0-9]+              { yylval = (int)strdup((int)yytext); return NUMBER; }
[A-Za-z_][A-Za-z0-9_]*  {
        if (strcmp(yytext, "and") == 0) return AND;
        if (strcmp(yytext, "break") == 0) return BREAK;
        if (strcmp(yytext, "do") == 0) return DO;
        if (strcmp(yytext, "else") == 0) return ELSE;
        if (strcmp(yytext, "elseif") == 0) return ELSEIF;
        if (strcmp(yytext, "end") == 0) return END;
        if (strcmp(yytext, "false") == 0) return FALSE;
        if (strcmp(yytext, "for") == 0) return FOR;
        if (strcmp(yytext, "function") == 0) return FUNCTION;
        if (strcmp(yytext, "if") == 0) return IF;
        if (strcmp(yytext, "in") == 0) return IN;
        if (strcmp(yytext, "local") == 0) return LOCAL;
        if (strcmp(yytext, "nil") == 0) return NIL;
        if (strcmp(yytext, "not") == 0) return NOT;
        if (strcmp(yytext, "or") == 0) return OR;
        if (strcmp(yytext, "repeat") == 0) return REPEAT;
        if (strcmp(yytext, "return") == 0) return RETURN;
        if (strcmp(yytext, "then") == 0) return THEN;
        if (strcmp(yytext, "true") == 0) return TRUE;
        if (strcmp(yytext, "until") == 0) return UNTIL;
        if (strcmp(yytext, "while") == 0) return WHILE;
        yylval = (int)strdup((int)yytext); return NAME; }
".."                { return CONCAT; }
"=="                { return EQ; }
"~="                { return NE; }
"<="                { return LE; }
">="                { return GE; }
[-+*/%^#=<>(){}\[\];:,.]  { return yytext[0]; }
.                   { return yytext[0]; }
%%
