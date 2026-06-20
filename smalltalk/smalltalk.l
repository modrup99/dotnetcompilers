%{
/* Scanner for a Smalltalk subset. Smalltalk's tokens: `'strings'`, "comments" (double
 * quotes!), #symbols, keyword selectors (ident:), binary selectors (runs of special
 * chars), and the pseudo-variables self/super/nil/true/false. The control-flow keyword
 * selectors (ifTrue:, whileTrue:, to:, do:, ...) get their own tokens so the grammar can
 * inline them; every other keyword is the generic KEYWORD token. */
int pline = 1;

char *unq(char *y)   /* 'str' with '' -> ' */
{
    int n = strlen(y); char *r = (char *)malloc(n + 1); int i = 1, j = 0;
    while (i < n - 1) { if (y[i] == '\'' && y[i + 1] == '\'') { r[j++] = '\''; i += 2; } else r[j++] = y[i++]; }
    r[j] = 0; return r;
}
%}
%%
[ \t\r]+            { }
\"[^\"]*\"          { }
\n                  { pline++; }
'([^']|'')*'        { yylval = (int)unq(yytext); return STRING; }
[0-9]+\.[0-9]+      { yylval = (int)strdup((int)yytext); return FLOATLIT; }
[0-9]+              { yylval = atoi((int)yytext); return INTLIT; }
"#"[A-Za-z_][A-Za-z0-9_]*  { yylval = (int)strdup((int)(yytext + 1)); return SYMBOL; }
":="                { return ASSIGN; }
[A-Za-z_][A-Za-z0-9_]*:    { char *s = (char *)strdup((int)yytext);
                             if (strcmp(s, "ifTrue:") == 0) return KW_IFTRUE;
                             if (strcmp(s, "ifFalse:") == 0) return KW_IFFALSE;
                             if (strcmp(s, "whileTrue:") == 0) return KW_WHILETRUE;
                             if (strcmp(s, "whileFalse:") == 0) return KW_WHILEFALSE;
                             if (strcmp(s, "timesRepeat:") == 0) return KW_TIMESREPEAT;
                             if (strcmp(s, "to:") == 0) return KW_TO;
                             if (strcmp(s, "do:") == 0) return KW_DO;
                             if (strcmp(s, "and:") == 0) return KW_AND;
                             if (strcmp(s, "or:") == 0) return KW_OR;
                             if (strcmp(s, "subclass:") == 0) return KW_SUBCLASS;
                             yylval = (int)s; return KEYWORD; }
[A-Za-z_][A-Za-z0-9_]*  { if (strcmp(yytext, "self") == 0) return KSELF;
                          if (strcmp(yytext, "super") == 0) return KSUPER;
                          if (strcmp(yytext, "nil") == 0) return KNIL;
                          if (strcmp(yytext, "true") == 0) return KTRUE;
                          if (strcmp(yytext, "false") == 0) return KFALSE;
                          yylval = (int)strdup((int)yytext); return NAME; }
"|"                 { return PIPE; }
":"                 { return COLON; }
"^"                 { return CARET; }
"!"                 { return BANG; }
[-+*/<>=~@,\\%]+     { yylval = (int)strdup((int)yytext); return BINSEL; }
[.;()\[\]]          { return yytext[0]; }
.                   { return yytext[0]; }
%%
