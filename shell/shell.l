%{
/* ilsh scanner: words (with quoting), operators, and reserved words.
 *
 * Reserved words (if/then/.../done/in) are only special in COMMAND POSITION —
 * at the start of a command (line start, or after ; | & && || ( then do else
 * elif while if for). Elsewhere they are ordinary WORDs, so `echo done`,
 * `grep then file`, `ls in` all work. A tiny for-header state recognizes the
 * `in` of `for x in a b c`, which is not in command position. */
int sc_cmd = 1;     /* expecting a command word -> reserved words live here */
int sc_fname = 0;   /* just saw FOR: the next word is the loop variable */
int sc_needin = 0;  /* saw the loop variable: an `in` may follow */

int sc_word(void)   /* emit current yytext as a WORD, advancing state */
{
    yylval = strdup(yytext);
    if (sc_fname) { sc_fname = 0; sc_needin = 1; }
    else sc_needin = 0;
    sc_cmd = 0;
    return WORD;
}
int sc_kw(int tok)  /* a reserved word matched: keyword here, or fall back to WORD */
{
    if (tok == IN) {
        if (sc_needin) { sc_needin = 0; sc_cmd = 0; return IN; }
        return sc_word();
    }
    if (!sc_cmd) return sc_word();
    if (tok == FOR) { sc_fname = 1; sc_cmd = 0; }
    else if (tok == IF || tok == WHILE || tok == ELIF ||
             tok == THEN || tok == ELSE || tok == DO) sc_cmd = 1;
    else sc_cmd = 0;     /* fi, done: construct end */
    return tok;
}
int sc_sep(int tok) { sc_cmd = 1; sc_fname = 0; sc_needin = 0; return tok; }  /* command separator */
%}
%%
[ \t]+          { }
"#"[^\n]*       { }
"\n"            { return sc_sep(';'); }
"&&"            { return sc_sep(AND_IF); }
"||"            { return sc_sep(OR_IF); }
">>"            { return APPEND; }
"if"            { return sc_kw(IF); }
"then"          { return sc_kw(THEN); }
"else"          { return sc_kw(ELSE); }
"elif"          { return sc_kw(ELIF); }
"fi"            { return sc_kw(FI); }
"while"         { return sc_kw(WHILE); }
"do"            { return sc_kw(DO); }
"done"          { return sc_kw(DONE); }
"for"           { return sc_kw(FOR); }
"in"            { return sc_kw(IN); }
([^ \t\n;|&<>()#\"']|\"[^\"]*\"|'[^']*'|\$\(\(([^()]|\([^()]*\))*\)\)|\$\([^)]*\)|`[^`]*`)+   { return sc_word(); }
"|"             { return sc_sep('|'); }
";"             { return sc_sep(';'); }
"&"             { return sc_sep('&'); }
"<"             { return '<'; }
">"             { return '>'; }
"("             { return sc_sep('('); }
")"             { return ')'; }
.               { return yytext[0]; }
%%
