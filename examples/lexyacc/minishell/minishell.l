%{
/* minishell scanner — words and two operators.
 *
 * A "word" is any run of characters that is not whitespace, not a separator and
 * not the start of a comment. There is no quoting and no globbing: this is the
 * teaching skeleton, not ilsh (see shell/shell.l for the real thing, including
 * the command-position trick that makes reserved words contextual).
 *
 * main() feeds the scanner exactly one line at a time, so a newline carries no
 * meaning and is simply skipped; ';' is the only separator token.
 */
%}
%%
[ \t]+          { }                                             /* skip blanks */
"#"[^\n]*       { }                                             /* comment */
\n              { }                                             /* one line per parse: newline is nothing */
"&&"            { return AND_IF; }                              /* must precede any single-'&' rule */
[^ \t\n;&#]+    { yylval = (int)strdup((int)yytext); return WORD; }
";"             { return ';'; }
.               { return yytext[0]; }                           /* unknown char: parser reports it */
%%
