[Messages]
#ifdef InstallerPreview
SetupAppTitle=安装界面预览
SetupWindowTitle=SLink 安装界面预览
#endif
WizardSelectDir=选择安装位置
SelectDirDesc=将安装到下面的文件夹
SelectDirLabel3=
SelectDirBrowseLabel=
ButtonInstall=安装(&I)
WizardInstalling=正在安装
InstallingLabel=正在解压文件…
FinishedHeadingLabel=安装完成
FinishedLabelNoIcons=
FinishedLabel=

[Code]
#ifdef InstallerPreview
var
  PreviewDirectoryPage: TWizardPage;
  PreviewOpenCheckBox: TNewCheckBox;
  PreviewInstallDir: String;
#endif

const
  WindowClientHeight = 280;
  ContentMargin = 24;
  HeadingTop = 24;
  DescriptionTop = 60;
  ContentTop = 108;
  ButtonGap = 8;
  ProgressHeight = 18;

procedure StyleHeading(LabelControl: TNewStaticText; ContentWidth: Integer);
begin
  LabelControl.SetBounds(ScaleX(ContentMargin), ScaleY(HeadingTop),
    ContentWidth, ScaleY(28));
  LabelControl.Font.Assign(WizardForm.Font);
  LabelControl.Font.Size := 14;
  LabelControl.Font.Style := [fsBold];
end;

procedure StyleDescription(LabelControl: TNewStaticText; ContentWidth: Integer);
begin
  LabelControl.Font.Assign(WizardForm.Font);
  LabelControl.SetBounds(ScaleX(ContentMargin), ScaleY(DescriptionTop),
    ContentWidth, ScaleY(32));
end;

procedure LayoutFooter;
var
  ButtonWidth, ButtonHeight, ButtonTop, RightEdge: Integer;
begin
  ButtonWidth := ScaleX(80);
  ButtonHeight := ScaleY(26);
  ButtonTop := WizardForm.Bevel.Top +
    (WizardForm.ClientHeight - WizardForm.Bevel.Top - ButtonHeight) div 2;
  RightEdge := WizardForm.ClientWidth - ScaleX(ContentMargin);
  WizardForm.CancelButton.SetBounds(RightEdge - ButtonWidth,
    ButtonTop, ButtonWidth, ButtonHeight);
  { Inno hides Cancel on completion, but keeps Next in its old slot. }
  if WizardForm.CancelButton.Visible then
    RightEdge := WizardForm.CancelButton.Left - ScaleX(ButtonGap);
  WizardForm.NextButton.SetBounds(RightEdge - ButtonWidth,
    ButtonTop, ButtonWidth, ButtonHeight);
  WizardForm.BackButton.SetBounds(
    WizardForm.NextButton.Left - ScaleX(ButtonGap) - ButtonWidth,
    ButtonTop, ButtonWidth, ButtonHeight);
end;

procedure InitializeWizard;
var
  ContentWidth: Integer;
begin
  { Keep the native footer anchored while removing unused vertical space. }
  WizardForm.ClientHeight := ScaleY(WindowClientHeight);
  ContentWidth := WizardForm.ClientWidth - ScaleX(ContentMargin * 2);
  WizardForm.Color := clBtnFace;
  WizardForm.InnerPage.Color := clWhite;
  WizardForm.SelectDirPage.Color := clWhite;
  WizardForm.PreparingPage.Color := clWhite;
  WizardForm.InstallingPage.Color := clWhite;
  WizardForm.FinishedPage.Color := clWhite;
  WizardForm.MainPanel.Color := clWhite;
  WizardForm.Bevel1.Visible := False;
  WizardForm.WizardSmallBitmapImage.Visible := False;
  WizardForm.WizardBitmapImage.Visible := False;
  WizardForm.WizardBitmapImage2.Visible := False;
  WizardForm.SelectDirBitmapImage.Visible := False;

  WizardForm.MainPanel.Height := ScaleY(ContentTop);
  StyleHeading(WizardForm.PageNameLabel, ContentWidth);
  StyleHeading(WizardForm.FinishedHeadingLabel, ContentWidth);
  StyleDescription(WizardForm.PageDescriptionLabel, ContentWidth);
  WizardForm.InnerNotebook.SetBounds(ScaleX(ContentMargin),
    ScaleY(ContentTop), ContentWidth,
    WizardForm.OuterNotebook.ClientHeight - ScaleY(ContentTop + ContentMargin));

  WizardForm.FinishedLabel.Font.Assign(WizardForm.Font);
  WizardForm.RunList.Font.Assign(WizardForm.Font);
  WizardForm.RunList.Color := clWhite;
  WizardForm.SelectDirLabel.Visible := False;
  WizardForm.SelectDirBrowseLabel.Visible := False;
  WizardForm.DirBrowseButton.Width := ScaleX(80);
  WizardForm.DirBrowseButton.Height := ScaleY(26);
  WizardForm.DirBrowseButton.Left := ContentWidth - WizardForm.DirBrowseButton.Width;
  WizardForm.DirBrowseButton.Top := 0;
  WizardForm.DirEdit.SetBounds(0, 0,
    WizardForm.DirBrowseButton.Left - ScaleX(ButtonGap), ScaleY(26));
  { Keep Inno's live operation and destination labels, in the shared description
    area. Do not replace them with a fixed "extracting" caption. }
  WizardForm.StatusLabel.Parent := WizardForm.MainPanel;
  WizardForm.StatusLabel.Font.Assign(WizardForm.Font);
  WizardForm.StatusLabel.SetBounds(ScaleX(ContentMargin), ScaleY(DescriptionTop),
    ContentWidth, ScaleY(18));
  WizardForm.FilenameLabel.Parent := WizardForm.MainPanel;
  WizardForm.FilenameLabel.Font.Assign(WizardForm.Font);
  WizardForm.FilenameLabel.SetBounds(ScaleX(ContentMargin), ScaleY(DescriptionTop + 20),
    ContentWidth, ScaleY(18));
  WizardForm.StatusLabel.Visible := False;
  WizardForm.FilenameLabel.Visible := False;
  WizardForm.ProgressGauge.SetBounds(0, 0, ContentWidth, ScaleY(ProgressHeight));
