%{
/* Scanner for Coil (Curly-Over-IL). A minimal curly-brace language whose yacc
 * grammar lowers each construct directly to a flat stack-IL IR, which the C#
 * assembler (coilasm) turns into a real .NET assembly. Comments: // to EOL. */
int pline = 1;

int kw(char *s)
{
    if (strcmp(s, "func") == 0) return KFUNC;
    if (strcmp(s, "var") == 0) return KVAR;
    if (strcmp(s, "return") == 0) return KRETURN;
    if (strcmp(s, "if") == 0) return KIF;
    if (strcmp(s, "else") == 0) return KELSE;
    if (strcmp(s, "while") == 0) return KWHILE;
    if (strcmp(s, "print") == 0) return KPRINT;
    if (strcmp(s, "println") == 0) return KPRINTLN;
    if (strcmp(s, "true") == 0) return KTRUE;
    if (strcmp(s, "false") == 0) return KFALSE;
    if (strcmp(s, "int") == 0) return KINT;
    if (strcmp(s, "double") == 0) return KDBL;
    if (strcmp(s, "bool") == 0) return KBOOL;
    if (strcmp(s, "string") == 0) return KSTR;
    if (strcmp(s, "void") == 0) return KVOID;
    return 0;
}

/* a "string literal" with \n \t \" \\ escapes -> the raw bytes */
char *unq(char *y)
{
    int n = strlen(y); char *r = (char *)malloc(n + 1); int i = 1, j = 0;
    while (i < n - 1)
    {
        if (y[i] == '\\') { i++; char c = y[i]; r[j++] = (c == 'n') ? '\n' : (c == 't') ? '\t' : (c == 'r') ? '\r' : c; i++; }
        else { r[j++] = y[i]; i++; }
    }
    r[j] = 0; return r;
}
%}
%%
[ \t\r]+        { }
\n              { pline++; }
"//"[^\n]*      { }
[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?  { yylval = (int)strdup((int)yytext); return DBLLIT; }
[0-9]+[eE][+-]?[0-9]+             { yylval = (int)strdup((int)yytext); return DBLLIT; }
[0-9]+          { yylval = atoi((int)yytext); return INTLIT; }
\"([^\"\\]|\\.)*\"   { yylval = (int)unq(yytext); return STRLIT; }
[A-Za-z_][A-Za-z0-9_]*  { int k = kw(yytext); if (k) return k; yylval = (int)strdup((int)yytext); return IDENT; }
"->"            { return ARROW; }
"=="            { return EQ; }
"!="            { return NE; }
"<="            { return LE; }
">="            { return GE; }
"&&"            { return ANDAND; }
"||"            { return OROR; }
[-+*/%=!<>(){},;]   { return yytext[0]; }
.               { return yytext[0]; }
%%
