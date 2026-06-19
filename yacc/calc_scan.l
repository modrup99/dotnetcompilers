%%
[ \t\n]+      { }
[0-9]+        { yylval = atoi(yytext); return NUMBER; }
"+"           { return '+'; }
"-"           { return '-'; }
"*"           { return '*'; }
"/"           { return '/'; }
"("           { return '('; }
")"           { return ')'; }
.             { return yytext[0]; }
