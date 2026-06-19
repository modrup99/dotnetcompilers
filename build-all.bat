@echo off
REM ===================================================================
REM  build-all - rebuild the entire toolchain from source.
REM  Needs Git Bash (bash) on PATH and the .NET 10 SDK.
REM ===================================================================
setlocal
cd /d "%~dp0"
where bash >nul 2>nul
if errorlevel 1 (
  echo Git Bash 'bash' was not found on your PATH.
  echo Install Git for Windows, or build manually:
  echo     dotnet build src\Cc -c Release
  echo     bash shell\build.sh
  pause
  exit /b 1
)
bash "%~dp0build_all.sh"
echo.
pause
endlocal
