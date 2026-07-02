; ─────────────────────────────────────────────────────────────
;  Dark Downloader — Windows Installer (Inno Setup 6)
;
;  Produces a real Setup.exe (no MSIX, no code-signing certificate).
;  - Installs into  {autopf}\Dark Downloader
;  - Creates a Desktop shortcut  (always)
;  - Creates a Start Menu group
;  - Offers to launch the app after install
;  - Ships with a proper Uninstall entry in Programs & Features
;
;  This file is consumed by scripts/build_installer.ps1 — do not compile it
;  by hand unless you have already run `flutter build windows --release`.
; ─────────────────────────────────────────────────────────────

#ifndef AppVersion
    #define AppVersion "1.1.36"
#endif

#define AppName        "Dark Downloader"
#define AppPublisher   "Dark Technology"
#define AppExeName     "dark_downloader.exe"
#define AppURL         "https://keenx.net"
#define AppId          "{{5E3C6E1A-8B4E-4E1D-9A5B-2C7D0F4A1B10}"

; SourceDir points at the Flutter release output; the build script passes /DSourceDir=...
#ifndef SourceDir
    #define SourceDir "..\build\windows\x64\runner\Release"
#endif

; Where the compiled Setup.exe should land.
#ifndef OutputDir
    #define OutputDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} v{#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Installer
VersionInfoProductName={#AppName}

; Install per-machine if run as admin, otherwise per-user — no admin required for basic install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableDirPage=no
DisableReadyPage=no
DisableFinishedPage=no
AllowNoIcons=yes

; Setup.exe metadata
OutputBaseFilename=Dark-Downloader-Setup-v{#AppVersion}
OutputDir={#OutputDir}
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}

; Compression
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=2

; Cosmetic
WizardStyle=modern
ShowLanguageDialog=auto
WindowVisible=no

; No admin prompt when only writing under user profile.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Bump this each release; users get "already installed" prompt otherwise.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ar"; MessagesFile: "compiler:Languages\Arabic.isl"

[Tasks]
Name: "desktopicon";   Description: "{cm:CreateDesktopIcon}";   GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Ship the entire Flutter Release output. Excludes any leftover .msix / .zip / previous installer / debug symbols.
Source: "{#SourceDir}\*"; DestDir: "{app}"; \
    Excludes: "*.msix,*.zip,*.pdb,Dark-Downloader-Setup-*.exe,Install-DarkDownloader.ps1,RUN.bat,README.txt"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; Start Menu
Name: "{autoprograms}\{#AppName}";        Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autoprograms}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

; Desktop — always created (user request)
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

; Optional Quick Launch (legacy)
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#AppName}"; \
    Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: quicklaunchicon

[Run]
; Offer to launch the app after finishing the wizard.
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Wipe app data folders on uninstall (comment out to preserve user data).
Type: filesandordirs; Name: "{app}"
