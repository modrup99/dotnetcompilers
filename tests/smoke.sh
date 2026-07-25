#!/usr/bin/env bash
# smoke.sh - compile and run one small program in every ILForge language and check the
# output. This is the regression net for changes to cc, lex, yacc or the runtime: those
# are shared by every front end, so a change there can break a language far away.
#
#   bash tests/smoke.sh            (expects the toolchain already built: bash build_all.sh)
#
# To check an *installed* copy instead of this working tree -- which catches packaging gaps
# a repo-only run cannot see, such as a helper the installer forgot to stage:
#
#   ILFORGE_ROOT="C:\Program Files\ILForge" bash tests/smoke.sh
#
# Exit code 0 = all languages pass.

cd "$(dirname "$0")/.."
ROOT="${ILFORGE_ROOT:-$(pwd)}"
CC="dotnet $ROOT/src/Cc/bin/Release/net10.0/cc.dll"
W="$(mktemp -d)"
pass=0; fail=0; failed=""

# run <name> <expected-substring> <compile-and-run command...>
check() {
    local name="$1" want="$2"; shift 2
    local got
    got="$("$@" 2>&1)"
    if [[ "$got" == *"$want"* ]]; then
        pass=$((pass+1)); printf '  ok    %-11s %s\n' "$name" "$(echo "$got" | head -1)"
    else
        fail=$((fail+1)); failed="$failed $name"
        printf '  FAIL  %-11s want %q\n' "$name" "$want"
        echo "$got" | head -4 | sed 's/^/          /'
    fi
}

# compile <tool-args...> then run the produced exe, echoing its output
build_run() {
    local exe="$1"; shift
    local out
    # NB: the message must not contain the tool's path, or it can accidentally satisfy the
    # expected-substring test (a compile failure would then read as a pass).
    out="$("$@" 2>&1)" || { echo "[compile-failed] ${out//$ROOT/}"; return 1; }
    [[ -f "$exe" ]] || { echo "[no-exe] ${out//$ROOT/}"; return 1; }
    "$exe"
}

echo "ILForge smoke test"

# ---- C (cc itself) ----
cat > "$W/t.c" <<'EOF'
int printf(int, ...);
int main(void) { int i, s = 0; for (i = 1; i <= 10; i++) s += i; printf((int)"c=%d\n", s); return 0; }
EOF
check c "c=55" build_run "$W/t.exe" dotnet "$ROOT/src/Cc/bin/Release/net10.0/cc.dll" "$W/t.c" -o "$W/t.exe" --exe

# unary operators and printf formatting. Each of these was wrong once: a unary result was
# always typed int (so a negated double was boxed as an int in varargs), `!` on a double
# emitted invalid IL, and the 0 flag was ignored for floating conversions.
cat > "$W/u.c" <<'EOF'
int printf(int, ...);
int main(void)
{
    long L = 5000000000;
    printf((int)"u=%f %f [%08.3f] %ld %d %d %d\n", -3.1, -(1.5 + 1.6), -3.1, -L, !0.0, !3.1, ~5);
    return 0;
}
EOF
check c-unary "u=-3.100000 -3.100000 [-003.100] -5000000000 1 0 -6" \
      build_run "$W/u.exe" dotnet "$ROOT/src/Cc/bin/Release/net10.0/cc.dll" "$W/u.c" -o "$W/u.exe" --exe

# ---- Pascal ----
cat > "$W/t.pas" <<'EOF'
program T; var i, s: integer;
begin s := 0; for i := 1 to 10 do s := s + i; writeln('pas=', s, ' ', 17 mod 5, ' ', round(3.7)); end.
EOF
check pascal "pas=55 2 4" build_run "$W/t.exe" "$ROOT/out/pascal.exe" "$W/t.pas" -o "$W/t.exe"

