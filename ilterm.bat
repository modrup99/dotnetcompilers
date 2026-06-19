@echo off
REM ===================================================================
REM  ilterm - the windowed VT terminal (Avalonia GUI) running the shell
REM  Double-click to open the terminal window. Resizable; history with
REM  the up-arrow and  !  expansion; run make/cc/vi inside it.
REM ===================================================================
setlocal
set "EXE=%~dp0src\ilterm\bin\Release\net10.0\ilterm.exe"
set "DLL=%~dp0out\ilsh.dll"
if not exist "%EXE%" (
  echo [ilterm] not built yet. Run build-all.bat first.
  pause
  exit /b 1
)
cd /d "%~dp0"
REM launch detached so this console closes immediately; the GUI stays up
start "ilterm" "%EXE%" "%DLL%"
endlocal
