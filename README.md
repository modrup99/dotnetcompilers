# dotnetcomp — compilers that emit pure .NET IL

A workbench for building compilers (for new and existing languages) that target
**pure .NET IL**, producing ordinary CLR assemblies that interoperate directly
with C#, VB.NET, and any .NET library.

The first compiler, **`tinyc`**, is a complete-but-minimal proof of the whole
pipeline: lexer → parser → AST → IL codegen → real `.dll`/`.exe`.

## Why .NET IL

- The CLR is a typed stack machine: emit opcodes, the JIT/GC/verifier do the rest.
- Any **public type** you emit is consumable from C#/VB.NET with no glue.
- You can `call` into the entire BCL + NuGet ecosystem from your language.

## How IL is emitted

`tinyc` uses **`PersistedAssemblyBuilder`** (`System.Reflection.Emit`, .NET 9+):
the familiar `ILGenerator.Emit(OpCodes.…)` API, but able to **save a real
assembly to disk** (classic `AssemblyBuilder.Save` was removed in .NET Core and
only returned, as `PersistedAssemblyBuilder`, in .NET 9).

Two non-obvious details this project already gets right:

1. **Bind against reference assemblies, not the runtime.** Types are resolved via
   `MetadataLoadContext` over the `net10.0` ref pack (`System.Runtime`,
   `System.Console`, …). Without this, emitted assemblies reference
   `System.Private.CoreLib` and *run* but cannot be *referenced* from C#.
2. **PE characteristics.** A library sets `ExecutableImage | Dll`; an executable
   sets `ExecutableImage` plus an entry-point token, and ships a
   `runtimeconfig.json`.

## Layout

```
src/TinyC/            the compiler
  Lexer.cs            source -> tokens
  Parser.cs           tokens -> AST (recursive descent, precedence climbing)
  Ast.cs              the AST node records
  Emitter.cs          AST -> IL via PersistedAssemblyBuilder
  ReferenceAssemblies.cs   locates the net10.0 ref pack
  Program.cs          CLI
examples/demo.tiny    sample program (functions, recursion, if/while)
interop/CsharpHost/   a C# app that references a Tiny-compiled .dll
out/                  build output (.dll/.exe/.il)
```

## Build & run

```powershell
# build the compiler
dotnet build src/TinyC/TinyC.csproj -c Release

$tinyc = "src/TinyC/bin/Release/net10.0/tinyc.dll"

# compile to a runnable executable (+ readable IL dump)
dotnet $tinyc examples/demo.tiny -o out/demo.dll --exe --il
dotnet out/demo.dll                       # -> 7 / 55 / 120

# compile to a library and call it from C#
dotnet $tinyc examples/demo.tiny -o out/demo.dll --dll
dotnet run --project interop/CsharpHost/CsharpHost.csproj -c Release
```

## The Tiny language (current surface)

```
func add(a, b) { return a + b; }
func main() {
    let x = 1;                 // declare
    x = x + 41;                // assign
    if (x > 10) { print x; }   // print -> Console.WriteLine(int)
    while (x > 0) { x = x - 1; }
    return 0;
}
```

- Types: 32-bit `int` only (smallest surface that still proves real codegen).
- `func` → `public static int` on a public `TinyProgram` type.
- Operators: `+ - * / %`, comparisons `== != < <= > >=`, unary `-`.
- `// line comments`.

## `cc` — a C-subset → IL compiler (toward C with lex/yacc)

A second, larger compiler aimed at compiling C (C89-ish) to IL, with the eventual
goal of self-hosting clean-room **lex** and **yacc**. Pointers will use a **fat-
pointer** model (array reference + integer offset) so pointer arithmetic, `p[i]`,
`p - q`, and `yyvsp[-1]`-style access all work while staying memory-safe — this is
what lets lex/yacc compile unchanged.

