param(
  [ValidateSet('Inspect','Check','Repair','Start','Stop','Resume','TestTunnel')][string]$Action='Inspect',
  [Parameter(Mandatory=$true)][string]$DataDir,
  [Parameter(Mandatory=$true)][string]$Engine,
  [switch]$Takeover,
  [string]$PreviousGuid='',
  [int]$ProxyPort=7890,
  [switch]$FastExit,
  [string]$ResultPath=''
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$ProgressPreference='SilentlyContinue'
$DataDir=[IO.Path]::GetFullPath($DataDir)
$Engine=[IO.Path]::GetFullPath($Engine)
. (Join-Path $PSScriptRoot 'network-probes.ps1')
$statePath=Join-Path $DataDir 'session.json'
$progressPath=Join-Path $DataDir 'progress.json'
$runDir=Join-Path $DataDir 'relay'
$script:session=$null
$script:created=$false
$script:mutex=$null
$script:locked=$false
function Write-Json($Path,$Object){
  $tmp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
  try {
    [IO.File]::WriteAllText($tmp,($Object | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    if(Test-Path -LiteralPath $Path){[IO.File]::Replace($tmp,$Path,[NullString]::Value)}
    else{[IO.File]::Move($tmp,$Path)}
  } finally {
    if(Test-Path -LiteralPath $tmp){[IO.File]::Delete($tmp)}
  }
}
function Step($Text){
  $entry=@{message=$Text;time=[DateTime]::Now.ToString('HH:mm:ss');utc=[DateTime]::UtcNow.ToString('o')}
  Write-Json $progressPath $entry
  $log=Join-Path $DataDir 'network.log'
  if((Test-Path $log) -and (Get-Item $log).Length -gt 262144){Move-Item -LiteralPath $log -Destination ($log+'.previous') -Force}
  [IO.File]::AppendAllText($log,($entry | ConvertTo-Json -Compress)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}
function Check-Cancel {
  if($Action -in @('Start','Resume','Repair') -and (Test-Path -LiteralPath (Join-Path $DataDir 'cancel.flag'))){throw '启动已取消，正在清理。'}
}
function Init-WinRT {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $null=[Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]
  $null=[Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]
  $null=[Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]
}
function Profiles { @([Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles()) }
function Manager($Profile) { [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($Profile) }
function Profile-Guid($Guid){
  $p=Profiles | Where-Object {$_.NetworkAdapter -and [guid]$_.NetworkAdapter.NetworkAdapterId -eq [guid]$Guid} | Sort-Object @{Expression={if($_.GetNetworkConnectivityLevel().ToString() -eq 'None'){1}else{0}}} | Select-Object -First 1
  if(-not $p){throw '原来的网络连接已消失，无法恢复热点。'}
  return $p
}
function Default-Profile {
  $p=[Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
  if(-not $p){$p=Profiles | Where-Object {$_.IsWlanConnectionProfile} | Select-Object -First 1}
  if(-not $p){throw '未找到可用网络，请先连接 Wi-Fi 或网线。'}
  return $p
}
function Await-Hotspot($Operation){
  $method=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
  $task=$method.MakeGenericMethod([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult]).Invoke($null,@($Operation))
  if(-not $task.Wait($(if($FastExit){4000}else{45000}))){throw 'Windows 热点操作超时。'}
  if($task.Result.Status.ToString() -ne 'Success'){throw ('Windows 热点操作失败：'+$task.Result.Status+' '+$task.Result.AdditionalErrorMessage)}
}
function Stop-Hotspot($Manager){
  if($Manager.TetheringOperationalState.ToString() -ne 'Off'){Await-Hotspot ($Manager.StopTetheringAsync())}
}
function Start-Hotspot($Manager){
  if($Manager.TetheringOperationalState.ToString() -ne 'On'){Await-Hotspot ($Manager.StartTetheringAsync())}
  for($i=0;$i -lt 20 -and $Manager.TetheringOperationalState.ToString() -eq 'InTransition';$i++){Start-Sleep -Milliseconds 300}
  if($Manager.TetheringOperationalState.ToString() -ne 'On'){throw 'Windows 热点未进入开启状态。'}
}
function Public-Share {
  $share=New-Object -ComObject HNetCfg.HNetShare
  foreach($conn in $share.EnumEveryConnection()){
    $cfg=$share.INetSharingConfigurationForINetConnection($conn)
    if($cfg.SharingEnabled -and $cfg.SharingConnectionType -eq 0){
      $p=$share.NetConnectionProps($conn)
      return @{name=$p.Name;guid=$p.Guid}
    }
  }
  return $null
}
function Preferred {
  $r=Find-NetRoute -RemoteIPAddress 1.1.1.1 | Where-Object {$_.PSObject.Properties['DestinationPrefix']} | Select-Object -First 1
  if(-not $r){throw '无法确认电脑当前上网路由。'}
  return ($r.InterfaceIndex.ToString()+'|'+$r.NextHop+'|'+$r.DestinationPrefix)
}
function Proxy-State {
  $p=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  return (@{enabled=$p.ProxyEnable;server=$p.ProxyServer;pac=$p.AutoConfigURL} | ConvertTo-Json -Compress)
}
function Load-Session {
  if(Test-Path -LiteralPath $statePath){
    $saved=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not $saved.PSObject.Properties['ready']){$saved | Add-Member NoteProperty ready $false}
    if(-not $saved.PSObject.Properties['dnsOwner']){$saved | Add-Member NoteProperty dnsOwner ''}
    return $saved
  }
  return $null
}
function Uses-Config([string]$CommandLine,[string]$ConfigPath){
  if(-not $CommandLine){return $false}
  $path=[regex]::Escape($ConfigPath.Replace('/','\'))
  # Match a whole argument, never config.yml.old or a substring of another path.
  $argument='"'+$path+'"'
  if($ConfigPath -notmatch '\s'){$argument+='|'+$path}
  return [regex]::IsMatch($CommandLine.Replace('/','\'),('(?:^|\s)(?:'+$argument+')(?=\s|$)'),[Text.RegularExpressions.RegexOptions]::IgnoreCase)
}
function Owned-Process($Session){
  if(-not $Session){return $null}
  $enginePath=[IO.Path]::GetFullPath($Session.engine)
  $configPath=Join-Path ([IO.Path]::GetFullPath($Session.runDir)) 'config.yml'
  if($Session.pid -eq 0 -and $Session.journalTicks){
    $orphans=@(Get-CimInstance Win32_Process -Filter "Name='hev-socks5-tunnel.exe'" | Where-Object {$_.ExecutablePath -eq $enginePath -and (Uses-Config $_.CommandLine $configPath) -and $_.CreationDate.ToUniversalTime().Ticks -ge [long]$Session.journalTicks})
    if($orphans.Count -eq 1){return $orphans[0]}
    return $null
  }
  $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$Session.pid) -ErrorAction SilentlyContinue
  if($p -and $p.ExecutablePath -eq $enginePath -and (Uses-Config $p.CommandLine $configPath) -and $p.CreationDate.ToUniversalTime().Ticks.ToString() -eq $Session.created){return $p}
  return $null
}
function Protect-QobuzDns($Session){
  # Journal the unique owner before creating a rule, including crash recovery.
  if(-not $Session.dnsOwner){$Session.dnsOwner='SLink '+[guid]::NewGuid().ToString();Write-Json $statePath $Session}
  $ours=@(Get-DnsClientNrptRule | Where-Object {$_.Comment -eq $Session.dnsOwner})
  foreach($rule in $ours){if(@($rule.Namespace).Count -ne 1 -or @($rule.Namespace)[0] -ne '.qobuz.com' -or (@($rule.NameServers) -join ',') -ne '198.19.255.2'){Fail-Probe 'dns-rule-changed' 'SLink DNS 规则被其他程序修改，未覆盖。'}}
  if(-not $ours.Count){$null=Add-DnsClientNrptRule -Namespace '.qobuz.com' -NameServers '198.19.255.2' -Comment $Session.dnsOwner}
  Clear-DnsClientCache
}
function Reconcile-StopSession($Session){
  # Explicit Stop only: recover a stale journal against one exact engine/config pair.
  if(-not $Session -or (Owned-Process $Session)){return $Session}
  $config=Join-Path ([IO.Path]::GetFullPath($Session.runDir)) 'config.yml'
  $candidates=@(Get-CimInstance Win32_Process -Filter "Name='hev-socks5-tunnel.exe'" | Where-Object {$_.ExecutablePath -eq [IO.Path]::GetFullPath($Session.engine) -and (Uses-Config $_.CommandLine $config) -and $_.CreationDate.ToUniversalTime().Ticks -ge [long]$Session.journalTicks})
  if(-not $candidates.Count){return $Session}
  if($candidates.Count -ne 1){throw '发现多个使用同一配置的代理，未自动清理。'}
  $a=Get-NetAdapter -Name SLink -ErrorAction Stop
  if(-not (Get-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress '198.19.255.1' -ErrorAction SilentlyContinue)){throw '无法确认恢复网卡身份，已保留连接。'}
  $share=Public-Share
  if($share -and [guid]$share.guid -ne [guid]$a.InterfaceGuid){throw '热点来源已改变，未自动清理。'}
  $Session.pid=$candidates[0].ProcessId
  $Session.created=$candidates[0].CreationDate.ToUniversalTime().Ticks.ToString()
  $Session.adapterGuid=$a.InterfaceGuid.ToString()
  $Session.ready=$false
  Write-Json $statePath $Session
  return $Session
}
function Restore-QobuzDns($Session){
  if(-not $Session.dnsOwner){return}
  foreach($rule in @(Get-DnsClientNrptRule | Where-Object {$_.Comment -eq $Session.dnsOwner})){
    if(@($rule.Namespace).Count -ne 1 -or @($rule.Namespace)[0] -ne '.qobuz.com' -or (@($rule.NameServers) -join ',') -ne '198.19.255.2'){throw 'SLink DNS 规则被其他程序修改，已保留恢复记录。'}
    Remove-DnsClientNrptRule -Name $rule.Name -Force
  }
  Clear-DnsClientCache
}
function Check-Adapter($Session){
  if(-not (Owned-Process $Session)){Fail-Probe 'engine-exited' '代理进程已退出，请重新连接。'}
  $a=Get-NetAdapter -Name SLink -ErrorAction Stop
  if([guid]$a.InterfaceGuid -ne [guid]$Session.adapterGuid -or $a.Status -ne 'Up'){Fail-Probe 'adapter' '专用网卡身份或状态已变化。'}
  $ip=Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Where-Object {$_.IPAddress -eq '198.19.255.1' -and $_.PrefixLength -eq 16 -and $_.AddressState -eq 'Preferred'}
  if(-not $ip){Fail-Probe 'adapter' '专用网卡 IPv4 地址尚未就绪。'}
  if(-not (Get-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix '198.19.0.0/16' -ErrorAction SilentlyContinue)){Fail-Probe 'adapter' '映射地址路由缺失。'}
  if((Preferred) -ne $Session.preferred -or (Proxy-State) -ne $Session.proxyState){Fail-Probe 'host-network' '电脑网络已变化，请停止后重新连接。'}
  return $a
}
function Configure-Adapter($Guid){
  $last='Windows 尚未注册网卡配置接口。'
  for($attempt=0;$attempt -lt 20;$attempt++){
    Check-Cancel
    try{
      $a=Get-NetAdapter -Name SLink -ErrorAction Stop
      if([guid]$a.InterfaceGuid -ne [guid]$Guid){throw '专用网卡身份已变化。'}
      $ip=Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction Stop | Where-Object {$_.IPAddress -eq '198.19.255.1' -and $_.AddressState -eq 'Preferred'} | Select-Object -First 1
      if(-not $ip){throw '网卡 IPv4 尚未就绪。'}
      if($ip.PrefixLength -ne 16){$ip | Set-NetIPAddress -PrefixLength 16 -ErrorAction Stop}
      # Adapter Up and IP creation precede the DNS/CIM interface becoming usable.
      Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses @('198.19.255.2') -ErrorAction Stop
      Set-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -AutomaticMetric Disabled -InterfaceMetric 5000 -ErrorAction Stop
      $dns=Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction Stop
      $net=Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction Stop
      $ip=Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Where-Object {$_.IPAddress -eq '198.19.255.1' -and $_.PrefixLength -eq 16 -and $_.AddressState -eq 'Preferred'}
      if($ip -and (@($dns.ServerAddresses) -join ',') -eq '198.19.255.2' -and $net.InterfaceMetric -eq 5000){return $a}
      $last='Windows 尚未提交网卡配置。'
    }catch{$last=$_.Exception.Message}
    Start-Sleep -Milliseconds 400
  }
  throw ('专用网卡配置未就绪：'+$last)
}
function Check-Connection($Session,[bool]$Hotspot){
  $a=Check-Adapter $Session
  $records=Test-MappedDns '198.19.255.2'
  if($Hotspot){
    if((Manager (Profile-Guid $a.InterfaceGuid)).TetheringOperationalState.ToString() -ne 'On'){Fail-Probe 'hotspot-off' '热点尚未开启。'}
    $share=Public-Share
    if($share -and [guid]$share.guid -ne [guid]$a.InterfaceGuid){Fail-Probe 'share-changed' '热点正在共享其他网卡。'}
    # Inspect the actual DHCP gateway's DNS, not just the engine's resolver.
    $gateway=Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -eq '192.168.137.1'} | Select-Object -First 1
    if(-not $gateway){Fail-Probe 'hotspot-gateway' '热点网关尚未就绪。'}
    $hotspotRecords=Test-MappedDns $gateway.IPAddress
    foreach($name in $records.Keys){if($hotspotRecords[$name] -ne $records[$name]){Fail-Probe 'hotspot-dns' ('热点 DNS 与代理网卡不一致：'+$name)}}
  }
  try{Test-TunnelForwarding $records}catch{
    $failure=$_.Exception
    if($failure.Data['code'] -in @('https','qconnect')){
      if(Compare-Upstream ([string]$failure.Data['code']) $ProxyPort){Fail-Probe 'tunnel-forwarding' ($failure.Message+'；直连本机代理检测通过，专用转发正在复查。')}
      else{Fail-Probe 'upstream' ($failure.Message+'；本机代理访问同一服务也失败，请检查代理节点。')}
    }
    throw
  }
  $null=Check-Adapter $Session
}
function Read-Status {
  $session=Load-Session
  $owned=Owned-Process $session
  $adapter=Get-NetAdapter -Name SLink -ErrorAction SilentlyContinue
  $share=$null; $warning=''
  try{$share=Public-Share}catch{$warning='请以管理员身份运行，以读取和管理热点共享。'}
  $profile=Default-Profile
  if($share){try{$profile=Profile-Guid $share.guid}catch{}}
  $m=Manager $profile
  $config=$m.GetCurrentAccessPointConfiguration()
  $devices=@()
  if($m.TetheringOperationalState.ToString() -eq 'On'){
    foreach($client in $m.GetTetheringClients()){
      $names=@($client.HostNames | ForEach-Object {$_.DisplayName})
      $devices+=@{mac=$client.MacAddress;names=$names}
    }
  }
  $managed=[bool]($owned -and $adapter -and $session.ready -and [guid]$adapter.InterfaceGuid -eq [guid]$session.adapterGuid -and (($share -and [guid]$share.guid -eq [guid]$adapter.InterfaceGuid) -or (-not $share -and $session.hotspotStarted)))
  $sources=@()
  $allAdapters=@(Get-NetAdapter)
  foreach($p in (Profiles | Where-Object {$_.NetworkAdapter -and $_.GetNetworkConnectivityLevel().ToString() -ne 'None'})){
    $a=$allAdapters | Where-Object {[guid]$_.InterfaceGuid -eq [guid]$p.NetworkAdapter.NetworkAdapterId} | Select-Object -First 1
    if($a){$sources+=@{name=$a.Name+' ('+$p.ProfileName+')';guid=$a.InterfaceGuid.ToString()}}
  }
  $routeOk=$null
  if($owned -and $session){$routeOk=((Preferred) -eq $session.preferred -and (Proxy-State) -eq $session.proxyState)}
  return @{ok=$true;hotspot=$m.TetheringOperationalState.ToString();ssid=$config.Ssid;password=$config.Passphrase;
    devices=$devices;clients=[int]$m.ClientCount;managed=$managed;owned=[bool]$owned;adapter=[bool]$adapter;
    pid=$(if($session){$session.pid}else{0});adapterGuid=$(if($adapter){$adapter.InterfaceGuid.ToString()}else{''});
    source=$(if($share){$share.name}elseif($managed){'SLink（启动时设置）'}else{''});sourceVerified=[bool]$share;sources=$sources;warning=$warning;routeOk=$routeOk;recovery=[bool]($session -and -not $owned)}
}
function Repair-Connection($Session){
  Check-Cancel
  # Preserve the live engine and its fake-IP map; never restart it on a probe timeout.
  $a=Check-Adapter $Session
  $share=Public-Share
  if($share -and [guid]$share.guid -ne [guid]$a.InterfaceGuid){Fail-Probe 'share-changed' '热点共享已被其他程序修改，未覆盖。'}
  $null=Test-MappedDns '198.19.255.2'
  Step '正在修复热点 DNS 与连接'
  Protect-QobuzDns $Session
  Check-Cancel
  Start-Hotspot (Manager (Profile-Guid $a.InterfaceGuid))
  Check-Connection $Session $true
  $Session.ready=$true;Write-Json $statePath $Session
  return @{ok=$true;message='连接已恢复；原代理会话已保留。';pid=$Session.pid;adapterGuid=$Session.adapterGuid;checkedAt=[DateTime]::UtcNow.ToString('o')}
}
function Restore($Session){
  $errors=@()
  try{Restore-QobuzDns $Session}catch{$errors+=$_.Exception.Message}
  if($FastExit){
    # Terminate only the journaled relay before potentially slow Windows hotspot calls.
    $capturedManager=$null
    try{
      $a=Get-NetAdapter -Name SLink -ErrorAction SilentlyContinue
      if($a -and $Session.adapterGuid -and [guid]$a.InterfaceGuid -eq [guid]$Session.adapterGuid){
        if($Session.hotspotStarted){$capturedManager=Manager (Profile-Guid $a.InterfaceGuid)}
        if($Session.routeAdded){Get-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object {$_.RouteMetric -eq 5000 -and $_.NextHop -eq '0.0.0.0'} | Remove-NetRoute -Confirm:$false}
      }
    }catch{$errors+=$_.Exception.Message}
    try{$owned=Owned-Process $Session;if($owned){Stop-Process -Id $owned.ProcessId -Force;Wait-Process -Id $owned.ProcessId -Timeout 3 -ErrorAction SilentlyContinue}}catch{$errors+=$_.Exception.Message}
    if($capturedManager){try{Stop-Hotspot $capturedManager}catch{$errors+=$_.Exception.Message}}
  }
  try{
    $share=Public-Share
    $adapter=Get-NetAdapter -Name SLink -ErrorAction SilentlyContinue
    if($adapter -and $Session.adapterGuid -and [guid]$adapter.InterfaceGuid -eq [guid]$Session.adapterGuid -and (($share -and [guid]$share.guid -eq [guid]$adapter.InterfaceGuid) -or (-not $share -and $Session.hotspotStarted))){Stop-Hotspot (Manager (Profile-Guid $adapter.InterfaceGuid))}
  }catch{$errors+=$_.Exception.Message}
  try{
    $owned=Owned-Process $Session
    $adapter=Get-NetAdapter -Name SLink -ErrorAction SilentlyContinue
    if($Session.adapterGuid -and $adapter -and [guid]$adapter.InterfaceGuid -eq [guid]$Session.adapterGuid -and $Session.routeAdded){
      Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object {$_.RouteMetric -eq 5000 -and $_.NextHop -eq '0.0.0.0'} | Remove-NetRoute -Confirm:$false
    }
    if($owned){Stop-Process -Id $owned.ProcessId -Force;Wait-Process -Id $owned.ProcessId -Timeout 5 -ErrorAction SilentlyContinue}
  }catch{$errors+=$_.Exception.Message}
  if($Session.restoreHotspot){
    try{
      $currentShare=Public-Share
      $m=Manager (Profile-Guid $Session.previousGuid)
      if($m.TetheringOperationalState.ToString() -eq 'On' -and $currentShare -and [guid]$currentShare.guid -ne [guid]$Session.previousGuid){
        throw '热点已被其他应用修改，未覆盖它；请检查 Windows 热点。'
      }
      Start-Hotspot $m
    }catch{$errors+=$_.Exception.Message}
  }
  if($errors.Count){throw ($errors -join '；')}
  if(Owned-Process $Session){throw '专用代理尚未退出，已保留恢复记录。'}
  if($Session.adapterGuid){
    for($i=0;$i -lt 15;$i++){
      $a=Get-NetAdapter -Name SLink -ErrorAction SilentlyContinue
      if(-not $a -or [guid]$a.InterfaceGuid -ne [guid]$Session.adapterGuid){break}
      Start-Sleep -Milliseconds 200
    }
    if($a -and [guid]$a.InterfaceGuid -eq [guid]$Session.adapterGuid){throw 'Windows 尚未释放专用网卡，已保留恢复记录。'}
  }
  if(Test-Path -LiteralPath $statePath){Remove-Item -LiteralPath $statePath}
}
try {
  $null=New-Item -ItemType Directory -Path $DataDir -Force
  Init-WinRT
  if($Action -eq 'Inspect'){$result=Read-Status}
  elseif($Action -eq 'Check'){
    $script:mutex=New-Object Threading.Mutex($false,'Local\SLink.Network')
    try{$script:locked=$script:mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$script:locked=$true}
    if(-not $script:locked){Fail-Probe 'busy' '连接正在调整，稍后重新检测。'}
    $session=Load-Session
    if(-not $session -or -not $session.ready){throw '连接尚未完成验证，请重新连接。'}
    Check-Connection $session $true
    $result=@{ok=$true;pid=$session.pid;adapterGuid=$session.adapterGuid;checkedAt=[DateTime]::UtcNow.ToString('o')}
  }
  else {
    $script:mutex=New-Object Threading.Mutex($false,'Local\SLink.Network')
    try{$script:locked=$script:mutex.WaitOne($(if($FastExit){4000}elseif($Action -eq 'Stop'){20000}else{0}))}catch [Threading.AbandonedMutexException]{$script:locked=$true}
    if(-not $script:locked){throw '另一个连接操作正在进行，请稍后重试。'}
    $session=Load-Session
    if($Action -eq 'Stop'){
      Step '正在停止音响连接并恢复原热点'
      for($cleanupAttempt=0;$session -and $cleanupAttempt -lt 3;$cleanupAttempt++){
        $session=Reconcile-StopSession $session;Restore $session
        $session=Load-Session
      }
      if($session){throw '连接恢复记录仍然存在，已保留记录，请重试清理。'}
      if(Test-Path -LiteralPath (Join-Path $DataDir 'cancel.flag')){Remove-Item -LiteralPath (Join-Path $DataDir 'cancel.flag')}
      Step '已停止；电脑原有代理继续运行'
      $result=@{ok=$true;message='音响连接已停止，原有网络已保留。'}
    }elseif($Action -eq 'Repair'){
      $result=Repair-Connection $session
      Step $result.message
    }elseif($Action -eq 'Resume'){
      Check-Cancel
      if(-not (Owned-Process $session)){throw '代理进程已结束，请先清理并重新连接。'}
      $a=Get-NetAdapter -Name SLink -ErrorAction Stop
      if([guid]$a.InterfaceGuid -ne [guid]$session.adapterGuid){throw '网卡身份不一致，未更改网络。'}
      if((Preferred) -ne $session.preferred -or (Proxy-State) -ne $session.proxyState){throw '电脑网络已变化，请先停止再重新连接。'}
      $m=Manager (Profile-Guid $a.InterfaceGuid)
      if($m.TetheringOperationalState.ToString() -ne 'Off'){throw '热点状态已变化，请刷新后重试。'}
      Step '正在恢复音响热点'
      $session.ready=$false;Write-Json $statePath $session
      Protect-QobuzDns $session
      Check-Connection $session $false
      Start-Hotspot $m
      Check-Cancel
      Check-Connection $session $true
      $session.ready=$true;Write-Json $statePath $session
      Step '音响热点已就绪，请连接 JBL'
      $result=@{ok=$true;message='热点已恢复。';pid=$session.pid;adapterGuid=$session.adapterGuid;checkedAt=[DateTime]::UtcNow.ToString('o')}
    }else{
      Check-Cancel
      if(Owned-Process $session){throw '音响代理已在运行。若热点被系统关闭，请先停止再连接。'}
      if($session){throw '发现上次连接的恢复记录，请先点击“清理并恢复”。'}
      if(Get-NetAdapter -Name SLink -ErrorAction SilentlyContinue){throw '存在同名 SLink 网卡，已停止操作以避免影响其他连接。'}
      $before=Preferred
      $proxyBefore=Proxy-State
      $previous=Default-Profile
      $oldManager=Manager $previous
      $wasOn=$oldManager.TetheringOperationalState.ToString() -eq 'On'
      if($wasOn -and $Action -ne 'TestTunnel'){
        if(-not $Takeover){throw '已有热点正在使用，请确认切换后再连接。'}
        $share=Public-Share
        if($share){$previous=Profile-Guid $share.guid}
        elseif($PreviousGuid){$previous=Profile-Guid $PreviousGuid}
        else{throw 'Windows 未报告现有热点来源。请选择当前共享的网卡，或先在 Windows 设置中关闭热点。'}
        $oldManager=Manager $previous
      }
      Step '正在创建音响专用代理网卡'
      Check-Cancel
      $script:session=@{pid=0;engine=$Engine;runDir=$runDir;created='';journalTicks=[DateTime]::UtcNow.Ticks.ToString();preferred=$before;proxyState=$proxyBefore;previousGuid=$previous.NetworkAdapter.NetworkAdapterId.ToString();restoreHotspot=$false;ready=$false;dnsOwner=''}
      Write-Json $statePath $script:session
      $script:created=$true
      $null=New-Item -ItemType Directory -Path $runDir -Force
      if($ProxyPort -lt 1 -or $ProxyPort -gt 65535){throw '代理端口无效。'}
      $config="tunnel:`n  name: SLink`n  mtu: 1500`n  ipv4: 198.19.255.1`nsocks5:`n  address: 127.0.0.1`n  port: $ProxyPort`n  udp: udp`nmapdns:`n  address: 198.19.255.2`n  port: 53`n  network: 198.19.0.0`n  netmask: 255.255.0.0`n  cache-size: 4096`nmisc:`n  log-level: warn`n  max-session-count: 1024`n"
      [IO.File]::WriteAllText((Join-Path $runDir 'config.yml'),$config,[Text.UTF8Encoding]::new($false))
      $p=Start-Process -FilePath $Engine -WorkingDirectory (Split-Path $Engine) -ArgumentList ('"'+(Join-Path $runDir 'config.yml')+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runDir 'stdout.log') -RedirectStandardError (Join-Path $runDir 'stderr.log')
      $proc=Get-CimInstance Win32_Process -Filter ('ProcessId='+$p.Id)
      $script:session.pid=$p.Id
      $script:session.created=$proc.CreationDate.ToUniversalTime().Ticks.ToString()
      Write-Json $statePath $script:session
      Check-Cancel
      $adapter=$null
      for($i=0;$i -lt 30;$i++){
        if($p.HasExited){throw '代理引擎启动失败，请查看诊断日志。'}
        $adapter=Get-NetAdapter -Name SLink -ErrorAction SilentlyContinue
        if($adapter -and $adapter.Status -eq 'Up' -and (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -eq '198.19.255.1' -and $_.AddressState -eq 'Preferred'})){break}
        Start-Sleep -Milliseconds 400
        Check-Cancel
      }
      if(-not $adapter -or $adapter.Status -ne 'Up'){throw '代理网卡未就绪，请检查管理员权限和 Wintun 驱动。'}
      $script:session.adapterGuid=$adapter.InterfaceGuid.ToString()
      $script:session.routeAdded=$true
      Write-Json $statePath $script:session
      if((Preferred) -ne $before -or (Proxy-State) -ne $proxyBefore){throw '检测到电脑网络发生变化，正在撤销本次启动。'}
      Step '正在配置专用网卡地址、DNS 与路由'
      $adapter=Configure-Adapter $script:session.adapterGuid
      Step '正在验证专用转发链路'
      Check-Cancel
      Test-HttpProbe 'upstream' @('--proxy',"socks5h://127.0.0.1:$ProxyPort",'--head','--connect-timeout','3','--max-time','6','-sS','-o','NUL','-w','%{http_code}|%{time_total}|%{size_download}','https://www.qobuz.com/')
      $null=New-NetRoute -DestinationPrefix '0.0.0.0/0' -InterfaceIndex $adapter.ifIndex -NextHop '0.0.0.0' -RouteMetric 5000 -PolicyStore ActiveStore
      if((Preferred) -ne $before){throw '备用路由影响电脑上网，正在撤销。'}
      Check-Connection $script:session $false
      if($Action -eq 'TestTunnel'){
        Restore $script:session
        $script:created=$false
        $result=@{ok=$true;message='代理网卡、转发链路及路由保护检查通过；未切换热点。'}
      }else{
        Check-Cancel
        Step '正在将热点连接到音响代理网卡'
        Protect-QobuzDns $script:session
        $script:session.restoreHotspot=$wasOn
        Write-Json $statePath $script:session
        if($wasOn){Stop-Hotspot $oldManager}
        $profile=$null
        for($i=0;$i -lt 20;$i++){
          try{$profile=Profile-Guid $adapter.InterfaceGuid;break}catch{Start-Sleep -Milliseconds 400}
        }
        if(-not $profile){throw 'Windows 尚未注册代理网卡的网络配置。'}
        $script:session.hotspotStarted=$true
        Write-Json $statePath $script:session
        Start-Hotspot (Manager $profile)
        Check-Cancel
        $share=Public-Share
        if($share -and [guid]$share.guid -ne [guid]$adapter.InterfaceGuid){throw '热点未共享正确的网卡，正在恢复原设置。'}
        if((Preferred) -ne $before -or (Proxy-State) -ne $proxyBefore){throw '电脑原有网络保护检查未通过，正在恢复。'}
        Step '正在核验热点 DNS 与 Qobuz Connect'
        Check-Connection $script:session $true
        $script:session.ready=$true;Write-Json $statePath $script:session
        Step '音响热点已就绪，请连接 JBL'
        $result=@{ok=$true;message='热点已就绪，请让 JBL 和控制手机连接该热点。';pid=$script:session.pid;adapterGuid=$script:session.adapterGuid;checkedAt=[DateTime]::UtcNow.ToString('o')}
      }
    }
  }
}catch {
  $message=$_.Exception.Message
  $failureCode=[string]$_.Exception.Data['code']
  if(-not $failureCode){$failureCode='system'}
  Write-Json (Join-Path $DataDir 'last-network-error.json') @{action=$Action;message=$message;position=$_.InvocationInfo.PositionMessage;stack=$_.ScriptStackTrace;utc=[DateTime]::UtcNow.ToString('o')}
  if($script:created){
    try{Restore $script:session;$message+=' 已撤销本次启动。'}catch{$message+=' 恢复未完成：'+$_.Exception.Message}
  }
  $result=@{ok=$false;error=$message;code=$failureCode;checkedAt=[DateTime]::UtcNow.ToString('o')}
  if($session){$result.pid=$session.pid;$result.adapterGuid=$session.adapterGuid}
  if($Action -notin @('Inspect','Check')){Step $message}
}finally{
  if($script:locked){$script:mutex.ReleaseMutex()}
  if($script:mutex){$script:mutex.Dispose()}
}
if($Action -in @('Check','Repair')){
  $result.details=@($script:probeDetails.ToArray())
  if($result.code -ne 'busy'){
    Write-Json (Join-Path $DataDir 'health.json') $result
    $history=Join-Path $DataDir 'health-history.jsonl'
    if((Test-Path $history) -and (Get-Item $history).Length -gt 1048576){Move-Item -LiteralPath $history -Destination ($history+'.previous') -Force}
    [IO.File]::AppendAllText($history,($result | ConvertTo-Json -Depth 10 -Compress)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
  }
}
if($ResultPath){Write-Json $ResultPath $result}
else{$result | ConvertTo-Json -Depth 12 -Compress}
