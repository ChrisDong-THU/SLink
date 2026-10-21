#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef InstallerPreview
  #ifndef BuildDir
    #error BuildDir is required
  #endif
  #ifndef ReleaseDir
    #error ReleaseDir is required
  #endif
#endif

[Setup]
AppId={{3C48002B-271A-4E2C-9E23-18ECFA0DE621}
AppName=SLink
AppVersion={#AppVersion}
AppPublisher=SLink
AppPublisherURL=https://github.com/ChrisDong-THU/SLink
AppSupportURL=https://github.com/ChrisDong-THU/SLink/issues
DefaultDirName={autopf}\SLink
DefaultGroupName=SLink
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableReadyPage=yes
DisableDirPage=no
AppendDefaultDirName=yes
#ifdef InstallerPreview
PrivilegesRequired=lowest
CreateAppDir=no
UsePreviousAppDir=no
Uninstallable=no
OutputDir=..\artifacts\installer-preview
OutputBaseFilename=SLink-Installer-Preview
#else
PrivilegesRequired=admin
OutputDir={#ReleaseDir}
OutputBaseFilename=SLink-{#AppVersion}-Setup-x64
#endif
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
SetupIconFile=..\assets\app.ico
UninstallDisplayIcon={app}\SLink.exe
Compression=lzma2/normal
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=100
CloseApplications=no
RestartApplications=no
ShowLanguageDialog=no
LanguageDetectionMethod=none
VersionInfoVersion={#AppVersion}

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"

[CustomMessages]
CleanupFailed=尚未完成网络清理，请断开 SLink 连接后重试。

#ifndef InstallerPreview
[Files]
Source: "{#BuildDir}\SLink.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\SLink.exe.config"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\THIRD_PARTY.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\native\*.ps1"; DestDir: "{app}\native"; Flags: ignoreversion
Source: "{#BuildDir}\bin\*"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#BuildDir}\licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "{#BuildDir}\SLink.exe"; DestName: "SLink-upgrade.exe"; Flags: dontcopy
Source: "{#BuildDir}\SLink.exe.config"; DestName: "SLink-upgrade.exe.config"; Flags: dontcopy
Source: "{#BuildDir}\native\network.ps1"; DestName: "network-upgrade.ps1"; Flags: dontcopy
Source: "{#BuildDir}\native\network-probes.ps1"; DestName: "network-probes-upgrade.ps1"; Flags: dontcopy

[InstallDelete]
Type: filesandordirs; Name: "{app}\_internal"
; Remove only known payload files of the withdrawn Flutter build.
; User preferences and network ownership journals live in LocalAppData.
Type: files; Name: "{app}\SLink.Native.exe"
Type: files; Name: "{app}\SLink.Native.exe.config"
Type: files; Name: "{app}\flutter_windows.dll"
Type: files; Name: "{app}\native_assets.json"
Type: files; Name: "{app}\concrt140.dll"
Type: files; Name: "{app}\msvcp140.dll"
Type: files; Name: "{app}\msvcp140_1.dll"
Type: files; Name: "{app}\msvcp140_2.dll"
Type: files; Name: "{app}\msvcp140_atomic_wait.dll"
Type: files; Name: "{app}\msvcp140_codecvt_ids.dll"
Type: files; Name: "{app}\vcruntime140.dll"
Type: files; Name: "{app}\vcruntime140_1.dll"
Type: files; Name: "{app}\data\app.so"
Type: files; Name: "{app}\data\icudtl.dat"
Type: filesandordirs; Name: "{app}\data\flutter_assets"
Type: dirifempty; Name: "{app}\data"
Type: files; Name: "{app}\licenses\Flutter-BSD.txt"

[Icons]
Name: "{autodesktop}\SLink"; Filename: "{app}\SLink.exe"; WorkingDir: "{app}"; AppUserModelID: "SLink.Desktop"
Name: "{autoprograms}\SLink"; Filename: "{app}\SLink.exe"; WorkingDir: "{app}"; AppUserModelID: "SLink.Desktop"

[Run]
Filename: "{app}\SLink.exe"; Description: "打开 SLink"; Flags: nowait postinstall skipifsilent runascurrentuser
#endif

#include "layout.iss"
#ifndef InstallerPreview
#include "cleanup.iss"
#endif

#ifdef InstallerPreview
procedure CurStepChanged(CurStep: TSetupStep);
var Progress: Integer;
begin
  if CurStep = ssInstall then begin
    WizardForm.ProgressGauge.Min := 0;
    WizardForm.ProgressGauge.Max := 100;
    for Progress := 0 to 100 do begin
      WizardForm.StatusLabel.Caption := '正在解压文件…';
      WizardForm.FilenameLabel.Caption := AddBackslash(PreviewInstallDir) + 'SLink.exe';
      WizardForm.ProgressGauge.Position := Progress;
      WizardForm.Refresh;
      Sleep(40);
    end;
  end;
end;
#else
procedure InitializeUninstallProgressForm;
begin
  UninstallProgressForm.Font.Name := 'Microsoft YaHei UI';
  UninstallProgressForm.Font.Size := 9;
end;
#endif
