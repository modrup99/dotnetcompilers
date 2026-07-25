# calc — a four-function calculator in lex + yacc

The classic first exercise: 8 scanner rules, 9 expression productions, and a
`%left`/`%right` block that does all the work of precedence and associativity.
Two files, no other dependencies.

- `calc.l`: patterns to tokens (`NUMBER`, `NAME`, and single characters)
- `calc.y`: grammar, evaluation actions, and `main()`

See `docs/lex-yacc.md` for the toolchain reference.

## Build

From the repo root (bash):

```bash
CC="dotnet src/Cc/bin/Release/net10.0/cc.dll"

dotnet yacc/yacc.dll -v < examples/lexyacc/calc/calc.y > out/calc_parse.c
dotnet lex/lex.dll      < examples/lexyacc/calc/calc.l > out/calc_scan.c
cat out/calc_parse.c out/calc_scan.c > out/calc_src.c
$CC out/calc_src.c -o out/calc.exe --exe
```

The parser must be concatenated **before** the scanner: `yacc` emits the
`enum { NUMBER = 257 }` token codes and the `int yylval;` that the scanner's
actions refer to.

`-v` is optional and prints the grammar statistics to stderr:

```
yacc: nsym=16 nprod=14
yacc: LALR states=23 reproc=40 gotos=143 itemscanned=1307
yacc: conflicts=0
```

Zero conflicts, from an ambiguous grammar; see *How it works* below.

## Run

`calc` is a line-at-a-time REPL on stdin. Given this input:

```
1 + 2 * 3
(1 + 2) * 3
2 - 3 - 4
x = 10
y = x * 4 + 2
y / 7
-x + 1
z
# a comment
1 / 3
```

the real session output is:

```
7
9
-5
10
42
6
-9
0
0.3333333333
```

`2 - 3 - 4` is `-5`, not `3`: `%left '+' '-'` makes subtraction left-associative.
`1 + 2 * 3` is `7` because `'*'` is declared on a later (higher) precedence line.
An undefined variable (`z`) reads as `0`.

A syntax error costs only the current line, because `main()` calls `yyparse()`
once per line:

```
$ printf '1 +\n2 + 2\n' | out/calc.exe
syntax error
4
```

## How it works

**The grammar is ambiguous on purpose.** `expr : expr '+' expr` says nothing
about how `1 + 2 * 3` groups; on its own it produces 24 shift/reduce conflicts.
The declarations

```
%right '='
%left  '+' '-'
%left  '*' '/'
%right UMINUS
```

resolve every one of them. Each line is a precedence level, and **later lines
bind tighter**. When the parser has `expr '+' expr` on the stack and sees `'*'`,
it compares the precedence of the rule (taken from its rightmost terminal, `'+'`)
against that of the lookahead (`'*'`): the lookahead wins, so it shifts and `*`
groups first. With equal precedence, `%left` reduces (left-associative) and
`%right` shifts. Deleting those three lines from `calc.y` and re-running
`yacc -v` reports `conflicts=24` with no other change.

**`%prec UMINUS`** exists because `'-' expr` would otherwise inherit the
precedence of binary `'-'`, and `-2 * 3` would parse as `-(2 * 3)`. `UMINUS` is
declared last, so it outranks `'*'`, and the unary rule binds tightest.

**Values are boxed.** Our yacc has no `%union`; `YYSTYPE` is always `int`. A
double therefore goes on the heap and `$$`/`$1` carry the address:

```c
int num(double d) { double *p = (double *)malloc(8); *p = d; return (int)p; }
double val(int h) { return *((double *)h); }
```

The `NAME` rule in `calc.l` uses the same trick for identifiers, passing a
`strdup`'d `char *` as an int.

**`yy_scan_string()`** points the generated scanner at a buffer. Without it, the
first `yylex()` reads all of stdin into one buffer, which is what you want for a
file-driven tool and not what you want for a REPL.
