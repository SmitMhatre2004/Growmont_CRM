; ============================================================================
; Growmont CRM Windows Installer (Inno Setup 6)
; ============================================================================
; Per-user installer for Growmont CRM. Packages the Flutter Release build
; output (growmont_crm.exe + engine DLLs + data\) — no separate updater exe;
; UpdateService.launchUpdaterAndExit runs a future version of this same
; installer directly.
;
; Build-time defines (passed via ISCC's /D switch):
;
;   MyAppVersion  Required for a real release build. e.g.:
;                   iscc growmont_installer.iss /DMyAppVersion=1.1.0
;                 Falls back to "0.0.0" if omitted, so the script can still
;                 be opened/compiled manually in the Inno Setup IDE.
;
;   ReleaseDir    Optional. Absolute path to the Flutter Release output
;                 folder (the one containing growmont_crm.exe). Passed by
;                 build_release.ps1, which auto-detects the correct path
;                 for the Flutter version in use. Falls back to the
;                 conventional relative path below if omitted.
;
; NOTE ON SLASHES: path values passed to #define / /D go through Inno
; Setup's preprocessor, which applies C-style string escaping (\n, \t, \xHH,
; ...). A literal Windows path containing e.g. "\x64" can be silently
; corrupted by that escape processing. Forward slashes avoid the problem
; entirely and Windows/Inno resolve them identically to backslashes, so
; every path define below uses "/" rather than "\".
; ============================================================================

#define MyAppName "Growmont CRM"
#define MyAppPublisher "Growmont"
#define MyAppURL "https://github.com/CruciaTos/GrowmontCRM_Release"
#define MyAppExeName "growmont_crm.exe"
; Permanent — do not change once the first release ships. See [Setup] below.
#define MyAppId "{7B3F1A62-9C48-4E1D-BF06-2A5D8C4E9F13}"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef ReleaseDir
  #define ReleaseDir "../flutterapp/build/windows/x64/runner/Release"
#endif

#define AppIconFile "../flutterapp/windows/runner/resources/app_icon.ico"

[Setup]
; Permanent AppId — do not change. This is what lets Setup recognize an
; existing install (same registry key) and perform an in-place upgrade
; instead of a side-by-side install. Changing it after the first release
; breaks in-place upgrades for everyone already installed.
AppId={{#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription={#MyAppName} Setup

; ---- Per-user install, no admin rights, no UAC prompt -----------------
DefaultDirName={localappdata}\Programs\GrowmontCRM
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest

; ---- In-place upgrade support ------------------------------------------
; AppId is fixed, so Setup finds any previous install of this AppId via the
; registry and reuses its directory/group automatically. These are Inno's
; defaults but are stated explicitly since in-place upgrade is a hard
; requirement here.
UsePreviousAppDir=yes
UsePreviousGroup=yes
UpdateUninstallLogAppName=yes

; ---- Native "close running app" support (Inno Setup 6 / Restart Manager)
; Setup detects growmont_crm.exe if running and closes it (with a prompt in
; interactive mode, silently under /VERYSILENT) before copying files over
; it. No custom process-killing code needed.
CloseApplications=yes
CloseApplicationsFilter=growmont_crm.exe
; Restart Manager restarting the app on its own would race with, and could
; double-launch alongside, the explicit relaunch entries in [Run] below (the
; interactive "Launch Growmont CRM" checkbox, and the silent-only
; auto-relaunch used by UpdateService.launchUpdaterAndExit) — so relaunching
; is left entirely to those [Run] entries.
RestartApplications=no

; ---- Output ---------------------------------------------------------------
OutputDir=Output
OutputBaseFilename=Growmont-Setup-{#MyAppVersion}
SetupIconFile={#AppIconFile}
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

; 64-bit only — matches the Flutter Windows x64 build output. "x64" is
; recognized by every Inno Setup 6.x release; if you're on Inno Setup 6.3+
; and want native ARM64 Windows support via x64 emulation, both values here
; can be changed to "x64compatible" instead.
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

; Flutter's Windows desktop embedder targets Windows 10 or later.
MinVersion=10.0

; /VERYSILENT, /SUPPRESSMSGBOXES, /NORESTART and /SP- are all handled
; natively by Setup's command-line parsing — nothing further to configure
; for them. No [Code] section is used in this script, so there is no custom
; UI that could block a silent run.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; Entire Release output tree: growmont_crm.exe, the Flutter engine DLLs,
; and the data\ folder.
;
; This is the ONLY [Files] entry in the script, and ReleaseDir always
; resolves to the build output under flutterapp\build\... — never to any
; %AppData% path. Per-user data (growmont.db etc.) lives under
; {userappdata}\...\GrowmontCRM and must never appear here.
Source: "{#ReleaseDir}/*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; Interactive installs (double-click, no /VERYSILENT): shows an optional
; "Launch Growmont CRM" checkbox on the wizard's Finished page. skipifsilent
; means this entry is always skipped when Setup is run silently — the entry
; below handles that case instead, so the two together are mutually
; exclusive.
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

; Silent installs (/VERYSILENT, used by UpdateService.launchUpdaterAndExit
; for in-app auto-updates): no wizard pages are shown, so there's no
; checkbox to check and postinstall entries above are skipped outright.
; skipifnotsilent is the mirror image of skipifsilent — it runs this entry
; only when Setup IS silent — so a silent update automatically relaunches
; the newly-installed Growmont CRM instead of leaving the user with the app
; closed after an update.
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; WorkingDir: "{app}"; Flags: nowait skipifnotsilent

[UninstallDelete]
; Recursively remove the install directory itself on uninstall (engine
; DLLs and any runtime files the app writes inside its own folder — none of
; which are tracked individually by [Files]).
;
; This is safe specifically because {app} is {localappdata}\Programs\
; GrowmontCRM, a directory tree entirely separate from the
; %AppData%\Roaming user-data path. Nothing in this script ever references
; an %AppData% path, so nothing under it can ever be deleted by this
; installer or its uninstaller.
Type: filesandordirs; Name: "{app}"
