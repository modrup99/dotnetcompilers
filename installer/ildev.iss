; ildev.iss — Inno Setup script for a proper IL Shell installer (Setup.exe + uninstaller).
;
; Build the payload first, then compile this with Inno Setup's ISCC:
;     powershell -File installer\build_dist.ps1
;     ISCC installer\ildev.iss            (needs Inno Setup: https://jrsoftware.org/isdl.php)
;
; Produces installer\Output\ildev-setup.exe. Installs per-user (no admin), adds the
; IL Shell entries to the Start Menu, and registers an uninstaller.

[Setup]
AppName=IL Shell
AppVerName=IL Shell (dotnetcompilers toolchain)
AppPublisher=dotnetcompilers
DefaultDirName={localappdata}\Programs\ildev
DefaultGroupName=IL Shell
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
Compression=lzma2
SolidCompression=yes
OutputDir=Output
OutputBaseFilename=ildev-setup
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "..\dist\ildev\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion; \
    Excludes: "install.ps1,uninstall.ps1"

[Icons]
Name: "{group}\IL Shell"; Filename: "{app}\src\ilterm\bin\Release\net10.0\ilterm.exe"; \
    Parameters: """{app}\out\ilsh.dll"""; WorkingDir: "{app}"; \
    Comment: "IL Shell — windowed terminal (color, fonts, menu)"
Name: "{group}\IL Shell (console)"; Filename: "{app}\src\ilshell\bin\Release\net10.0\ilshell.exe"; \
    Parameters: """{app}\out\ilsh.dll"""; WorkingDir: "{app}"; \
    Comment: "IL Shell in a console window"
Name: "{group}\Uninstall IL Shell"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\src\ilterm\bin\Release\net10.0\ilterm.exe"; Parameters: """{app}\out\ilsh.dll"""; \
    WorkingDir: "{app}"; Description: "Launch IL Shell now"; Flags: nowait postinstall skipifsilent
