#!/usr/bin/env bash
# Build ilsh from shell.l + shell.y using our lex, yacc, and cc (all -> .NET IL).
set -e
cd "$(dirname "$0")/.."
CC="dotnet src/Cc/bin/Release/net10.0/cc.dll"

dotnet yacc/yacc.dll < shell/shell.y > out/sh_parse.c   # grammar  -> LALR parser
dotnet lex/lex.dll   < shell/shell.l > out/sh_scan.c    # patterns -> scanner
cat out/sh_parse.c out/sh_scan.c shell/coreutils.c shell/make.c shell/vi.c > out/ilsh.c   # parser + scanner + builtins + make + vi
$CC out/ilsh.c -o out/ilsh.dll --exe                    # C subset -> IL
echo "built out/ilsh.dll"

# build the launch .exe and stage ilsh.dll + CRuntime.dll next to it
dotnet build src/ilshell -c Release -v q >/dev/null 2>&1 || echo "(launcher build failed)"
LDIR=src/ilshell/bin/Release/net10.0
if [ -d "$LDIR" ]; then
  cp out/ilsh.dll out/CRuntime.dll "$LDIR"/ 2>/dev/null
  echo "launch exe: $LDIR/ilshell.exe"
fi
