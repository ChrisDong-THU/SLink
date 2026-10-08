#ifndef AppVersion
 #error AppVersion is required
#endif
#ifndef BuildDir
 #error BuildDir is required
#endif
#ifndef ReleaseDir
 #error ReleaseDir is required
#endif
[Setup]
AppId={{3C48002B-271A-4E2C-9E23-18ECFA0DE621}
AppName=SLink
AppVersion={#AppVersion}
AppPublisher=SLink
AppPublisherURL=https://github.com/ChrisDong-THU/SLink
AppSupportURL=https://github.com/ChrisDong-THU/SLink/issues
AppUpdatesURL=https://github.com/ChrisDong-THU/SLink/releases
LicenseFile=..\LICENSE
DefaultDirName={autopf}\SLink
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir={#ReleaseDir}
OutputBaseFilename=SLink-{#AppVersion}-Setup-x64
SetupIconFile=..\assets\app.ico
UninstallDisplayIcon={app}\SLink.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
VersionInfoVersion={#AppVersion}
[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
[CustomMessages]
chinesesimp.LaunchApp=启动 SLink
english.LaunchApp=Launch SLink
chinesesimp.CleanupFailed=尚未完成网络清理，请断开 SLink 连接后重试。
english.CleanupFailed=Network cleanup is incomplete. Disconnect SLink and retry.
[Files]
Source: "{#BuildDir}\SLink.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\SLink.exe.config"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\THIRD_PARTY.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\native\*.ps1"; DestDir: "{app}\native"; Flags: ignoreversion
Source: "{#BuildDir}\bin\*"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#BuildDir}\licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "{#BuildDir}\SLink.exe"; DestName: "SLink-upgrade.exe"; Flags: dontcopy
Source: "{#BuildDir}\native\network.ps1"; DestName: "network-upgrade.ps1"; Flags: dontcopy
Source: "{#BuildDir}\native\network-probes.ps1"; DestName: "network-probes-upgrade.ps1"; Flags: dontcopy
[InstallDelete]
Type: filesandordirs; Name: "{app}\_internal"
[Icons]
Name: "{commondesktop}\SLink"; Filename: "{app}\SLink.exe"; WorkingDir: "{app}"; AppUserModelID: "SLink.Desktop"
Name: "{commonprograms}\SLink"; Filename: "{app}\SLink.exe"; WorkingDir: "{app}"; AppUserModelID: "SLink.Desktop"
[Run]
Filename: "{app}\SLink.exe"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent runascurrentuser
[Code]
function InitializeSetup(): Boolean;
var Release: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', Release) and (Release >= 528040);
  if not Result then MsgBox('SLink requires Windows with .NET Framework 4.8 or later.', mbError, MB_OK);
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
var Code: Integer;
begin
  Result := '';
  ExtractTemporaryFile('SLink-upgrade.exe');
  ExtractTemporaryFile('network-upgrade.ps1');
  ExtractTemporaryFile('network-probes-upgrade.ps1');
  ForceDirectories(ExpandConstant('{tmp}\native'));
  CopyFile(ExpandConstant('{tmp}\network-upgrade.ps1'), ExpandConstant('{tmp}\native\network.ps1'), False);
  CopyFile(ExpandConstant('{tmp}\network-probes-upgrade.ps1'), ExpandConstant('{tmp}\native\network-probes.ps1'), False);
  if not Exec(ExpandConstant('{tmp}\SLink-upgrade.exe'), '--prepare-install "' + ExpandConstant('{app}\SLink.exe') + '"', ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then
    Result := CustomMessage('CleanupFailed');
end;
function InitializeUninstall(): Boolean;
var Code: Integer;
begin
  Result := Exec(ExpandConstant('{app}\SLink.exe'), '--quit --wait', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
  if not Result then MsgBox(CustomMessage('CleanupFailed'), mbError, MB_OK);
end;
