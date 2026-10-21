param([string]$ISCC = 'ISCC.exe')
. (Join-Path $PSScriptRoot 'common.ps1')
& $ISCC '/DInstallerPreview=1' "/DAppVersion=$AppVersion" (Join-Path $RepoRoot 'packaging/installer.iss')
if ($LASTEXITCODE) { throw 'Installer preview compilation failed' }
Write-Host (Join-Path $RepoRoot 'artifacts/installer-preview/SLink-Installer-Preview.exe')
