%{
/* Scanner for Tiny C++ (tcpp). C/C++ lexis. The classic "lexer hack": an
 * identifier that has been declared a type (typedef / class / struct name) is
 * returned as TYPENAME so the grammar can tell declarations from expressions.
 * Comments are pre-stripped by the driver. */
int pline = 1;
int tokln = 1;

int kw(char *s)
{
    if (strcmp(s, "int") == 0) return KINT;
    if (strcmp(s, "char") == 0) return KCHAR;
    if (strcmp(s, "void") == 0) return KVOID;
    if (strcmp(s, "double") == 0) return KDOUBLE;
    if (strcmp(s, "float") == 0) return KDOUBLE;
    if (strcmp(s, "long") == 0) return KLONG;
    if (strcmp(s, "short") == 0 || strcmp(s, "unsigned") == 0 || strcmp(s, "signed") == 0) return KINT;
    if (strcmp(s, "bool") == 0) return KBOOL;
    if (strcmp(s, "const") == 0) return KCONST;
    if (strcmp(s, "if") == 0) return KIF;
    if (strcmp(s, "else") == 0) return KELSE;
    if (strcmp(s, "while") == 0) return KWHILE;
    if (strcmp(s, "for") == 0) return KFOR;
    if (strcmp(s, "do") == 0) return KDO;
    if (strcmp(s, "return") == 0) return KRETURN;
    if (strcmp(s, "break") == 0) return KBREAK;
    if (strcmp(s, "continue") == 0) return KCONTINUE;
    if (strcmp(s, "switch") == 0) return KSWITCH;
    if (strcmp(s, "case") == 0) return KCASE;
    if (strcmp(s, "default") == 0) return KDEFAULT;
    if (strcmp(s, "struct") == 0) return KSTRUCT;
    if (strcmp(s, "class") == 0) return KCLASS;
    if (strcmp(s, "enum") == 0) return KENUM;
    if (strcmp(s, "typedef") == 0) return KTYPEDEF;
    if (strcmp(s, "sizeof") == 0) return KSIZEOF;
    if (strcmp(s, "public") == 0) return KPUBLIC;
    if (strcmp(s, "private") == 0) return KPRIVATE;
    if (strcmp(s, "protected") == 0) return KPROTECTED;
    if (strcmp(s, "virtual") == 0) return KVIRTUAL;
    if (strcmp(s, "new") == 0) return KNEW;
    if (strcmp(s, "delete") == 0) return KDELETE;
    if (strcmp(s, "true") == 0) return KTRUE;
    if (strcmp(s, "false") == 0) return KFALSE;
    if (strcmp(s, "this") == 0) return KTHIS;
    return 0;
}
%}
%%
[ \t\r]+        { }
\n              { pline++; }
^#[^\n]*        { }                       /* pass over any leftover preprocessor lines */
[A-Za-z_][A-Za-z0-9_]*   { tokln = pline; int k = kw(yytext); if (k) return k; yylval = (int)strdup((int)yytext); return is_typename(yytext) ? TYPENAME : IDENT; }
0[xX][0-9a-fA-F]+   { tokln = pline; yylval = (int)strdup((int)yytext); return INTLIT; }
[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?   { tokln = pline; yylval = (int)strdup((int)yytext); return REALLIT; }
[0-9]+          { tokln = pline; yylval = (int)strdup((int)yytext); return INTLIT; }
\"([^\"\\]|\\.)*\"   { tokln = pline; yylval = (int)strdup((int)yytext); return STRLIT; }
'([^'\\]|\\.)*'  { tokln = pline; yylval = (int)strdup((int)yytext); return CHARLIT; }
"::"            { return SCOPE; }
"++"            { return INC; }
"--"            { return DEC; }
"->"            { return ARROW; }
"<<"            { return SHL; }
">>"            { return SHR; }
"<="            { return LE; }
">="            { return GE; }
"=="            { return EQ; }
"!="            { return NE; }
"&&"            { return ANDAND; }
"||"            { return OROR; }
"+="            { return PLUSEQ; }
"-="            { return MINUSEQ; }
"*="            { return STAREQ; }
"/="            { return SLASHEQ; }
"%="            { return PCTEQ; }
"&="            { return AMPEQ; }
"|="            { return PIPEEQ; }
"^="            { return CARETEQ; }
[-+*/%=<>(){}\[\];,.&|^!~?:]   { return yytext[0]; }
.               { return yytext[0]; }
%%
