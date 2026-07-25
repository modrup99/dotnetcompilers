# Packaging & installing ILForge

ILForge is **relocatable**: every tool finds the others by walking up from `CRuntime.dll`
to the folder containing `build_all.sh`. The distribution preserves that layout, so it runs
from wherever it is installed.

## 1. Build the distribution

From the repo root (add `-Build` to rebuild the toolchain first, `-Zip` to also produce
`dist\ILForge.zip`):

```
powershell -ExecutionPolicy Bypass -File installer\build_dist.ps1 -Build -Zip
```

This stages a self-contained tree into `dist\ILForge\`: the compilers and tools (`out\`),
the C compiler (`src\Cc\bin\...`), the shell launchers, the brand and per-language icons,
the full documentation (`docs\`), the worked examples, the developer command prompt, and
the seed home directory.

## 2. Install

**PowerShell installer** (no extra software). Unzip the package, then from inside it:

```
powershell -ExecutionPolicy Bypass -File install.ps1
```

Defaults to **`%ProgramFiles%\ILForge`** and self-elevates (Program Files needs
administrator rights); the Start Menu group is then registered for all users. Options:

| Option | Effect |
|---|---|
| `-PerUser` | install to `%LOCALAPPDATA%\Programs\ILForge`, no elevation |
| `-Dest <dir>` | install anywhere else |
| `-HomeDir <dir>` | the shell's home (default `%LOCALAPPDATA%\ILForge\home`) |
| `-NoElevate` | fail rather than prompt for elevation |

It creates an **ILForge** Start Menu group containing:

- **ILForge Shell** — the windowed terminal (color, fonts, right-click menu)
- **ILForge Shell (console)** — the same shell in a console window
- **ILForge Developer Command Prompt** — `cmd.exe` with the whole toolchain on `PATH`
- **ILForge Documentation** — opens the manual

Remove it with `uninstall.ps1` (which keeps your home directory unless you pass `-RemoveHome`).

**Inno Setup installer** — for a signed-style `Setup.exe` with an Add/Remove Programs
entry. Needs [Inno Setup](https://jrsoftware.org/isdl.php):

```
ISCC installer\ilforge.iss        ->  installer\Output\ILForge-setup.exe
```

## The home directory

The shell's home lives **outside** the install tree (Program Files is not user-writable),
defaulting to `%LOCALAPPDATA%\ILForge\home`. It holds your `.ilshellrc` and `.quicklaunch`,
persists across reinstalls, and is never overwritten. `.ilshellrc` is generated once with
the installed layout; if you later reinstall the toolchain elsewhere, the install-relative
mounts in it are rebased automatically while your own edits are kept. Inside the shell,
`refresh` reloads `.ilshellrc` and the quicklaunch menu without restarting.

## Requirements

- **To run:** the **.NET 10 runtime**
  (https://dotnet.microsoft.com/download/dotnet/10.0). The installer warns if it is absent.
- **To compile new `.exe` files** with `cc`: the **.NET 10 SDK** (cc stamps the apphost
  from the SDK). Compiling to `.dll` works with the runtime alone.
