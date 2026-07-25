# ILForge — the manual

**ILForge** is a polyglot compiler workbench. Every language in it compiles to **pure
.NET IL** — real CLR assemblies that interoperate with C# and VB.NET — and the whole
toolchain is self-hosted: our own `lex` and `yacc` generate C, our own C compiler `cc`
lowers that C to IL, and the compilers for the other languages are written in that C and
compiled by `cc`.

```
   language source ──▶ lex + yacc ──▶ C ──▶ cc ──▶ .NET IL ──▶ .exe / .dll
                       (ours)              (ours)              (real CLR assembly)
```

## Start here

| If you want to… | Read |
|---|---|
| see every command at a glance | [COMMANDS.txt](COMMANDS.txt) |
| know what each language supports and how to use it | **[LANGUAGES.md](LANGUAGES.md)** |
| build your own language with our lex + yacc | **[lex-yacc.md](lex-yacc.md)** |
| use the Unix-style shell, its virtual filesystem and editor | [shell](../shell/shell.md) |
| work in a plain Windows console instead | *ILForge Developer Command Prompt* (Start Menu) |

## The two shells

**ILForge Shell** (`ilsh`, windowed or console) is a Unix-style shell: pipes,
redirection, `if`/`while`/`for`, coreutils (`ls cat grep sed sort wc …`), a `vi` with
syntax highlighting, `make`, and an optional **virtual filesystem** that presents
`/home /bin /etc /include /lib /tmp` over real Windows paths. See
[shell/shell.md](../shell/shell.md).

**ILForge Developer Command Prompt** is the counterpart for people who want `cmd.exe`:
it puts every compiler on `PATH`, sets `INCLUDE` and `LIB` (which `cc` honours, as in a
Visual Studio prompt), and leaves you at an ordinary prompt. Type `ilforge-help` for the
command list, or `ilsh` to drop into the Unix-style shell.

## The languages

Thirteen compilers and four interpreters. Each has a full reference with a verified
tutorial — every example in those documents was compiled and run, and the output shown is
the real output.

| Language | Kind | Reference |
|---|---|---|
| C (the `cc` compiler itself) | compiler | [lex-yacc.md](lex-yacc.md), `cc -h` |
| Pascal | compiler | [pascal](../pascal/pascal.md) |
| Modula-2 / Oberon-2 | compiler | [oberon](../oberon/oberon.md) |
| Tiny C++ | compiler | [tcpp](../cpp/tcpp.md) |
| QBasic | compiler | [qbasic](../qbasic/qbasic.md) |
| Forth | compiler | [forth](../forth/forth.md) |
| Fortran 90 | compiler | [fortran](../fortran/fortran.md) |
| COBOL | compiler | [cobol](../cobol/cobol.md) |
| Ada | compiler | [ada](../ada/ada.md) |
| Smalltalk | compiler | [smalltalk](../smalltalk/smalltalk.md) |
| Lua | compiler | [lua](../lua/lua.md) |
| AWK | compiler | [awk](../awk/awk.md) |
| Coil | compiler | [coil](../coil/coil.md) |
| Logo | interpreter | [logo](../logo/logo.md) |
| Lisp | interpreter | [lisp](../lisp/lisp.md) |
| Prolog | interpreter | [prolog](../prolog/prolog.md) |
| bc | calculator | [bc](../bc/bc.md) |

PDF editions of every reference are in [pdf/](pdf/).

## Examples

`examples/` holds runnable programs, including the two classic compiler-construction
exercises built with our own toolchain:

- `examples/lexyacc/calc/` — a calculator with variables and precedence
- `examples/lexyacc/minishell/` — a tiny shell that parses and runs commands

## Requirements

- **.NET 10 runtime** — to run ILForge and the programs it compiles.
- **.NET 10 SDK** — only needed for `cc` to stamp native `.exe` apphosts; compiling to
  `.dll` works with the runtime alone.
