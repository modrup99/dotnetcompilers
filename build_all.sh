#!/usr/bin/env bash
# Rebuild the whole toolchain from source: cc + CRuntime, then lex & yacc
# (compiled by cc, our C -> .NET IL), then the shell + launchers + GUI terminal.
set -e
cd "$(dirname "$0")"

echo "[1/5] building cc + CRuntime ..."
dotnet build src/Cc -c Release -v q
CC="dotnet src/Cc/bin/Release/net10.0/cc.dll"

echo "[2/5] compiling lex and yacc (our C -> IL) ..."
$CC lex/lex.c   -o lex/lex.dll   --exe
$CC yacc/yacc.c -o yacc/yacc.dll --exe

echo "[3/5] building the shell (ilsh.dll) + ilshell.exe launcher ..."
bash shell/build.sh

echo "[4/6] building the GUI terminal (ilterm.exe) ..."
dotnet build src/ilterm -c Release -v q
cp out/ilsh.dll out/CRuntime.dll src/ilterm/bin/Release/net10.0/   2>/dev/null || true
cp out/ilsh.dll out/CRuntime.dll src/ilshell/bin/Release/net10.0/ 2>/dev/null || true

echo "[5/6] compiling xeyes (our C -> IL) + building the ilgfx window ..."
$CC gfx/xeyes.c -o out/xeyes.dll --exe
dotnet build src/ilgfx -c Release -v q
cp out/xeyes.dll out/CRuntime.dll src/ilgfx/bin/Release/net10.0/ 2>/dev/null || true
# refresh the shell's CRuntime so the in-shell `xeyes`/`gfx` builtins are current
cp out/ilsh.dll out/CRuntime.dll src/ilterm/bin/Release/net10.0/   2>/dev/null || true

echo "[6/8] building the Pascal compiler (pascal.l + pascal.y -> our C -> IL) ..."
dotnet yacc/yacc.dll < pascal/pascal.y > out/pas_parse.c
dotnet lex/lex.dll   < pascal/pascal.l > out/pas_scan.c
cat out/pas_parse.c out/pas_scan.c > out/pascal_src.c
$CC out/pascal_src.c -o out/pascal.exe --exe

echo "[7/9] building the Modula-2/Oberon-2 compiler (oberon.l + oberon.y -> our C -> IL) ..."
dotnet yacc/yacc.dll < oberon/oberon.y > out/ob_parse.c
dotnet lex/lex.dll   < oberon/oberon.l > out/ob_scan.c
cat out/ob_parse.c out/ob_scan.c > out/oberon_src.c
$CC out/oberon_src.c -o out/oberon.exe --exe

echo "[8/10] building the Tiny C++ compiler (cpp.l + cpp.y -> our C -> IL) ..."
dotnet yacc/yacc.dll < cpp/cpp.y > out/cpp_parse.c
dotnet lex/lex.dll   < cpp/cpp.l > out/cpp_scan.c
cat out/cpp_parse.c out/cpp_scan.c > out/tcpp_src.c
$CC out/tcpp_src.c -o out/tcpp.exe --exe

echo "[9/11] building the QBasic compiler (qbasic.l + qbasic.y -> our C -> IL) ..."
dotnet yacc/yacc.dll < qbasic/qbasic.y > out/qb_parse.c
dotnet lex/lex.dll   < qbasic/qbasic.l > out/qb_scan.c
cat out/qb_parse.c out/qb_scan.c > out/qbasic_src.c
$CC out/qbasic_src.c -o out/qbasic.exe --exe

echo "[10/12] building the Forth compiler (forth.l + forth.y -> our C -> IL) ..."
dotnet yacc/yacc.dll < forth/forth.y > out/forth_parse.c
dotnet lex/lex.dll   < forth/forth.l > out/forth_scan.c
cat out/forth_parse.c out/forth_scan.c > out/forth_src.c
$CC out/forth_src.c -o out/forth.exe --exe

echo "[11/13] building the Logo interpreter (logo.c -> our C -> IL; no lex/yacc, arity-directed) ..."
$CC logo/logo.c -o out/logo.exe --exe

echo "[12/14] building the Lisp interpreter (lisp.c -> our C -> IL; cons/closures/metacircular) ..."
$CC lisp/lisp.c -o out/lisp.exe --exe

echo "[13/15] building the Prolog interpreter (prolog.c -> our C -> IL; unification+backtracking+cut) ..."
$CC prolog/prolog.c -o out/prolog.exe --exe

echo "[14/16] building bc, the scientific calculator (bc.l + bc.y -> our C -> IL) ..."
dotnet yacc/yacc.dll < bc/bc.y > out/bc_parse.c
dotnet lex/lex.dll   < bc/bc.l > out/bc_scan.c
cat out/bc_parse.c out/bc_scan.c > out/bc_src.c
$CC out/bc_src.c -o out/bc.exe --exe

