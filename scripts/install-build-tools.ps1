# Install the pinned, official Inno Setup compiler into the ignored .tools directory.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$destination = Join-Path $repo '.tools/inno'
$download = Join-Path $repo '.tools/downloads/innosetup-6.7.3.exe'
$expected = '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732'
$null = New-Item -ItemType Directory -Path (Split-Path $download) -Force
if (-not (Test-Path -LiteralPath $download)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe' -OutFile $download
}
if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $expected) {
    throw 'Inno Setup installer checksum mismatch; remove the cached download and retry.'
}
$process = Start-Process -FilePath $download -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/CURRENTUSER',
    ('/DIR="' + $destination + '"')
) -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode) { throw "Inno Setup installation failed: $($process.ExitCode)" }
Get-Item (Join-Path $destination 'ISCC.exe') | Select-Object FullName
