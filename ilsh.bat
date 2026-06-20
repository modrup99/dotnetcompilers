@echo off
REM ===================================================================
REM  ilsh - the IL shell (interactive, in this console window)
REM  Double-click to open a shell. Type  exit  to leave.
REM  Inside you get: cc, lex, yacc, make, vi, and the coreutils.
REM ===================================================================
setlocal
set "EXE=%~dp0src\ilshell\bin\Release\net10.0\ilshell.exe"
if not exist "%EXE%" (
  echo [ilsh] not built yet. Run build-all.bat first ^(needs Git Bash^).
  pause
  exit /b 1
)
cd /d "%~dp0"
title ilsh
REM  forward args (e.g.  ilsh --home C:\path  enables the virtual filesystem)
"%EXE%" %*
echo.
echo [ilsh exited]  Press any key to close this window.
pause >nul
endlocal
