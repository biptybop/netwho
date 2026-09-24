; Inno Setup script for NetWho. Built by .github/workflows/windows.yml:
;   iscc /DAppVersion=1.0.0 /DSourceDir=<release bundle> /DOutputDir=<dir> netwho.iss
; Installs per user (no admin rights), which also suits managed work PCs.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; Never change AppId: Windows uses it to recognise upgrades.
AppId={{AECF19A8-2EB1-44F0-A01C-3044B49C1E69}
AppName=NetWho
AppVersion={#AppVersion}
AppVerName=NetWho {#AppVersion}
AppPublisher=biptybop
AppPublisherURL=https://github.com/biptybop/netwho
AppSupportURL=https://github.com/biptybop/netwho/issues
AppUpdatesURL=https://github.com/biptybop/netwho/releases
DefaultDirName={localappdata}\Programs\NetWho
DefaultGroupName=NetWho
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\..\LICENSE
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\netwho.exe
OutputDir={#OutputDir}
OutputBaseFilename=netwho-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\NetWho"; Filename: "{app}\netwho.exe"
Name: "{autodesktop}\NetWho"; Filename: "{app}\netwho.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\netwho.exe"; Description: "{cm:LaunchProgram,NetWho}"; Flags: nowait postinstall skipifsilent
