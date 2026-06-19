%{
/* Scanner for `bc` — a text scientific calculator. Tokens feed the yacc grammar,
 * which evaluates with syntax-directed actions. Numbers are boxed as double handles
 * (yacc's value stack is int). `q`/`quit` exits. # starts a comment. */
%}
%%
[ \t]+          { }
#[^\n]*         { }
[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?  { yylval = num(atof((int)yytext)); return NUMBER; }
\.[0-9]+([eE][+-]?[0-9]+)?        { yylval = num(atof((int)yytext)); return NUMBER; }
[0-9]+([eE][+-]?[0-9]+)?          { yylval = num(atof((int)yytext)); return NUMBER; }
[A-Za-z_][A-Za-z0-9_]*  { if (strcmp(yytext, "quit") == 0 || strcmp(yytext, "q") == 0) return QUIT; yylval = (int)strdup((int)yytext); return NAME; }
"=="            { return EQ; }
"!="            { return NE; }
"<="            { return LE; }
">="            { return GE; }
"&&"            { return AND; }
"||"            { return OR; }
"+="            { return PLUSEQ; }
"-="            { return MINUSEQ; }
"*="            { return STAREQ; }
"/="            { return SLASHEQ; }
"%="            { return PCTEQ; }
"^="            { return CARETEQ; }
\n              { return '\n'; }
[-+*/%^()=<>!,;] { return yytext[0]; }
.               { return yytext[0]; }
%%
