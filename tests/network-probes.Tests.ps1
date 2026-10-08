$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'native\network-probes.ps1')
$script:passed=0
function Assert($Value,$Message){if(-not $Value){throw $Message};$script:passed++}
function Must-Fail([scriptblock]$Block,$Message){$failed=$false;try{& $Block}catch{$failed=$true};Assert $failed $Message}
# Compressed answer, one A record, no question: exercises byte parsing without DNS/network access.
$packet=[byte[]]@(18,52,129,128,0,0,0,1,0,0,0,0,192,12,0,1,0,1,0,0,0,1,0,4,198,19,0,12)
$a=Convert-DnsAnswer $packet 4660
Assert ($a.rcode -eq 0 -and $a.addresses[0].address -eq '198.19.0.12') 'IPv4 answer parsing'
Must-Fail {Convert-DnsAnswer $packet 99} 'Reject unrelated transaction'
Must-Fail {Convert-DnsAnswer ([byte[]]$packet[0..24]) 4660} 'Reject truncated record'
$empty=[byte[]]@(18,52,129,128,0,0,0,0,0,0,0,0)
Assert (@((Convert-DnsAnswer $empty 4660).addresses).Count -eq 0) 'Accept explicit NODATA'
Must-Fail {Convert-DnsAnswer ([byte[]]@(18,52,129,128,0,1,0,0,0,0,0,0,0)) 4660} 'Reject truncated empty-answer question'
function Query-Dns($Server,$HostName,$Type){
  if($Type -eq 1){return @{rcode=0;addresses=@(@{type=1;address=$script:testAddress})}}
  return @{rcode=0;addresses=$script:testAAAA}
}
$script:testAddress='198.19.0.12';$script:testAAAA=@()
Assert ((Test-MappedDns 'test')['qws-eu-prod.qobuz.com'] -eq '198.19.0.12') 'Mapped DNS accepted'
$script:testAddress='93.179.102.140'
Must-Fail {Test-MappedDns 'test'} 'Reject leaked real IPv4'
$script:testAddress='198.19.0.12';$script:testAAAA=@(@{type=28;address='2a03:2880:f12a:83:face:b00c:0:25de'})
Must-Fail {Test-MappedDns 'test'} 'Reject observed IPv6 DNS fallback'
$script:curlResults=New-Object 'Collections.Generic.Queue[object]'
function Invoke-ProbeCurl($Arguments){return $script:curlResults.Dequeue()}
$records=@{'www.qobuz.com'='198.19.0.12';'qws-eu-prod.qobuz.com'='198.19.0.13'}
$script:curlResults.Enqueue(@{status='302';exit=0});$script:curlResults.Enqueue(@{status='101';exit=28})
Test-TunnelForwarding $records;Assert $true 'Bounded WebSocket upgrade succeeds'
$script:curlResults.Enqueue(@{status='302';exit=0});$script:curlResults.Enqueue(@{status='400';exit=0})
Must-Fail {Test-TunnelForwarding $records} 'Website alone does not validate Connect'
$script:curlResults.Enqueue(@{status='302';exit=28});$script:curlResults.Enqueue(@{status='302';exit=28})
try{Test-TunnelForwarding $records;throw 'Expected timeout'}catch{Assert ($_.Exception.Message -match 'curl 28' -and $_.Exception.Data['code'] -eq 'https') '302 with timeout remains a transport failure and records real cause'}
$script:curlResults.Enqueue(@{status='000';exit=28});$script:curlResults.Enqueue(@{status='302';exit=0});$script:curlResults.Enqueue(@{status='101';exit=28})
Test-TunnelForwarding $records;Assert ($script:curlResults.Count -eq 0) 'Transient HTTPS timeout retries without restarting relay'
$script:curlResults.Enqueue(@{status='302';exit=0});$script:curlResults.Enqueue(@{status='401';exit=0})
Must-Fail {Test-TunnelForwarding $records} 'Reject WebSocket auth failure without retries'
$script:curlResults.Enqueue(@{status='302';exit=0});$script:curlResults.Enqueue(@{status='101';exit=56});$script:curlResults.Enqueue(@{status='101';exit=56})
Must-Fail {Test-TunnelForwarding $records} 'An aborted upgraded connection is not healthy'
$script:curlResults.Enqueue(@{status='302';exit=0})
Assert (Compare-Upstream 'https' 7890) 'Upstream reference accepts complete redirect response'
$script:curlResults.Enqueue(@{status='101';exit=28})
Assert (Compare-Upstream 'qconnect' 7890) 'Upstream reference checks the same WebSocket service'
$script:curlResults.Enqueue(@{status='000';exit=7})
Assert (-not (Compare-Upstream 'https' 7890)) 'Unavailable proxy distinguished from tunnel failure'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path $PSScriptRoot) 'native\network.ps1'),[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'Network script parses'
$definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-Json'},$true)
Invoke-Expression $definition.Extent.Text
$testFile=Join-Path ([IO.Path]::GetTempPath()) ('slink-atomic-'+[guid]::NewGuid().ToString('N')+'.json')
try{Write-Json $testFile @{pid=1};Write-Json $testFile @{pid=2};Assert ((Get-Content $testFile -Raw | ConvertFrom-Json).pid -eq 2) 'Atomic journal replacement works in Windows PowerShell 5.1'}finally{if(Test-Path $testFile){Remove-Item -LiteralPath $testFile}}
$definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Configure-Adapter'},$true)
Invoke-Expression $definition.Extent.Text
$script:adapterGuid=[guid]'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$script:configureAttempts=0
function Check-Cancel {}
function Start-Sleep {}
function Get-NetAdapter {[pscustomobject]@{InterfaceGuid=$script:adapterGuid;ifIndex=42}}
function Get-NetIPAddress {[pscustomobject]@{IPAddress='198.19.255.1';PrefixLength=16;AddressState='Preferred'}}
function Set-DnsClientServerAddress {$script:configureAttempts++;if($script:configureAttempts -lt 3){throw 'Element not found'}}
function Set-NetIPInterface {}
function Get-DnsClientServerAddress {[pscustomobject]@{ServerAddresses=@('198.19.255.2')}}
function Get-NetIPInterface {[pscustomobject]@{InterfaceMetric=5000}}
$configured=Configure-Adapter $script:adapterGuid
Assert ($configured.ifIndex -eq 42 -and $script:configureAttempts -eq 3) 'DNS interface registration race is retried and read back'
$script:configureAttempts=0
Must-Fail {Configure-Adapter ([guid]'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')} 'Reject replaced adapter'
Assert ($script:configureAttempts -eq 0) 'Do not mutate a different adapter'
$definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Repair-Connection'},$true)
Invoke-Expression $definition.Extent.Text
$script:repairEvents=New-Object 'Collections.Generic.List[string]'
$session=[pscustomobject]@{pid=10;adapterGuid=$script:adapterGuid.ToString();ready=$true}
function Check-Adapter { [pscustomobject]@{InterfaceGuid=$script:adapterGuid} }
function Public-Share { @{guid=$script:shareGuid} }
function Test-MappedDns {if($script:brokenEngine){throw 'engine-dns'};@{}}
function Step {}
function Protect-QobuzDns {$script:repairEvents.Add('dns')}
function Profile-Guid { 'profile' }
function Manager { 'manager' }
function Start-Hotspot {$script:repairEvents.Add('ensure-hotspot')}
function Check-Connection {$script:repairEvents.Add('verify')}
function Write-Json {$script:repairEvents.Add('journal')}
function Stop-Process {throw 'repair must not stop relay'}
function Stop-Hotspot {throw 'repair must not stop hotspot'}
$script:shareGuid=$script:adapterGuid;$script:brokenEngine=$false
$result=Repair-Connection $session
Assert ($result.ok -and $result.pid -eq 10 -and ($script:repairEvents -join ',') -eq 'dns,ensure-hotspot,verify,journal') 'Repair preserves relay, verifies before writing success'
$script:repairEvents.Clear();$script:shareGuid=[guid]'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
Must-Fail {Repair-Connection $session} 'Do not take over a changed hotspot'
Assert ($script:repairEvents.Count -eq 0) 'No mutations on changed hotspot'
$script:shareGuid=$script:adapterGuid;$script:brokenEngine=$true
Must-Fail {Repair-Connection $session} 'A dead engine DNS requires explicit restart'
Assert ($script:repairEvents.Count -eq 0) 'Do not churn DNS when engine is unresponsive'
$definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Reconcile-StopSession'},$true)
Invoke-Expression $definition.Extent.Text
$definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Uses-Config'},$true)
Invoke-Expression $definition.Extent.Text
Assert (Uses-Config '"C:\SLink\engine.exe" "C:\SLink\relay\config.yml"' 'C:\SLink\relay\config.yml') 'Accept exact quoted config argument'
Assert (Uses-Config 'engine.exe C:/SLink/relay/config.yml' 'C:\SLink\relay\config.yml') 'Accept exact unquoted config argument'
Assert (Uses-Config 'engine.exe "C:\My SLink\config.yml"' 'C:\My SLink\config.yml') 'Accept config path containing spaces'
Assert (-not (Uses-Config 'engine.exe "C:\SLink\relay\config.yml.old"' 'C:\SLink\relay\config.yml')) 'Reject config suffix collision'
Assert (-not (Uses-Config 'engine.exe C:\My SLink\config.yml' 'C:\My SLink\config.yml')) 'Reject unquoted path split into multiple arguments'
function Owned-Process { $null }
$now=[DateTime]::UtcNow
$script:processes=@([pscustomobject]@{ProcessId=99;ExecutablePath='C:\SLink\hev-socks5-tunnel.exe';CommandLine='"C:\SLink\hev-socks5-tunnel.exe" "C:\SLink\relay\config.yml"';CreationDate=$now})
function Get-CimInstance {$script:processes}
$session=[pscustomobject]@{pid=10;created='old';engine='C:\SLink\hev-socks5-tunnel.exe';runDir='C:\SLink\relay';journalTicks=$now.AddDays(-1).Ticks.ToString();adapterGuid='old';ready=$true}
$script:shareGuid=$script:adapterGuid
$result=Reconcile-StopSession $session
Assert ($result.pid -eq 99 -and $result.created -eq $now.Ticks.ToString() -and -not $result.ready) 'Explicit stop recovers exact engine config from stale PID'
$script:processes+=@($script:processes[0])
Must-Fail {Reconcile-StopSession $session} 'Ambiguous relay is not adopted'
$script:processes=@([pscustomobject]@{ProcessId=77;ExecutablePath='C:\Other\hev-socks5-tunnel.exe';CommandLine='other';CreationDate=$now})
$result=Reconcile-StopSession $session
Assert ($result.pid -eq 99) 'Unrelated engine never replaces ownership'
@{ok=$true;passed=$script:passed} | ConvertTo-Json -Compress