**Stage 1 (done):** scalar `int`/`char` + `void`, functions, recursion, globals,
full operator set, `if`/`while`/`do`/`for`, `break`/`continue`, prototypes. Each C
function → `public static` on a public `CProgram` type (so it's callable from C#).
Temporary intrinsics `putint`/`putchar`/`getchar` stand in until the libc subset.

```powershell
dotnet build src/Cc/Cc.csproj -c Release
$cc = "src/Cc/bin/Release/net10.0/cc.dll"
dotnet $cc examples/demo.c -o out/cdemo.dll --exe   # run: dotnet out/cdemo.dll
dotnet $cc examples/demo.c -o out/cdemo.dll --dll   # C# refs it: interop/CHost
```

Two gotchas already handled (beyond tinyc's): a prototype must NOT emit a bodyless
method (malformed), and the emitted **assembly name must match the output file
name** or the host can resolve a same-named sibling assembly instead.

**Stage 2 (done):** the **flat-arena memory model** — a C pointer is an `int`
address into one `byte[]` arena ([CRuntime](src/CRuntime/CRuntime.cs)), so pointer
arithmetic is integer arithmetic scaled by `sizeof`, and casts/unions are faithful
(it's all bytes). Working: `char*`/string literals, local + global arrays, `[]`,
`&`/`*`, pointer arithmetic & comparison, `(type)` casts, `sizeof`. Every local and
parameter lives in a per-call stack frame so `&x` always works; globals live in the
data segment. A type-propagating emitter chooses load/store widths and scales
pointer math. See [strings.c](examples/strings.c).

**libc (in `CRuntime`, bound by name):** `<string.h>` (strlen/strcpy/strncpy/strcat/
strcmp/strncmp/strchr/strrchr/strstr/strdup/memcpy/memmove/memset/memcmp), `<ctype.h>`
(is*/to*), `<stdlib.h>` (malloc/free/calloc/realloc/atoi/abs/exit/rand/srand),
`<stdio.h>` (printf/fprintf/sprintf/snprintf via varargs, puts/putchar/getchar,
fopen/fgetc/fgets/fputs/fread/fwrite/fclose/feof). `fork()` is **not** supported and
can't be — a managed runtime can't snapshot/resume a call stack or copy the address
space; lex/yacc don't need it.

**Stage 2b (done):** `struct`/`union` (byte offsets in the arena — unions are
*faithful*, no compromise), member access `.`/`->`, struct copy/assignment,
`typedef` (parser tracks typedef names — C's context-sensitive grammar), `enum`
(constant-folded), `switch`/`case`/`default`, and **function pointers** — variables,
params, arrays, and indirect calls, lowered to int ids dispatched through generated
`__call_<n>_<ret>` switch methods. See [structs.c](examples/structs.c) (incl. a
comparator-driven sort). Function-pointer declarators `R (*fp)(params)` parse.

**Stage 2c (done) — gap-fillers:** aggregate initializers (arrays incl. inferred
length & multi-dim, structs, nested, partial→zero, `char[]="..."`), `goto`/labels,
adjacent string-literal concatenation, **floating point** (`double`/`float`, mixed
arithmetic with conversions, `math.h`), `printf` `%f`/`%e`/`%g`, `scanf`/`sscanf`,
and **struct by value** (params copied into the callee frame; returns via an sret
hidden pointer). See [features.c](examples/features.c).

**Remaining minor gaps:** designated initializers (`.field=`), bit-fields,
`long`/`unsigned` as distinct types (all map to int), function-pointer-returning
structs via indirect call. None block lex/yacc.

**Roadmap:** ✅ 2/2b/2c done → ✅ 3 lex → ✅ 4 LALR(1) yacc. The full lex+yacc
toolchain works, both written in our C and emitting C.

**Hardening (real-world C):** added a **C preprocessor** ([Preprocessor.cs](src/Cc/Preprocessor.cs))
— object- & function-like `#define`, `#include "..."`/`<...>`, `#ifdef`/`#ifndef`/
`#if`/`#elif`/`#else`/`#endif` with `defined()` and constant-expression evaluation,
line continuations, comment stripping (no `#`/`##`). Plus: comma operator, octal/hex
char escapes (`'\101'`, `'\x42'`), octal integer literals (`0755`), persistent
`static` locals, and real **`unsigned`** semantics (logical `>>`, unsigned `/` `%`
and comparisons). And a second round closed the remaining gaps: **64-bit `long`/`unsigned long`**
(a third numeric class — int32 / int64 / float64 — with full promotion,
conversions, `%ld`/`%lu`, 64-bit literals), **designated initializers**
(`{.x=1}`, `{[5]=9}`), macro **`#` stringize / `##` paste**, and a **broader libc**
(`strtol`/`strtoul`/`strtod`, `memchr`/`strpbrk`/`strspn`/`strcspn`, `labs`/`atoll`,
`fseek`/`ftell`/`rewind`/`fflush`).

Regression suite in [tests/](tests/) (17 edge-case programs);
exercised against linked lists, recursive quicksort, bit-twiddling, 64-bit
arithmetic, and function-pointer dispatch tables.

## `lex` — a clean-room lexer generator ([lex/lex.c](lex/lex.c))

Written **in the C subset compiled by `cc`** (so `lex` itself runs as IL), it reads
a `.l` spec from stdin and **emits a C scanner** to stdout:

```bash
dotnet src/Cc/bin/Release/net10.0/cc.dll lex/lex.c -o lex/lex.dll --exe   # build lex
dotnet lex/lex.dll < lex/calc.l > out/scanner.c                          # generate scanner
dotnet src/Cc/bin/Release/net10.0/cc.dll out/scanner.c -o out/scanner.dll --exe
dotnet out/scanner.dll
```

- **Regex:** literals, `.`, `[...]` (ranges, `^` negation), `* + ?`, `|`, `(...)`,
  `"strings"`, escapes, and `{NAME}` definition expansion.
- **Approach:** each rule compiles to a Thompson regex-VM program
  (`CHAR/ANY/CLASS/SPLIT/JMP/MATCH`); the emitted `yylex()` simulates all rules in
  parallel for **leftmost-longest match**, first rule winning ties.
- **Runtime API in generated scanner:** `yylex()`, `yytext`, `yyleng`,
  `yy_scan_string(s)` (or reads stdin). Actions are arbitrary C; `return`s a token.
- Sections: `%{ %}` verbatim code, `NAME pattern` defs, `%%`, rules, `%%`, user code.

Found & fixed a real `cc` bug en route: escaped char constants (`'\n'`) were
mis-lexed (only string escapes had been exercised before).

## `yacc` — a clean-room LALR(1) parser generator ([yacc/yacc.c](yacc/yacc.c))

Also written **in our C** (runs as IL), reads a `.y` grammar from stdin and
**emits a C parser** to stdout.

```bash
dotnet yacc/yacc.dll < yacc/calc.y > out/parse.c   # LALR(1) tables + LR driver
dotnet lex/lex.dll   < yacc/calc_scan.l > out/scan.c
cat out/parse.c out/scan.c > out/calc.c            # parser defines tokens/yylval; scanner provides yylex
dotnet cc.dll out/calc.c -o out/calc.dll --exe
echo "2 + 3 * 4 - 10 / 2" | dotnet out/calc.dll      # => result = 9
```

- **Algorithm:** builds the canonical **LR(1)** item-set collection, then merges
  states with identical LR(0) cores → true **LALR(1)**.
- **Conflict resolution:** `%left`/`%right`/`%nonassoc` precedence for shift/reduce,
  earliest-rule for reduce/reduce (conflicts counted/reported).
- **Grammar:** `%token`, precedence decls, `%start`, `%{ %}`, rules with `|`,
  actions with `$$`/`$n` (YYSTYPE = int), `%prec`.
- **Emitted parser:** ACTION/GOTO tables + a table-driven LR engine (`yyparse`)
  driving `yylex()`; emits an `enum` of token codes so a lex scanner links against
  it. Integrates with the `lex` scanner above.

The [calc](yacc/calc.y) example respects precedence, associativity, and
parentheses: `(2+3)*4 → 20`, `100-10-5 → 85`, `2*(3+4)*5 → 70`.

## `ilsh` — a bash/ksh-style shell ([shell/](shell/))

The classic lex+yacc showcase: a small shell. [shell.l](shell/shell.l) scans
words/quotes/operators, [shell.y](shell/shell.y) is an LALR grammar that builds a
command **AST**, and a tree-walking executor (in the grammar's user code) runs it
— all compiled by `cc` to IL.

```bash
bash shell/build.sh                       # yacc+lex+cc -> out/ilsh.dll
dotnet out/ilsh.dll < shell/demo.sh
```

Supports: simple commands & arguments, **variables** (`X=42`, `$X`, `${X}`, `$?`),
single/double **quoting**, **pipelines** `a | b | c`, **redirection** `>` `>>` `<`,
sequencing `;`, `&&`/`||`, and control flow — `if`/`elif`/`else`/`fi`,
`while`/`do`/`done`, `for x in … do … done`. Builtins: `cd`, `pwd`, `echo`,
`export`, `set`, `exit`, `true`, `false`, `test`/`[ ]`. External commands run as
real processes (CRuntime adds `sh_run`/redirection via `System.Diagnostics.Process`),
so pipelines mix builtins and external tools: `echo … | sort | findstr a`.

**Interactive + coreutils.** `dotnet out/ilsh.dll` with no redirected input starts a
REPL (prompt shows the cwd, handles multi-line `if`/`while`/`for`); piping a script
runs it in batch. **`alias`** is supported (`alias ll='ls -l'`, `alias vi='notepad++'`
→ `vi file` launches your editor). A set of **coreutils are built in**
([shell/coreutils.c](shell/coreutils.c), compiled into ilsh) so they're instant and
pipe in-process: `ls` (incl. `-l`/`-a`), `cat`, `grep` (`-i`/`-v`/`-n`), `sort`,
`wc`, `head`/`tail` (`-N`), `cut` (`-d`/`-f`), `paste`, `find` (`-name` glob),
`more`, `cp`, `mv`, `rm`, `mkdir`, `touch`, `ln` (`-s`). The filesystem/console
primitives they use (`rt_lsopen`, `rt_find`, stat, copy/move/link, raw key input)
live in CRuntime.

More shell features: `help`, `-h`/`--help` on every builtin, `&` background launch,
`alias`/`unalias`, `source`/`.`, **shell-local variables** (not the Windows env) with
bootstrapped `HOME`/`PATH` and `~/.bashrc` at startup, **PATH-based command
resolution**, `push`/`pop` (directory stack), and a raw **line editor with history**
(Up/Down recall, `!!`/`!n`/`!prefix`).

**`make`** ([shell/make.c](shell/make.c), built into ilsh): parses a Makefile
(`NAME = / := / +=`, rules `target: prereqs` + tab recipes, comments, `\`
continuation), builds the goal by walking prerequisites and comparing timestamps
(`rt_mtime`), and runs recipe lines **through the shell itself** (so pipes,
redirects, and aliases work). Supports `$(VAR)`/`${VAR}`, automatic vars `$@ $< $^`,
`@`/`-` recipe prefixes, `-f`, and `VAR=val` overrides. See
[shell/Makefile.demo](shell/Makefile.demo). *(Next: a minimal modal `vi` — raw-console
support is already in place.)*

## `ilterm` — a windowed terminal (Avalonia display host)

A resizable GUI terminal that hosts the shell, X-windows style. Architecture: the
Avalonia host loads the compiled `ilsh` as an assembly and wires **CRuntime's
console I/O to a VT grid** (`TermGrid` in CRuntime) — no PTY/sockets, since our
assemblies are normal .NET. The terminal *brains* are testable headless:

- **`TermGrid`** (in CRuntime) — an 80×24 (resizable) character grid with cursor,
  colours, scroll, and a VT102-ish parser (CR/LF/BS/TAB, CSI cursor moves,
  erase-line/display, SGR colours).
- **Raw line editor + history** (shell-side): Up/Down recall, Left/Right/Home/End
  editing, and `!!`/`!n`/`!prefix` history expansion — works in the window *and*
  at any ANSI console.
- **[src/TermTest](src/TermTest)** drives the real shell against a `TermGrid` with a
  scripted key stream and dumps the grid — so history recall, `$VAR` expansion, and
  builtins are verified without a display.

```bash
bash shell/build.sh                              # -> out/ilsh.dll
dotnet run --project src/ilterm -- out/ilsh.dll  # opens the terminal window
```

> Note: the headless terminal core is tested; the Avalonia window itself
> ([src/ilterm](src/ilterm)) compiles but hasn't been run in this environment —
> it needs a desktop to verify. `xeyes` (a graphics client) is the next step.

## Languages built on the toolchain

Beyond `cc`/`lex`/`yacc` themselves, the workbench hosts a family of languages, each
running as pure .NET IL. **Compilers** use the `lex + yacc → C → cc` pipeline, so every
`SUBROUTINE`/`FUNCTION`/paragraph becomes a `public static` method on `CProgram` —
directly callable from C#/VB.NET. **Interpreters** are written directly in the C subset
that `cc` compiles. Each language has a reference following the Language Museum tutorial
framework (every example verified against the real tool); rendered PDFs live in
[docs/pdf/](docs/pdf/).

| Language | Kind | Highlights | Reference |
|---|---|---|---|
| Pascal (TP4/TP7) | compiler (lex+yacc) | Turbo Pascal 4/7, OOP (object/virtual/VMT) | — |
| Modula-2 / Oberon-2 | compiler (lex+yacc) | modules, shared front end | — |
| Tiny C++ | compiler (lex+yacc) | classes, virtual, inheritance, ctors, `new`/`delete` | [md](cpp/tcpp.md) · [pdf](docs/pdf/TinyCpp.pdf) |
| QBasic | compiler (lex+yacc) | typed vars/arrays, `SUB`/`FUNCTION` by-ref, gfx, `#line` PDB | [md](qbasic/qbasic.md) · [pdf](docs/pdf/QBasic.pdf) |
| Forth | compiler (lex+yacc) | words → methods, stack = .NET `Stack<object>` | [md](forth/forth.md) · [pdf](docs/pdf/Forth.pdf) |
| Fortran 90 | compiler (lex+yacc) | free-form, by-ref subroutines, arrays, intrinsics, C# interop | [md](fortran/fortran.md) · [pdf](docs/pdf/Fortran90.pdf) |
| COBOL | compiler (lex+yacc) | 4 divisions, `PIC`/edited fields, `OCCURS`/88-levels, `PERFORM`/`EVALUATE` | [md](cobol/cobol.md) · [pdf](docs/pdf/COBOL.pdf) |
| Ada | compiler (lex+yacc) | strong typing, enums, arrays, `in`/`out` params, `'Image`, C# interop | [md](ada/ada.md) · [pdf](docs/pdf/Ada.pdf) |
| Smalltalk | compiler (lex+yacc) | everything-is-an-object, message dispatch, classes/methods, C# interop | [md](smalltalk/smalltalk.md) · [pdf](docs/pdf/Smalltalk.pdf) |
| Coil | compiler (lex+yacc → IR → C# `Reflection.Emit`) | curly-brace, ~1:1 with IL | [md](coil/coil.md) · [pdf](docs/pdf/Coil.pdf) |
| Logo | interpreter (in cc-C) | turtle graphics → PNG/SVG/animated GIF + REPL | [md](logo/logo.md) · [pdf](docs/pdf/Logo.pdf) |
| Lisp | interpreter (in cc-C) | closures, metacircular eval, a Lisp-compiler-in-Lisp | [md](lisp/lisp.md) · [pdf](docs/pdf/Lisp.pdf) |
| Prolog | interpreter (in cc-C) | unification + binding trail + SLD backtracking + cut | [md](prolog/prolog.md) · [pdf](docs/pdf/Prolog.pdf) |
| bc | calculator (lex+yacc) | full precedence, scientific functions, REPL | [md](bc/bc.md) · [pdf](docs/pdf/bc.pdf) |

```bash
bash build_all.sh          # build the whole toolchain + every language
py docs/make_pdfs.py       # regenerate the reference PDFs in docs/pdf/
```

C#/VB.NET interop for the compiled languages is demonstrated under [interop/](interop/)
(e.g. [FortranHost](interop/FortranHost), [CobolHost](interop/CobolHost),
[CoilHost](interop/CoilHost)).

## Natural next steps

- More types: `string`, `bool`, `double`; overload `print` against the BCL.
- Let Tiny **reference external .NET assemblies** and emit calls into them.
- Locals/params symbol-table → a small semantic-analysis pass with type checking.
- A second front end (e.g. retarget a Nova/Pascal grammar) onto the same emitter.
- Optional textual-IL backend via `ilasm` (NuGet `Microsoft.NET.ILAsm`) for those
  who prefer to assemble from `.il` text.
- Emit a PDB for source-level debugging in VS / VS Code.
