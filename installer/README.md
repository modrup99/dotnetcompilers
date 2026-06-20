# Packaging & installing IL Shell

The toolchain is **relocatable**: every tool finds the others by walking up from
`CRuntime.dll` to the folder that contains `build_all.sh`. The distribution preserves that
layout, so it runs from wherever it is installed.

## 1. Build the distribution

From the repo root (after the toolchain is built, or pass `-Build` to build it first):

```
powershell -ExecutionPolicy Bypass -File installer\build_dist.ps1 -Build -Zip
```

This stages a self-contained tree into `dist\ildev\` (the compilers and tools in `out\`,
the C compiler in `src\Cc\bin\...`, the shell launchers, the language docs for `man`, and
the sample config files) and, with `-Zip`, produces `dist\ildev.zip`.

## 2. Install it (Start Menu shortcut, no admin)

Two ways:

**PowerShell installer** (no extra software). Unzip the package, then from inside it:

```
powershell -ExecutionPolicy Bypass -File install.ps1
```

It copies the toolchain to `%LOCALAPPDATA%\Programs\ildev` (override with `-Dest`) and adds
**IL Shell** (the windowed terminal) and **IL Shell (console)** to the Start Menu. Search
the Start Menu for "IL Shell" to launch. Remove it with `uninstall.ps1`.

**Inno Setup installer** (a polished `Setup.exe` with an uninstaller in
Add/Remove Programs). Needs [Inno Setup](https://jrsoftware.org/isdl.php):

```
ISCC installer\ildev.iss
```

produces `installer\Output\ildev-setup.exe`.

## Requirements

- **To run** the shell and the pre-built compilers: the **.NET 10 runtime**
  (https://dotnet.microsoft.com/download/dotnet/10.0). The installer warns if it's missing.
- **To compile new programs to `.exe`** with `cc`: the **.NET 10 SDK** (cc stamps the
  apphost from the SDK). Compiling to `.dll` works with just the runtime.
