param([string]$Output=(Join-Path (Split-Path $PSScriptRoot) 'artifacts/tests'))
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'scripts/common.ps1')
$src=$SourceRoot
$Output=[IO.Path]::GetFullPath($Output)
$null=New-Item -ItemType Directory -Path $Output -Force
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$refs=@('System.dll','System.Core.dll','System.Web.Extensions.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Xaml.dll','WPF/WindowsBase.dll','WPF/PresentationCore.dll','WPF/PresentationFramework.dll') | ForEach-Object {'/reference:'+(Join-Path $framework $_)}
$sources=Get-ChildItem -LiteralPath $src -Filter '*.cs' | ForEach-Object FullName
$sources+=Join-Path $PSScriptRoot 'Tests.cs'
$savedLib=$env:LIB
try {
    $env:LIB=''
    # No administrator manifest: unit/UI tests never change the real network.
    & (Join-Path $framework 'csc.exe') /nologo /target:winexe /main:SLink.Tests /platform:x64 /warn:4 /warnaserror+ "/out:$Output/Tests.exe" "/resource:$src/Main.xaml,Main.xaml" "/resource:$RepoRoot/assets/app.ico,app.ico" @refs @sources
    if($LASTEXITCODE){throw 'Test compilation failed'}
} finally {$env:LIB=$savedLib}
$report=Join-Path $Output 'results.json'
if(Test-Path -LiteralPath $report){Remove-Item -LiteralPath $report}
$process=Start-Process -FilePath (Join-Path $Output 'Tests.exe') -ArgumentList ('--self-test "'+$report+'"') -WindowStyle Hidden -PassThru
try {
    if(-not $process.WaitForExit(60000)){$process.Kill();$null=$process.WaitForExit(2000);throw 'Self-test timed out'}
    $result=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    if($process.ExitCode -or -not $result.ok){throw ('Self-test failed: '+$result.error)}
    $result | ConvertTo-Json -Compress
} finally {$process.Dispose()}
# Use Windows PowerShell 5.1, the production network script host, in a separate process.
& "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'network-probes.Tests.ps1')
if($LASTEXITCODE){throw 'Network probe tests failed'}
