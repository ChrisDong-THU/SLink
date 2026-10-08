# Install the pinned, official Inno Setup compiler into the ignored .tools directory.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$destination = Join-Path $repo '.tools/inno'
$download = Join-Path $repo '.tools/downloads/innosetup-7.1.0-x64.exe'
$expected = '0362a383ed217d4c4239b5933866dd96d3eb2102737da92f80f6057a4b40df2f'
$null = New-Item -ItemType Directory -Path (Split-Path $download) -Force
if (-not (Test-Path -LiteralPath $download)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/jrsoftware/issrc/releases/download/is-7_1_0/innosetup-7.1.0-x64.exe' -OutFile $download
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
