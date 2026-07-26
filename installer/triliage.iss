; Inno Setup script for triliage.
;
; Flutter's Windows output is not a standalone binary: triliage.exe is a ~90KB
; shim that loads flutter_windows.dll and the AOT snapshot in data\app.so. All
; of it has to be installed together, which is why [Files] copies the whole
; Release directory rather than picking out the executable.
;
; Build locally with:
;   flutter build windows --release
;   ISCC.exe /DAppVersion=0.1.0 installer\triliage.iss
;
; The compiled installer lands in dist\.

#define AppName "triliage"
#define AppPublisher "Jayakrishna Konda"
#define AppURL "https://github.com/jay739/triliage"
#define AppExe "triliage.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

; Overridden by CI with the release tag. The fallback keeps a local compile
; working without arguments.
#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif

[Setup]
; Stable across releases on purpose: this is how Windows recognises an install
; as an upgrade of the same app rather than a second copy alongside it. Never
; regenerate it.
AppId={{8F3A2C7E-4B19-4D6A-9E52-1C7A0B3D5E84}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputDir=..\dist
OutputBaseFilename=triliage-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

; Per-user by default, so a normal install needs no admin rights and raises no
; UAC prompt. Someone who wants a machine-wide install can still elevate from
; the wizard, which is what the overrides line allows.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