#ifdef InstallerPreview
  { CreateAppDir=no skips Inno's directory page. Reuse its actual controls on
    a preview page, so browsing works without ever creating the chosen path. }
  PreviewDirectoryPage := CreateCustomPage(wpWelcome,
    SetupMessage(msgWizardSelectDir), SetupMessage(msgSelectDirDesc));
  PreviewDirectoryPage.Surface.Color := clWhite;
  WizardForm.DirEdit.Parent := PreviewDirectoryPage.Surface;
  WizardForm.DirEdit.Text := ExpandConstant('{autopf}\SLink');
  WizardForm.DirBrowseButton.Parent := PreviewDirectoryPage.Surface;
  PreviewOpenCheckBox := TNewCheckBox.Create(WizardForm);
  PreviewOpenCheckBox.Parent := WizardForm.FinishedPage;
  PreviewOpenCheckBox.Caption := '打开 SLink';
  PreviewOpenCheckBox.Checked := True;
#endif
end;

procedure CurPageChanged(CurPageID: Integer);
var
  ContentWidth, OptionsTop: Integer;
begin
  LayoutFooter;
  ContentWidth := WizardForm.ClientWidth - ScaleX(ContentMargin * 2);
  { Inno adjusts labels when entering pages; reapply the shared text grid. }
  StyleHeading(WizardForm.PageNameLabel, ContentWidth);
  StyleDescription(WizardForm.PageDescriptionLabel, ContentWidth);
  WizardForm.PageDescriptionLabel.Visible := CurPageID <> wpInstalling;
  WizardForm.StatusLabel.Visible := CurPageID = wpInstalling;
  WizardForm.FilenameLabel.Visible := CurPageID = wpInstalling;
#ifdef InstallerPreview
  if CurPageID = PreviewDirectoryPage.ID then
    WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall);
#endif
  if CurPageID = wpFinished then begin
    { Apply after Inno has populated and positioned the completion controls. }
    ContentWidth := WizardForm.FinishedPage.ClientWidth - ScaleX(ContentMargin * 2);
    StyleHeading(WizardForm.FinishedHeadingLabel, ContentWidth);
    { Empty FinishedLabel messages still leave Inno's paragraph separators
      before the standard finish instruction. Trim those, not just its bounds. }
    WizardForm.FinishedLabel.Caption := Trim(WizardForm.FinishedLabel.Caption);
    StyleDescription(WizardForm.FinishedLabel, ContentWidth);
    WizardForm.AdjustLabelHeight(WizardForm.FinishedLabel);
    OptionsTop := WizardForm.FinishedLabel.Top +
      WizardForm.FinishedLabel.Height + ScaleY(16);
    if OptionsTop < ScaleY(ContentTop) then
      OptionsTop := ScaleY(ContentTop);
    WizardForm.RunList.SetBounds(ScaleX(ContentMargin), OptionsTop,
      ContentWidth, WizardForm.FinishedPage.ClientHeight - OptionsTop - ScaleY(ContentMargin));
#ifdef InstallerPreview
    { Use a visual-only checkbox, not RunList: Inno binds RunList items to [Run]. }
    PreviewOpenCheckBox.SetBounds(ScaleX(ContentMargin), OptionsTop,
      ContentWidth, ScaleY(24));
#endif
    { Preserve Inno's reboot choices if an upgrade requires restarting Windows. }
    WizardForm.YesRadio.SetBounds(ScaleX(ContentMargin), OptionsTop,
      ContentWidth, ScaleY(20));
    WizardForm.NoRadio.SetBounds(ScaleX(ContentMargin), OptionsTop + ScaleY(28),
      ContentWidth, ScaleY(20));
  end;
end;

#ifdef InstallerPreview
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  if CurPageID = PreviewDirectoryPage.ID then begin
    PreviewInstallDir := WizardForm.DirEdit.Text;
    { Inno may ensure DirEdit exists even with CreateAppDir=no. Keep the
      selected directory display-only and use its existing temporary folder. }
    WizardForm.DirEdit.Text := ExpandConstant('{tmp}');
  end;
  Result := True;
end;
#endif
