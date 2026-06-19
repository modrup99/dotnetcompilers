%{
/* Scanner for a combined Modula-2 / Oberon-2 compiler. Wirth-family lexis:
 * case-SENSITIVE, keywords are UPPERCASE; operators include # (<>), & (AND),
 * ~ (NOT); sets use { }. Nested (* *) comments are pre-stripped by the driver. */
int pline = 1;
int tokln = 1;

int kw(char *s)   /* exact (case-sensitive) keyword match */
{
    if (strcmp(s, "MODULE") == 0) return KMODULE;
    if (strcmp(s, "BEGIN") == 0) return KBEGIN;
    if (strcmp(s, "END") == 0) return KEND;
    if (strcmp(s, "CONST") == 0) return KCONST;
    if (strcmp(s, "TYPE") == 0) return KTYPE;
    if (strcmp(s, "VAR") == 0) return KVAR;
    if (strcmp(s, "PROCEDURE") == 0) return KPROCEDURE;
    if (strcmp(s, "IF") == 0) return KIF;
    if (strcmp(s, "THEN") == 0) return KTHEN;
    if (strcmp(s, "ELSIF") == 0) return KELSIF;
    if (strcmp(s, "ELSE") == 0) return KELSE;
    if (strcmp(s, "WHILE") == 0) return KWHILE;
    if (strcmp(s, "DO") == 0) return KDO;
    if (strcmp(s, "REPEAT") == 0) return KREPEAT;
    if (strcmp(s, "UNTIL") == 0) return KUNTIL;
    if (strcmp(s, "FOR") == 0) return KFOR;
    if (strcmp(s, "TO") == 0) return KTO;
    if (strcmp(s, "BY") == 0) return KBY;
    if (strcmp(s, "CASE") == 0) return KCASE;
    if (strcmp(s, "OF") == 0) return KOF;
    if (strcmp(s, "LOOP") == 0) return KLOOP;
    if (strcmp(s, "EXIT") == 0) return KEXIT;
    if (strcmp(s, "RETURN") == 0) return KRETURN;
    if (strcmp(s, "ARRAY") == 0) return KARRAY;
    if (strcmp(s, "RECORD") == 0) return KRECORD;
    if (strcmp(s, "POINTER") == 0) return KPOINTER;
    if (strcmp(s, "SET") == 0) return KSET;
    if (strcmp(s, "DIV") == 0) return KDIV;
    if (strcmp(s, "MOD") == 0) return KMOD;
    if (strcmp(s, "AND") == 0) return KAND;
    if (strcmp(s, "OR") == 0) return KOR;
    if (strcmp(s, "NOT") == 0) return KNOT;
    if (strcmp(s, "IN") == 0) return KIN;
    if (strcmp(s, "NIL") == 0) return KNIL;
    if (strcmp(s, "TRUE") == 0) return KTRUE;
    if (strcmp(s, "FALSE") == 0) return KFALSE;
    if (strcmp(s, "WITH") == 0) return KWITH;
    if (strcmp(s, "IMPORT") == 0) return KIMPORT;
    if (strcmp(s, "FROM") == 0) return KFROM;
    if (strcmp(s, "DEFINITION") == 0) return KDEF;
    if (strcmp(s, "IMPLEMENTATION") == 0) return KIMPL;
    return 0;
}
%}
%%
[ \t\r]+        { }
\n              { pline++; }
[A-Za-z][A-Za-z0-9_]*   { tokln = pline; int k = kw(yytext); if (k) return k; yylval = (int)strdup((int)yytext); return IDENT; }
[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?   { tokln = pline; yylval = (int)strdup((int)yytext); return REALLIT; }
[0-9]+          { tokln = pline; yylval = atoi((int)yytext); return INTLIT; }
\"[^\"]*\"      { tokln = pline; char *t = yytext; t[strlen(t) - 1] = 0; yylval = (int)strdup((int)(t + 1)); return STRLIT; }
'[^']*'         { tokln = pline; char *t = yytext; t[strlen(t) - 1] = 0; yylval = (int)strdup((int)(t + 1)); return STRLIT; }
":="            { return ASSIGN; }
".."            { return DOTDOT; }
"<="            { return LE; }
">="            { return GE; }
"<>"            { return NE; }
"#"             { return NE; }
"&"             { return KAND; }
"~"             { return KNOT; }
[-+*/=<>(),;:.\[\]{}^|]   { return yytext[0]; }
.               { return yytext[0]; }
%%