# ---- Pascal objects + virtual dispatch (exercises cc's function-pointer dispatcher,
#      which a same-arity double-taking helper in the prelude once made emit invalid IL) ----
cat > "$W/o.pas" <<'EOF'
program O;
type
  TShape = object
    function Area: integer; virtual;
  end;
  TSq = object(TShape)
    s: integer;
    constructor Init(n: integer);
    function Area: integer; virtual;
  end;
function TShape.Area: integer;
begin Area := 0 end;
constructor TSq.Init(n: integer);
begin s := n end;
function TSq.Area: integer;
begin Area := s * s end;
var q: TSq; p: ^TShape;
begin
  q.Init(7);
  p := @q;
  writeln('virt=', p^.Area, ' ', round(3.7))
end.
EOF
check pas-oop "virt=49 4" build_run "$W/o.exe" "$ROOT/out/pascal.exe" "$W/o.pas" -o "$W/o.exe"

# ---- Modula-2 / Oberon-2 ----
cat > "$W/t.mod" <<'EOF'
MODULE T; VAR i, s: INTEGER;
BEGIN s := 0; FOR i := 1 TO 10 DO s := s + i END;
  Out.String("ob="); Out.Int(s, 0); Out.String(" "); Out.Int(17 MOD 5, 0); Out.Ln;
  FOR i := 3 TO 1 BY -1 DO Out.Int(i, 0) END; Out.Ln;
END T.
EOF
check oberon "ob=55 2" build_run "$W/t.exe" "$ROOT/out/oberon.exe" "$W/t.mod" -o "$W/t.exe"

# ---- Tiny C++ ----
# NB: printf is built in (do not declare it -- `...` is not valid here), and an override
# must repeat `virtual` to be dispatched dynamically.
cat > "$W/t.cpp" <<'EOF'
class Shape {
  public:
    virtual int area() { return 0; }
};
class Sq : public Shape {
  public:
    virtual int area() { return 49; }
};
int main() { Shape* p = new Sq(); printf("cpp=%d\n", p->area()); return 0; }
EOF
check tcpp "cpp=49" build_run "$W/t.exe" "$ROOT/out/tcpp.exe" "$W/t.cpp" -o "$W/t.exe"

# ---- QBasic ----
cat > "$W/t.bas" <<'EOF'
s% = 0
FOR i% = 1 TO 10
  s% = s% + i%
NEXT i%
PRINT "bas="; s%
EOF
check qbasic "bas=" build_run "$W/t.exe" "$ROOT/out/qbasic.exe" "$W/t.bas" -o "$W/t.exe"

# ---- Forth ----
cat > "$W/t.fth" <<'EOF'
: sq dup * ;
7 sq . cr
EOF
check forth "49" build_run "$W/t.exe" "$ROOT/out/forth.exe" "$W/t.fth" -o "$W/t.exe"

# ---- Fortran 90 ----
cat > "$W/t.f90" <<'EOF'
program t
  integer :: i, s
  s = 0
  do i = 1, 10
    s = s + i
  end do
  print *, 'f90=', s
end program t
EOF
check fortran "55" build_run "$W/t.exe" "$ROOT/out/fortran.exe" "$W/t.f90" -o "$W/t.exe"

# ---- COBOL ----
cat > "$W/t.cob" <<'EOF'
IDENTIFICATION DIVISION.
PROGRAM-ID. T.
DATA DIVISION.
WORKING-STORAGE SECTION.
01 I PIC 9(4) VALUE 0.
01 S PIC 9(4) VALUE 0.
PROCEDURE DIVISION.
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > 10
        ADD I TO S
    END-PERFORM
    DISPLAY "cob=" S
    STOP RUN.
EOF
check cobol "cob=" build_run "$W/t.exe" "$ROOT/out/cobol.exe" "$W/t.cob" -o "$W/t.exe"

# ---- Ada ----
cat > "$W/t.adb" <<'EOF'
with Ada.Text_IO; use Ada.Text_IO;
procedure Main is
   function Sq (N : Integer) return Integer is begin return N * N; end Sq;
   S : Integer := 0;
