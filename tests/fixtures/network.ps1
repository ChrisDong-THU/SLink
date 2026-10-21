param([string]$Action,[string]$DataDir,[string]$Engine,[int]$ProxyPort,[string]$ResultPath,[switch]$Takeover,[string]$PreviousGuid,[switch]$FastExit)
$ErrorActionPreference='Stop'
# Test-only backend: never imports production networking code or changes networking.
$fixture=Get-Content -LiteralPath (Join-Path $DataDir 'native-fixture.json') -Raw | ConvertFrom-Json
[IO.File]::AppendAllText((Join-Path $DataDir 'native-calls.txt'),$Action+[Environment]::NewLine)
if($Action -eq 'Inspect'){Start-Sleep -Milliseconds 350;$result=$fixture.state}
elseif($Action -eq 'Check'){$result=$fixture.health}
else{$result=$fixture.result}
[IO.File]::WriteAllText($ResultPath,($result | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
