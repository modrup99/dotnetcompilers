%{
/* Scanner for AWK. Two AWK-specific lexer problems, both handled with the generated
 * scanner's exposed input buffer (yy_buf/yy_pos/yy_len) since our lex has no
 * start-conditions/unput:
 *   (1) `/` is regex-start in "regex position" (after an operator, '(', ',', a keyword,
 *       or statement start) but division elsewhere. We track g_val (1 = a value just
 *       ended, so `/` is divide) and, in regex position, hand-scan the regex literal.
 *   (2) a newline ends a statement EXCEPT after a token that implies continuation
 *       (`,` `{` `&&` `||` `do` `else` `?` `:` `(` `[` and binary operators) or `\`.
 *       g_cont suppresses the newline token in those cases. */
int pline = 1;
int g_val = 0;     /* 1 => previous token was a value: `/` means divide */
int g_cont = 1;    /* 1 => a following newline is a continuation (suppress) */

char *dupn(char *s, int n) { char *r = (char *)malloc(n + 1); int i; for (i = 0; i < n; i++) r[i] = s[i]; r[i] = 0; return r; }

int kw(char *s)
{
    if (strcmp(s, "BEGIN") == 0) return KBEGIN;
    if (strcmp(s, "END") == 0) return KEND;
    if (strcmp(s, "function") == 0 || strcmp(s, "func") == 0) return KFUNCTION;
    if (strcmp(s, "if") == 0) return KIF;
    if (strcmp(s, "else") == 0) return KELSE;
    if (strcmp(s, "while") == 0) return KWHILE;
    if (strcmp(s, "for") == 0) return KFOR;
    if (strcmp(s, "do") == 0) return KDO;
    if (strcmp(s, "break") == 0) return KBREAK;
    if (strcmp(s, "continue") == 0) return KCONTINUE;
    if (strcmp(s, "next") == 0) return KNEXT;
    if (strcmp(s, "exit") == 0) return KEXIT;
    if (strcmp(s, "return") == 0) return KRETURN;
    if (strcmp(s, "delete") == 0) return KDELETE;
    if (strcmp(s, "in") == 0) return KIN;
    if (strcmp(s, "print") == 0) return KPRINT;
    if (strcmp(s, "printf") == 0) return KPRINTF;
    if (strcmp(s, "split") == 0) return KSPLIT;
    return 0;
}

char *unq(char *y)   /* "..." with escapes -> raw string */
{
    int n = strlen(y); char *r = (char *)malloc(n + 1); int i = 1, j = 0;
    while (i < n - 1)
    {
        if (y[i] == '\\' && i + 1 < n - 1)
        {
            i++;
            if (y[i] == 'n') r[j++] = 10;
            else if (y[i] == 't') r[j++] = 9;
            else if (y[i] == 'r') r[j++] = 13;
            else if (y[i] == '\\') r[j++] = '\\';
            else if (y[i] == '"') r[j++] = '"';
            else if (y[i] == '/') r[j++] = '/';
            else { r[j++] = '\\'; r[j++] = y[i]; }
            i++;
        }
        else r[j++] = y[i++];
    }
    r[j] = 0; return r;
}

char *scan_regex()   /* read from yy_pos up to the closing unescaped '/' */
{
    char *r = (char *)malloc(512); int n = 0;
    while (yy_pos < yy_len && yy_buf[yy_pos] != '/')
    {
        if (yy_buf[yy_pos] == '\\' && yy_pos + 1 < yy_len) { r[n++] = yy_buf[yy_pos++]; r[n++] = yy_buf[yy_pos++]; }
        else r[n++] = yy_buf[yy_pos++];
    }
    if (yy_pos < yy_len) yy_pos++;   /* skip closing '/' */
    r[n] = 0; return r;
}
%}
%%
[ \t]+              { }
"\\\n"              { pline++; }
"#"[^\n]*           { }
\n                  { pline++; if (g_cont) { } else { g_val = 0; g_cont = 1; return NEWLINE; } }
"/"                 { if (g_val == 0) { yylval = (int)scan_regex(); g_val = 1; g_cont = 0; return REGEX; } if (yy_pos < yy_len && yy_buf[yy_pos] == '=') { yy_pos++; g_val = 0; g_cont = 1; return DIV_ASSIGN; } g_val = 0; g_cont = 1; return '/'; }
[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?   { yylval = (int)strdup((int)yytext); g_val = 1; g_cont = 0; return NUMBER; }
[0-9]+([eE][+-]?[0-9]+)?           { yylval = (int)strdup((int)yytext); g_val = 1; g_cont = 0; return NUMBER; }
\.[0-9]+([eE][+-]?[0-9]+)?         { yylval = (int)strdup((int)yytext); g_val = 1; g_cont = 0; return NUMBER; }
\"([^\"\\]|\\.)*\"  { yylval = (int)unq(yytext); g_val = 1; g_cont = 0; return STRING; }
[A-Za-z_][A-Za-z0-9_]*  { int k = kw(yytext); if (k) { g_val = (k == KEND) ? 0 : 0; g_cont = (k == KDO || k == KELSE) ? 1 : 0; if (k == KEND || k == KBEGIN) g_cont = 0; yylval = (int)strdup((int)yytext); return k; } yylval = (int)strdup((int)yytext); g_val = 1; g_cont = 0; return NAME; }
"+="                { g_val = 0; g_cont = 1; return ADD_ASSIGN; }
"-="                { g_val = 0; g_cont = 1; return SUB_ASSIGN; }
"*="                { g_val = 0; g_cont = 1; return MUL_ASSIGN; }
"%="                { g_val = 0; g_cont = 1; return MOD_ASSIGN; }
"^="                { g_val = 0; g_cont = 1; return POW_ASSIGN; }
"=="                { g_val = 0; g_cont = 1; return EQ; }
"!="                { g_val = 0; g_cont = 1; return NE; }
"<="                { g_val = 0; g_cont = 1; return LE; }
">="                { g_val = 0; g_cont = 1; return GE; }
">>"                { g_val = 0; g_cont = 1; return APPEND; }
"&&"                { g_val = 0; g_cont = 1; return AND; }
"||"                { g_val = 0; g_cont = 1; return OR; }
"!~"                { g_val = 0; g_cont = 1; return NOMATCH; }
"++"                { g_cont = 0; return INCR; }
"--"                { g_cont = 0; return DECR; }
"~"                 { g_val = 0; g_cont = 1; return '~'; }
[)\]]               { g_val = 1; g_cont = 0; return yytext[0]; }
[([,{]              { g_val = 0; g_cont = 1; return yytext[0]; }
[+\-*%^<>=!?:]      { g_val = 0; g_cont = 1; return yytext[0]; }
";"                 { g_val = 0; g_cont = 1; return ';'; }
"}"                 { g_val = 0; g_cont = 0; return 125; }   /* 125 == '}'; literal '}' would confuse the action brace-counter */
"$"                 { g_val = 0; g_cont = 1; return '$'; }
.                   { return yytext[0]; }
%%
