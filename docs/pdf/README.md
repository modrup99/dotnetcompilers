# Language reference PDFs

Rendered references for each language hosted on the toolchain, following the Language
Museum tutorial framework (reference sections + a 9-activity tutorial, every example
verified against the real compiler/interpreter).

| PDF | Language | Source |
|---|---|---|
| [QBasic.pdf](QBasic.pdf) | QBasic | [qbasic/qbasic.md](../../qbasic/qbasic.md) |
| [TinyCpp.pdf](TinyCpp.pdf) | Tiny C++ | [cpp/tcpp.md](../../cpp/tcpp.md) |
| [Forth.pdf](Forth.pdf) | Forth | [forth/forth.md](../../forth/forth.md) |
| [Fortran90.pdf](Fortran90.pdf) | Fortran 90 | [fortran/fortran.md](../../fortran/fortran.md) |
| [COBOL.pdf](COBOL.pdf) | COBOL | [cobol/cobol.md](../../cobol/cobol.md) |
| [Coil.pdf](Coil.pdf) | Coil | [coil/coil.md](../../coil/coil.md) |
| [Logo.pdf](Logo.pdf) | Logo | [logo/logo.md](../../logo/logo.md) |
| [Lisp.pdf](Lisp.pdf) | Lisp | [lisp/lisp.md](../../lisp/lisp.md) |
| [Prolog.pdf](Prolog.pdf) | Prolog | [prolog/prolog.md](../../prolog/prolog.md) |
| [bc.pdf](bc.pdf) | bc | [bc/bc.md](../../bc/bc.md) |

## Regenerating

```
py docs/make_pdfs.py
```

The script ([docs/make_pdfs.py](../make_pdfs.py)) converts each Markdown reference to
styled HTML (via `python-markdown`) and prints it to PDF with headless Chrome/Edge.
