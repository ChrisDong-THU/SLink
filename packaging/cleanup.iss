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
  { The withdrawn Flutter build owns its session in a separate process.
    Ask that owner to clean up and wait for its UI before replacing any files. }
  if FileExists(ExpandConstant('{app}\SLink.Native.exe')) then begin
    if not Exec(ExpandConstant('{app}\SLink.Native.exe'), '--prepare-install "' + ExpandConstant('{app}\SLink.exe') + '"', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then begin
      Result := CustomMessage('CleanupFailed');
      Exit;
    end;
  end;
  ExtractTemporaryFile('SLink-upgrade.exe');
  ExtractTemporaryFile('SLink-upgrade.exe.config');
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
