# minishell — a shell in ten productions

Read a line, parse it into a command tree, walk the tree and run it. `;` sequences
commands, `&&` runs the right-hand side only if the left-hand side exited 0, and
anything else on the line is a program plus its arguments.

- `minishell.l`: words and the two operators
- `minishell.y`: grammar, the `Node` tree, the tree-walker, and `main()`

This is the teaching skeleton of `shell/shell.y` (ilsh), which adds quoting,
pipes, redirection, `if`/`while`/`for`, variables, aliases, ~60 builtins and a
virtual filesystem. The execution primitive is identical: `sh_run(argv, argc)`.

See `docs/lex-yacc.md` for the toolchain reference.

## Build

From the repo root (bash):

```bash
CC="dotnet src/Cc/bin/Release/net10.0/cc.dll"

dotnet yacc/yacc.dll -v < examples/lexyacc/minishell/minishell.y > out/ms_parse.c
dotnet lex/lex.dll      < examples/lexyacc/minishell/minishell.l > out/ms_scan.c
cat out/ms_parse.c out/ms_scan.c > out/minishell_src.c
$CC out/minishell_src.c -o out/minishell.exe --exe
```

Parser first, then scanner: the scanner's actions use `AND_IF` and `WORD`, which
`yacc` emits as enum constants, and `yylval`, which `yacc` declares.

```
yacc: nsym=10 nprod=11
yacc: LALR states=12 reproc=12 gotos=17 itemscanned=98
yacc: conflicts=0
```

## Run

`minishell` reads commands from stdin, one line at a time. Given this input:

```
cmd /c echo hello from minishell
cmd /c echo first ; cmd /c echo second
cmd /c exit 0 && cmd /c echo left succeeded
cmd /c exit 1 && cmd /c echo never printed
# a comment line
nosuchprog
exit
```

the real session output is:

```
hello from minishell
first
second
left succeeded
nosuchprog: command not found
```

`cmd /c echo never printed` never runs: `cmd /c exit 1` returned 1, so `&&`
short-circuits. `nosuchprog: command not found` comes from the runtime's
`sh_run`, which returns 127 when `Process.Start` fails.

## How it works

**Grammar.** Three layers, each one left-recursive, which is what an LR parser
prefers (left recursion keeps the stack shallow; a recursive-descent parser would
need the opposite):

```
list    : andlist | list ';' andlist | list ';' ;
andlist : cmd     | andlist AND_IF cmd ;
cmd     : words ;
words   : WORD    | words WORD ;
```

Layering rather than precedence declarations is what makes `a && b ; c && d`
group correctly with zero conflicts: `;` can only appear in `list`, `&&` only in
`andlist`, so there is nothing to be ambiguous about.

**The tree.** Actions build nodes and return their addresses as ints (`YYSTYPE`
is `int`), so `$$ = mknode(NSEQ, $1, $3)` is a pointer masquerading as an
integer. Words accumulate into a `struct Words` holding up to 64 `char *`, again
stored as ints.

**Execution.** `exec()` returns an exit status, and that return value is the
entire implementation of `&&`:

```c
if (n->kind == NAND) { int s = exec(n->a); if (s != 0) return s; return exec(n->b); }
```

`run_cmd()` copies the word list into a flat `int` array and calls
`sh_run(argv, argc)` from `CRuntime`, which does `Process.Start` +
`WaitForExit` and hands back the child's exit code. Builtins are checked before
that point, because a builtin is precisely a command that has to change the
shell's own state and therefore cannot be a child process; here only `exit`.

**Newlines.** `main()` feeds one line per `yyparse()` call, so `\n` is discarded
by the scanner and `;` is the only separator token. ilsh does it the other way
round (`"\n" { return sc_sep(';'); }`) because it parses whole scripts.

## Not included

Deliberately: quoting, globbing, pipes, redirection, background jobs, `cd`,
variables, control flow, and PATH resolution (so `echo` must be spelled
`cmd /c echo` on Windows, since there is no `echo.exe`). All of them are in
`shell/shell.y` and `shell/shell.l`.
