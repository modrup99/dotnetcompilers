# uninstall.ps1 — remove the toolchain and its Start Menu shortcuts.
#
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1 [-Dest <dir>]

param([string]$Dest = "$env:LOCALAPPDATA\Programs\ildev")
$ErrorActionPreference = "Continue"

$programs = [Environment]::GetFolderPath("Programs")
foreach ($n in @("IL Shell.lnk", "IL Shell (console).lnk")) {
    $p = Join-Path $programs $n
    if (Test-Path $p) { Remove-Item -Force $p; Write-Host "removed shortcut $n" }
}
if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest; Write-Host "removed $Dest" }
else { Write-Host "nothing installed at $Dest" }
