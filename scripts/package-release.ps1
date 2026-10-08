[CmdletBinding()]
param([string]$ReleaseDir)
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $ReleaseDir) { $ReleaseDir = Join-Path $RepoRoot 'artifacts/releases' }
$ReleaseDir = [IO.Path]::GetFullPath($ReleaseDir)
Assert-BundledDependencies
$installer = Join-Path $ReleaseDir "SLink-$AppVersion-Setup-x64.exe"
if (-not (Test-Path -LiteralPath $installer)) { throw 'Build the installer before packaging a release.' }
if ((Get-Item -LiteralPath $installer).VersionInfo.ProductVersion -ne $AppVersion) {
    throw 'Installer version does not match Version.cs.'
}
$dirty = & git -C $RepoRoot status --porcelain --untracked-files=normal
if ($LASTEXITCODE -or $dirty) { throw 'Release packaging requires a clean, committed Git checkout.' }
$source = Join-Path $ReleaseDir "SLink-$AppVersion-source.zip"
& git -C $RepoRoot archive --format=zip "--prefix=SLink-$AppVersion/" "--output=$source" HEAD
if ($LASTEXITCODE) { throw 'Source archive failed.' }
$dependencies = Get-Content (Join-Path $RepoRoot 'third_party/dependencies.json') -Raw | ConvertFrom-Json
$runtime = Join-Path $ReleaseDir ('msys2-runtime-' + $dependencies.runtimeSource.revision + '.tar.gz')
if (-not (Test-Path -LiteralPath $runtime)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $dependencies.runtimeSource.url -OutFile $runtime
}
if ((Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash -ne $dependencies.runtimeSource.sha256) {
    throw 'MSYS2 corresponding source checksum mismatch.'
}
$lines = @($installer, $source, $runtime) | ForEach-Object {
    (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($_)
}
[IO.File]::WriteAllText((Join-Path $ReleaseDir 'SHA256SUMS.txt'), ($lines -join "`n") + "`n")
[IO.File]::WriteAllText("$installer.sha256", $lines[0] + "`n")
Get-ChildItem -LiteralPath $ReleaseDir | Select-Object Name, Length
