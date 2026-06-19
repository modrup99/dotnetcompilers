@echo off
REM ===================================================================
REM  xeyes - the classic X11 demo (two eyes follow the mouse), running
REM  as our C -> .NET IL program inside the ilgfx graphics window.
REM  Double-click to open; close the window to quit.
REM ===================================================================
setlocal
set "EXE=%~dp0src\ilgfx\bin\Release\net10.0\ilgfx.exe"
set "DLL=%~dp0out\xeyes.dll"
if not exist "%EXE%" (
  echo [xeyes] ilgfx not built yet. Run build-all.bat first.
  pause
  exit /b 1
)
cd /d "%~dp0"
start "xeyes" "%EXE%" "%DLL%"
endlocal