begin
   for I in 1 .. 10 loop S := S + I; end loop;
   Put_Line ("ada=" & Integer'Image (S) & Integer'Image (Sq (7)));
end Main;
EOF
check ada "ada= 55 49" build_run "$W/t.exe" "$ROOT/out/ada.exe" "$W/t.adb" -o "$W/t.exe"

# ---- Smalltalk ----
cat > "$W/t.st" <<'EOF'
| s |
s := 0.
1 to: 10 do: [:i | s := s + i].
('st=' , s printString) printNl.
EOF
check smalltalk "st=55" build_run "$W/t.exe" "$ROOT/out/smalltalk.exe" "$W/t.st" -o "$W/t.exe"

# ---- Lua ----
cat > "$W/t.lua" <<'EOF'
local s = 0
for i = 1, 10 do s = s + i end
local t = {10, 20, 30}
print("lua=" .. s .. " " .. #t)
EOF
check lua "lua=55 3" build_run "$W/t.exe" "$ROOT/out/lua.exe" "$W/t.lua" -o "$W/t.exe"

# ---- AWK (reads stdin) ----
cat > "$W/t.awk" <<'EOF'
{ s += $1 }
END { print "awk=" s }
EOF
if out=$("$ROOT/out/awk.exe" "$W/t.awk" -o "$W/ta.exe" 2>&1) && [[ -f "$W/ta.exe" ]]; then
    got=$(printf '10\n20\n25\n' | "$W/ta.exe" 2>&1)
    if [[ "$got" == *"awk=55"* ]]; then pass=$((pass+1)); printf '  ok    %-11s %s\n' awk "$got"
    else fail=$((fail+1)); failed="$failed awk"; printf '  FAIL  %-11s got %q\n' awk "$got"; fi
else fail=$((fail+1)); failed="$failed awk"; echo "  FAIL  awk         compile: $out"; fi

# ---- Coil ----
# coilfe emits .dll + .runtimeconfig.json + a stamped native .exe, as cc does, so the
# produced exe must run directly (it once was a managed PE needing `dotnet <exe>`).
cat > "$W/t.coil" <<'EOF'
func sq(int n) -> int { return n * n; }
func main() -> void { println(sq(7)); }
EOF
check coil "49" build_run "$W/tc.exe" "$ROOT/out/coilfe.exe" "$W/t.coil" -o "$W/tc.exe"

# ---- interpreters ----
cat > "$W/t.logo" <<'EOF'
TO SQ :N
  OUTPUT :N * :N
END
PRINT SQ 7
EOF
check logo "49" "$ROOT/out/logo.exe" "$W/t.logo"

cat > "$W/t.lisp" <<'EOF'
(define (sq n) (* n n))
(print (sq 7))
EOF
check lisp "49" "$ROOT/out/lisp.exe" "$W/t.lisp"

cat > "$W/t.pl" <<'EOF'
parent(tom, bob).
parent(bob, ann).
grand(X, Z) :- parent(X, Y), parent(Y, Z).
?- grand(tom, W).
EOF
check prolog "ann" "$ROOT/out/prolog.exe" "$W/t.pl"

check bc "42" "$ROOT/out/bc.exe" "6*7"

# ---- the shell ----
got=$(printf 'echo sh=$((6*7))\nbc "1+1"\n' | "$ROOT/out/ilsh.exe" 2>&1)
if [[ "$got" == *"sh=42"* ]]; then pass=$((pass+1)); printf '  ok    %-11s %s\n' ilsh "$(echo "$got" | head -1)"
else fail=$((fail+1)); failed="$failed ilsh"; printf '  FAIL  %-11s got %q\n' ilsh "$got"; fi

rm -rf "$W"
echo
echo "passed $pass, failed $fail"
[[ -n "$failed" ]] && echo "failed:$failed"
[[ $fail -eq 0 ]]
