# uninstall.ps1 - remove ILForge and its Start Menu group.
#
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1 [-Dest <dir>] [-Home]
#
# The home directory is kept by default (it holds your .ilshellrc, .quicklaunch and work);
# pass -RemoveHome to delete it too.
# (Note: the switch cannot be called -Home -- $Home is a read-only PowerShell variable.)

param(
    [string]$Dest = "$env:ProgramFiles\ILForge",
    [string]$HomeDir = "$env:LOCALAPPDATA\ILForge\home",
    [switch]$RemoveHome
)
$ErrorActionPreference = "Continue"

foreach ($root in @([Environment]::GetFolderPath("CommonPrograms"), [Environment]::GetFolderPath("Programs"))) {
    $g = Join-Path $root "ILForge"
    if (Test-Path $g) { Remove-Item -Recurse -Force $g; Write-Host "removed Start Menu group: $g" }
    # older layouts put the shortcuts loose in Programs
    foreach ($n in @("IL Shell.lnk", "IL Shell (console).lnk")) {
        $p = Join-Path $root $n
        if (Test-Path $p) { Remove-Item -Force $p; Write-Host "removed shortcut $n" }
    }
}

if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest; Write-Host "removed $Dest" }
else { Write-Host "nothing installed at $Dest" }

if ($RemoveHome) {
    if (Test-Path $HomeDir) { Remove-Item -Recurse -Force $HomeDir; Write-Host "removed home $HomeDir" }
} elseif (Test-Path $HomeDir) {
    Write-Host "kept home directory: $HomeDir  (pass -RemoveHome to remove it)"
}
