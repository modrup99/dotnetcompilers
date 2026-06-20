# build_dist.ps1 — assemble a relocatable distribution of the dotnetcompilers toolchain.
#
#   powershell -ExecutionPolicy Bypass -File installer\build_dist.ps1 [-Build] [-Zip]
#
#   -Build   run build_all.sh first (needs Git Bash + .NET 10 SDK)
#   -Zip     also produce dist\ildev.zip
#
# The layout is kept relocatable: the toolchain locates itself by walking up from
# CRuntime.dll to the folder containing build_all.sh, so we ship that marker at the
# root with out\, src\Cc\bin\..., and the launcher bins beneath it.

param([switch]$Build, [switch]$Zip)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path "$PSScriptRoot\..").Path
$dest = Join-Path $repo "dist\ildev"

if ($Build) { & bash "$repo/build_all.sh"; if ($LASTEXITCODE -ne 0) { throw "build_all.sh failed" } }

if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force $dest | Out-Null

function StageDir($rel) {
    $s = Join-Path $repo $rel
    if (-not (Test-Path $s)) { Write-Warning "skip (not built): $rel"; return }
    $d = Join-Path $dest $rel
    New-Item -ItemType Directory -Force $d | Out-Null
    Copy-Item "$s\*" $d -Recurse -Force
    Write-Host "  staged $rel"
}
function StageFile($rel) {
    $s = Join-Path $repo $rel
    if (-not (Test-Path $s)) { return }
    $d = Join-Path $dest $rel
    New-Item -ItemType Directory -Force (Split-Path $d) | Out-Null
    Copy-Item $s $d -Force
}

# runtime marker + rebuild helpers
StageFile "build_all.sh"
StageFile "build-all.bat"
StageFile "README.md"

# the compilers/tools, the C compiler, and the launchers (with all their deps)
StageDir  "out"
# drop generated intermediates that aren't needed at runtime (parser/scanner C, etc.)
Get-ChildItem (Join-Path $dest "out") -Filter *.c -File -ErrorAction SilentlyContinue | Remove-Item -Force
StageDir  "src\Cc\bin\Release\net10.0"
StageDir  "src\ilshell\bin\Release\net10.0"
StageDir  "src\ilterm\bin\Release\net10.0"
StageDir  "src\ilgfx\bin\Release\net10.0"

# language reference docs (so `man <lang>` works) + sample config
Get-ChildItem $repo -Directory | Where-Object { $_.Name -notin @("dist","installer","src",".git") } | ForEach-Object {
    Get-ChildItem $_.FullName -Filter *.md -File -ErrorAction SilentlyContinue | ForEach-Object {
        StageFile ($_.FullName.Substring($repo.Length + 1))
    }
}
StageFile "shell\dot-ilshellrc.sample"
StageFile "shell\dot-quicklaunch.sample"

# seed home directory (becomes the persistent /home on install)
Copy-Item (Join-Path $PSScriptRoot "home") $dest -Recurse -Force
Write-Host "  staged home (seed)"

# the per-machine installer + uninstaller travel inside the package
Copy-Item "$PSScriptRoot\install.ps1"   $dest -Force
Copy-Item "$PSScriptRoot\uninstall.ps1" $dest -Force

$bytes = (Get-ChildItem $dest -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("Distribution staged at {0} ({1:N1} MB)" -f $dest, ($bytes / 1MB))

if ($Zip) {
    $zip = Join-Path $repo "dist\ildev.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Compress-Archive -Path "$dest\*" -DestinationPath $zip -Force
    Write-Host "Zipped -> $zip"
}
