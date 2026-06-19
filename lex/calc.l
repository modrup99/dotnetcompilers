%{
/* a small tokenizer to demonstrate the generated scanner */
%}
DIGIT   [0-9]
ID      [a-zA-Z_][a-zA-Z0-9_]*
%%
[ \t\n]+        { /* skip whitespace */ }
{DIGIT}+        { printf("NUMBER(%d)\n", atoi(yytext)); }
{ID}            { printf("IDENT(%s)\n", yytext); }
"=="            { printf("EQ\n"); }
"="             { printf("ASSIGN\n"); }
"+"             { printf("PLUS\n"); }
"*"             { printf("STAR\n"); }
.               { printf("OTHER(%s)\n", yytext); }
%%
int main(void) {
    yy_scan_string("foo = 42 + bar*7 == 100");
    yylex();
    return 0;
}
