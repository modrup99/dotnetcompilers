# install.ps1 — install the dotnetcompilers toolchain for the current user and put the
# shell on the Start Menu.  Run this from inside the unzipped package:
#
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Dest <dir>]
#
# Default destination: %LOCALAPPDATA%\Programs\ildev

param([string]$Dest = "$env:LOCALAPPDATA\Programs\ildev")
$ErrorActionPreference = "Stop"
$src = $PSScriptRoot

# .NET 10 runtime is required to run the toolchain (SDK only needed to compile new exes).
$rt = & dotnet --list-runtimes 2>$null
if (-not ($rt -match "Microsoft\.NETCore\.App 10\.")) {
    Write-Warning "The .NET 10 runtime was not detected."
    Write-Warning "Install it from https://dotnet.microsoft.com/download/dotnet/10.0 (the toolchain needs it to run)."
}

Write-Host "Installing to $Dest ..."
New-Item -ItemType Directory -Force $Dest | Out-Null
# copy everything except the installer scripts themselves
Get-ChildItem $src -Force | Where-Object { $_.Name -notin @("install.ps1", "uninstall.ps1") } |
    ForEach-Object { Copy-Item $_.FullName -Destination $Dest -Recurse -Force }

$ilterm = Join-Path $Dest "src\ilterm\bin\Release\net10.0\ilterm.exe"
$ilshDll = Join-Path $Dest "out\ilsh.dll"
$ilshell = Join-Path $Dest "src\ilshell\bin\Release\net10.0\ilshell.exe"
if (-not (Test-Path $ilterm))  { throw "ilterm.exe missing in package ($ilterm) - was the package built fully?" }
if (-not (Test-Path $ilshDll)) { throw "out\ilsh.dll missing in package" }

$programs = [Environment]::GetFolderPath("Programs")          # per-user Start Menu\Programs
$ws = New-Object -ComObject WScript.Shell

# primary: the windowed terminal (color, fonts, right-click menu)
$lnk = $ws.CreateShortcut((Join-Path $programs "IL Shell.lnk"))
$lnk.TargetPath = $ilterm
$lnk.Arguments = '"' + $ilshDll + '"'
$lnk.WorkingDirectory = $Dest
$lnk.Description = "IL Shell - the dotnetcompilers toolchain (windowed terminal)"
$lnk.Save()

# secondary: the plain console shell
if (Test-Path $ilshell) {
    $lnk2 = $ws.CreateShortcut((Join-Path $programs "IL Shell (console).lnk"))
    $lnk2.TargetPath = $ilshell
    $lnk2.Arguments = '"' + $ilshDll + '"'
    $lnk2.WorkingDirectory = $Dest
    $lnk2.Description = "IL Shell in a console window"
    $lnk2.Save()
}

Write-Host ""
Write-Host "Installed to:        $Dest"
Write-Host "Start Menu shortcut: $(Join-Path $programs 'IL Shell.lnk')"
Write-Host "Search the Start Menu for 'IL Shell' to launch it."
