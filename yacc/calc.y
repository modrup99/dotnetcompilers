%{
int printf(int fmt, ...);
int result;
%}
%token NUMBER
%left '+' '-'
%left '*' '/'
%%
input : expr              { result = $1; }
      ;
expr  : expr '+' expr     { $$ = $1 + $3; }
      | expr '-' expr     { $$ = $1 - $3; }
      | expr '*' expr     { $$ = $1 * $3; }
      | expr '/' expr     { $$ = $1 / $3; }
      | '(' expr ')'      { $$ = $2; }
      | NUMBER            { $$ = $1; }
      ;
%%
int main(void) {
    yyparse();                 /* scanner reads the expression from stdin */
    printf("result = %d\n", result);
    return 0;
}
