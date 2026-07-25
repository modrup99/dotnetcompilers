@echo off
REM ===================================================================
REM  ILForge Developer Command Prompt
REM
REM  Puts the whole toolchain on PATH in an ordinary Windows console --
REM  the counterpart to the ilsh Unix-style shell. Every compiler is then
REM  a bare command:  cc, lex, yacc, pascal, lua, cobol, awk, ...
REM
REM  Launch it from the Start Menu, double-click it, or from a console:
REM      call ilforge-cmd.bat [homedir]   (configures the current console)
REM  A shortcut should run:
REM      cmd.exe /k "<install>\ilforge-cmd.bat" "<homedir>"
REM ===================================================================

set "ILFORGE_ROOT=%~dp0"
if "%ILFORGE_ROOT:~-1%"=="\" set "ILFORGE_ROOT=%ILFORGE_ROOT:~0,-1%"

REM --- home directory: first argument wins, then a pre-set ILFORGE_HOME, then the default.
REM     The installer passes the home it configured, so this matches the shell's /home. ---
if not "%~1"=="" set "ILFORGE_HOME=%~1"
if not defined ILFORGE_HOME set "ILFORGE_HOME=%LOCALAPPDATA%\ILForge\home"
if not exist "%ILFORGE_HOME%" mkdir "%ILFORGE_HOME%" >nul 2>nul

REM --- tools on PATH: the compilers in out\, plus cc, lex and yacc ---
set "ILFORGE_BIN=%ILFORGE_ROOT%\out"
set "ILFORGE_CC=%ILFORGE_ROOT%\src\Cc\bin\Release\net10.0"
set "PATH=%ILFORGE_BIN%;%ILFORGE_CC%;%ILFORGE_ROOT%\lex;%ILFORGE_ROOT%\yacc;%PATH%"

REM --- search paths honoured by cc (like INCLUDE/LIB in a VS prompt) ---
if not defined INCLUDE set "INCLUDE=%ILFORGE_ROOT%\include"
if not defined LIB     set "LIB=%ILFORGE_ROOT%\out"

REM --- the Unix-style shell, for when you want pipes and coreutils ---
set "ILSH=%ILFORGE_ROOT%\src\ilshell\bin\Release\net10.0\ilshell.exe"
set "ILSH_DLL=%ILFORGE_ROOT%\out\ilsh.dll"
doskey ilsh="%ILSH%" "%ILSH_DLL%" --home "%ILFORGE_HOME%" $*
doskey ilforge-help=type "%ILFORGE_ROOT%\docs\COMMANDS.txt"

echo.
echo  ILForge Developer Command Prompt
echo  --------------------------------
echo  root : %ILFORGE_ROOT%
echo  home : %ILFORGE_HOME%
echo.
echo  compilers : cc pascal oberon tcpp qbasic forth fortran cobol ada smalltalk lua awk coilfe
echo  interps   : logo lisp prolog bc
echo  tools     : lex yacc ilsh (Unix-style shell)   ilforge-help (command list)
echo.
echo  e.g.   lua hello.lua -o hello.exe  ^&^&  hello.exe
echo         cc prog.c -o prog.exe --icon "%ILFORGE_ROOT%\icons\default.png"
echo.

cd /d "%ILFORGE_HOME%" 2>nul
