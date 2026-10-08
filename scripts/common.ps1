$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot
$SourceRoot = Join-Path $RepoRoot 'src/SLink'
$FrameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$Compiler = Join-Path $FrameworkRoot 'csc.exe'
if (-not (Test-Path -LiteralPath $Compiler)) {
    throw 'SLink requires Windows x64 with .NET Framework 4.8.'
}
$FrameworkReferences = @(
    'System.dll', 'System.Core.dll', 'System.Web.Extensions.dll',
    'System.Drawing.dll', 'System.Windows.Forms.dll', 'System.Xaml.dll',
    'WPF/WindowsBase.dll', 'WPF/PresentationCore.dll', 'WPF/PresentationFramework.dll'
) | ForEach-Object { '/reference:' + (Join-Path $FrameworkRoot $_) }
$VersionSource = Get-Content -LiteralPath (Join-Path $SourceRoot 'Version.cs') -Raw
if ($VersionSource -notmatch 'const string Version = "(\d+\.\d+\.\d+)"') {
    throw 'Version.cs must define a three-part release version.'
}
$AppVersion = $Matches[1]

function Assert-BundledDependencies {
    $manifest = Get-Content (Join-Path $RepoRoot 'third_party/dependencies.json') -Raw | ConvertFrom-Json
    foreach ($file in $manifest.files) {
        $path = Join-Path $RepoRoot ('third_party/windows-x64/' + $file.name)
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) {
            throw "Bundled dependency checksum mismatch: $($file.name)"
        }
    }
}
