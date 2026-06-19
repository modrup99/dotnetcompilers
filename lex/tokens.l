%%
[ \t\n]+    { }
[0-9]+      { return 1; }
[a-z]+      { return 2; }
.           { return 3; }
%%
int main(void) {
    int t;
    yy_scan_string("ab 12 x!");
    while ((t = yylex()) != 0) printf("tok=%d text=[%s]\n", t, yytext);
    return 0;
}
