%{
/* calc scanner — the token side of the classic lex+yacc calculator.
 *
 * Everything above the first %% is copied verbatim into the generated C. The
 * token names (NUMBER, NAME) are NOT declared here: `yacc` emits them as an
 * enum, which is why out/calc_parse.c must be concatenated BEFORE this file's
 * output. `yylval` is likewise declared by the parser.
 *
 * yacc's value stack is `int`, so a double is boxed on the heap by num() (see
 * calc.y) and the int handle is what travels in yylval.
 */
%}

/* Named definitions may be referenced from a pattern as {NAME}. */
DIGIT   [0-9]
ALPHA   [A-Za-z_]

%%
[ \t]+                          { }                     /* skip blanks: no return = keep scanning */
"#"[^\n]*                       { }                     /* comment to end of line */
{DIGIT}+("."{DIGIT}*)?          { yylval = num(atof((int)yytext)); return NUMBER; }
"."{DIGIT}+                     { yylval = num(atof((int)yytext)); return NUMBER; }
{ALPHA}({ALPHA}|{DIGIT})*       { yylval = (int)strdup((int)yytext); return NAME; }
\n                              { return '\n'; }
[-+*/()=]                       { return yytext[0]; }   /* single-char tokens are their own code */
.                               { return yytext[0]; }   /* anything else: let the parser complain */
%%