echo "[15/16] building Coil (lex+yacc front end -> stack-IL IR; C# coilasm -> real .NET IL) ..."
dotnet build src/CoilAsm -c Release -v q
dotnet yacc/yacc.dll < coil/coil.y > out/coil_parse.c
dotnet lex/lex.dll   < coil/coil.l > out/coil_scan.c
cat out/coil_parse.c out/coil_scan.c > out/coil_src.c
$CC out/coil_src.c -o out/coilfe.exe --exe

echo "[16/17] building the Fortran 90 compiler (fortran.l + fortran.y -> our C -> IL; C#/VB interop) ..."
dotnet yacc/yacc.dll < fortran/fortran.y > out/f90_parse.c
dotnet lex/lex.dll   < fortran/fortran.l > out/f90_scan.c
cat out/f90_parse.c out/f90_scan.c > out/fortran_src.c
$CC out/fortran_src.c -o out/fortran.exe --exe

echo "[17/18] building the COBOL compiler (cobol.l + cobol.y -> our C -> IL; free-format; C#/VB interop) ..."
dotnet yacc/yacc.dll < cobol/cobol.y > out/cob_parse.c
dotnet lex/lex.dll   < cobol/cobol.l > out/cob_scan.c
cat out/cob_parse.c out/cob_scan.c > out/cobol_src.c
$CC out/cobol_src.c -o out/cobol.exe --exe

echo "[18/20] building the Ada compiler (ada.l + ada.y -> our C -> IL; C#/VB interop) ..."
dotnet yacc/yacc.dll < ada/ada.y > out/ada_parse.c
dotnet lex/lex.dll   < ada/ada.l > out/ada_scan.c
cat out/ada_parse.c out/ada_scan.c > out/ada_src.c
$CC out/ada_src.c -o out/ada.exe --exe

echo "[19/21] building the Smalltalk compiler (smalltalk.l + smalltalk.y -> our C -> IL; C#/VB interop) ..."
dotnet yacc/yacc.dll < smalltalk/smalltalk.y > out/st_parse.c
dotnet lex/lex.dll   < smalltalk/smalltalk.l > out/st_scan.c
cat out/st_parse.c out/st_scan.c > out/st_src.c
$CC out/st_src.c -o out/smalltalk.exe --exe

echo "[20/21] building the Lua compiler (lua.l + lua.y -> our C -> IL; C#/VB interop) ..."
dotnet yacc/yacc.dll < lua/lua.y > out/lua_parse.c
dotnet lex/lex.dll   < lua/lua.l > out/lua_scan.c
cat out/lua_parse.c out/lua_scan.c > out/lua_src.c
$CC out/lua_src.c -o out/lua.exe --exe

echo "[21/21] done. Tools & launchers:"
echo "   ilsh.bat    - interactive shell in a console"
echo "   ilterm.bat  - windowed VT terminal (GUI)"
echo "   xeyes.bat   - the eyes-follow-the-mouse demo (GUI)"
echo "   out/pascal.exe <file.pas>  - the Pascal compiler"
echo "   out/oberon.exe <file>      - the Modula-2 / Oberon-2 compiler"
echo "   out/tcpp.exe <file.cpp>    - the Tiny C++ compiler"
echo "   out/qbasic.exe <file.bas>  - the QBasic compiler (gfx programs: run via 'gfx <name>')"
echo "   out/forth.exe <file.fth>   - the Forth compiler (stack = .NET Stack<object>)"
echo "   out/logo.exe <f.logo> -png|-svg|-gif <out>  - the Logo turtle interpreter (or no args = REPL)"
echo "   out/lisp.exe <file.lisp>   - the Lisp interpreter (or no args = REPL)"
echo "   out/prolog.exe <file.pl>   - the Prolog interpreter (unification + backtracking + cut)"
echo "   out/bc.exe [\"EXPR\"]        - the scientific calculator (REPL if no arg; q/quit to exit)"
echo "   out/coilfe.exe <f.coil> [-o out] [--dll]  - the Coil compiler (curly-brace, ~1-to-1 with .NET IL; C#/VB interop)"
echo "   out/fortran.exe <f.f90> [-o out] [--dll]  - the Fortran 90 compiler (free-form; C#/VB interop)"
echo "   out/cobol.exe <f.cob> [-o out] [--dll]    - the COBOL compiler (free-format; PIC/PERFORM/EVALUATE; C#/VB interop)"
echo "   out/ada.exe <f.adb> [-o out] [--dll]      - the Ada subset compiler (types/enums/arrays; in/out; C#/VB interop)"
echo "   out/smalltalk.exe <f.st> [-o out] [--dll] - the Smalltalk compiler (objects/messages/classes; C#/VB interop)"
echo "   out/lua.exe <f.lua> [-o out] [--dll]      - the Lua compiler (dynamic types, tables, first-class functions; C#/VB interop)"
