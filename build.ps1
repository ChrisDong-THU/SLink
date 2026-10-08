[CmdletBinding()]
param(
    [string]$Output,
    [switch]$Setup,
    [string]$ISCC = 'ISCC.exe',
    [string]$ReleaseDir
)
. (Join-Path $PSScriptRoot 'scripts/common.ps1')
if (-not $Output) { $Output = Join-Path $RepoRoot 'artifacts/app' }
if (-not $ReleaseDir) { $ReleaseDir = Join-Path $RepoRoot 'artifacts/releases' }
Assert-BundledDependencies
$Output = [IO.Path]::GetFullPath($Output)
$ReleaseDir = [IO.Path]::GetFullPath($ReleaseDir)
$null = New-Item -ItemType Directory -Path $Output -Force
$sources = Get-ChildItem -LiteralPath $SourceRoot -Filter '*.cs' | ForEach-Object FullName
# Generate the manifest in the output directory so its version cannot drift.
$manifest = Get-Content (Join-Path $SourceRoot 'app.manifest') -Raw
$manifest = $manifest -replace 'assemblyIdentity version="[^"]+"', ('assemblyIdentity version="' + $AppVersion + '.0"')
$manifestPath = Join-Path $Output 'app.manifest'
[IO.File]::WriteAllText($manifestPath, $manifest, (New-Object Text.UTF8Encoding($false)))
$savedLib = $env:LIB
try {
    $env:LIB = ''
    & $Compiler /nologo /target:winexe /platform:x64 /optimize+ /warn:4 /warnaserror+ "/out:$Output/SLink.exe" "/win32manifest:$manifestPath" "/win32icon:$RepoRoot/assets/app.ico" "/resource:$SourceRoot/Main.xaml,Main.xaml" "/resource:$RepoRoot/assets/app.ico,app.ico" @FrameworkReferences @sources
    if ($LASTEXITCODE) { throw 'Compilation failed' }
} finally { $env:LIB = $savedLib }
Copy-Item -LiteralPath (Join-Path $SourceRoot 'SLink.exe.config') -Destination $Output -Force
foreach ($folder in @('native', 'licenses')) {
    $destination = Join-Path $Output $folder
    $null = New-Item -ItemType Directory -Path $destination -Force
    Copy-Item -Path (Join-Path $RepoRoot "$folder/*") -Destination $destination -Force
}
$null = New-Item -ItemType Directory -Path (Join-Path $Output 'bin') -Force
Copy-Item -Path (Join-Path $RepoRoot 'third_party/windows-x64/*') -Destination (Join-Path $Output 'bin') -Force
foreach ($file in @('LICENSE', 'THIRD_PARTY.md')) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination $Output -Force
}
if ($Setup) {
    $null = New-Item -ItemType Directory -Path $ReleaseDir -Force
    & $ISCC "/DAppVersion=$AppVersion" "/DBuildDir=$Output" "/DReleaseDir=$ReleaseDir" (Join-Path $RepoRoot 'packaging/installer.iss')
    if ($LASTEXITCODE) { throw 'Setup compilation failed' }
    $installer = Join-Path $ReleaseDir "SLink-$AppVersion-Setup-x64.exe"
    $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$installer.sha256", "$hash  $([IO.Path]::GetFileName($installer))`n")
}
Get-Item (Join-Path $Output 'SLink.exe') | Select-Object Name, Length
