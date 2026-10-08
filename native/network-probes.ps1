# Read-only probes. Use UDP directly: the Windows resolver can return cached
# answers from another interface even when the tunnel itself is working.
$script:probeDetails=New-Object 'Collections.Generic.List[object]'
function Fail-Probe([string]$Code,[string]$Message) {
  $ex=New-Object InvalidOperationException($Message)
  $ex.Data['code']=$Code
  throw $ex
}
function Read-DnsUInt16($Bytes,[int]$Offset) {
  if($Offset -lt 0 -or $Offset+2 -gt $Bytes.Length){throw 'DNS response is truncated'}
  return ([int]$Bytes[$Offset]*256+[int]$Bytes[$Offset+1])
}
function Skip-DnsName($Bytes,[int]$Offset) {
  for($n=0;$n -lt 128;$n++){
    if($Offset -ge $Bytes.Length){throw 'DNS name is truncated'}
    $size=[int]$Bytes[$Offset]
    if($size -eq 0){return ($Offset+1)}
    if(($size -band 192) -eq 192){if($Offset+1 -ge $Bytes.Length){throw 'DNS pointer is truncated'};return ($Offset+2)}
    if($size -gt 63){throw 'Invalid DNS label'}
    $Offset+=$size+1
  }
  throw 'Invalid DNS name'
}
function Convert-DnsAnswer([byte[]]$Bytes,[int]$Id) {
  if($Bytes.Length -lt 12 -or (Read-DnsUInt16 $Bytes 0) -ne $Id -or -not($Bytes[2] -band 128) -or ($Bytes[2] -band 2)){throw 'Invalid or truncated DNS response'}
  $offset=12
  for($i=0;$i -lt (Read-DnsUInt16 $Bytes 4);$i++){
    $offset=(Skip-DnsName $Bytes $offset)+4
    if($offset -gt $Bytes.Length){throw 'DNS question is truncated'}
  }
  $addresses=@()
  for($i=0;$i -lt (Read-DnsUInt16 $Bytes 6);$i++){
    $offset=Skip-DnsName $Bytes $offset
    $kind=Read-DnsUInt16 $Bytes $offset
    $length=Read-DnsUInt16 $Bytes ($offset+8)
    $offset+=10
    if($offset+$length -gt $Bytes.Length){throw 'DNS record is truncated'}
    if(($kind -eq 1 -and $length -eq 4) -or ($kind -eq 28 -and $length -eq 16)){
      $ip=[Net.IPAddress]::new([byte[]]$Bytes[$offset..($offset+$length-1)])
      $addresses+=@{type=$kind;address=$ip.ToString()}
    }
    $offset+=$length
  }
  return @{rcode=([int]$Bytes[3] -band 15);addresses=@($addresses)}
}
function Query-Dns([string]$Server,[string]$HostName,[int]$Type=1) {
  $id=Get-Random -Minimum 1 -Maximum 65535
  $query=New-Object 'Collections.Generic.List[byte]'
  $query.AddRange([byte[]]@(($id -shr 8),($id -band 255),1,0,0,1,0,0,0,0,0,0))
  foreach($label in $HostName.Split('.')){$b=[Text.Encoding]::ASCII.GetBytes($label);$query.Add([byte]$b.Length);$query.AddRange($b)}
  $query.AddRange([byte[]]@(0,0,$Type,0,1))
  for($attempt=1;$attempt -le 2;$attempt++){
    $udp=New-Object Net.Sockets.UdpClient
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try{
      $udp.Client.ReceiveTimeout=2000
      $udp.Connect($Server,53)
      $null=$udp.Send($query.ToArray(),$query.Count)
      $endpoint=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0)
      $answer=Convert-DnsAnswer ($udp.Receive([ref]$endpoint)) $id
      $script:probeDetails.Add(@{stage='dns';server=$Server;host=$HostName;type=$Type;attempt=$attempt;ms=$watch.ElapsedMilliseconds;rcode=$answer.rcode;addresses=$answer.addresses})
      return $answer
    }catch{
      $script:probeDetails.Add(@{stage='dns';server=$Server;host=$HostName;type=$Type;attempt=$attempt;ms=$watch.ElapsedMilliseconds;error='no-valid-response'})
      if($attempt -eq 2){Fail-Probe $(if($Server -eq '198.19.255.2'){'engine-dns'}else{'hotspot-dns'}) ('DNS 未响应：'+$Server+' / '+$HostName+' / '+$(if($Type -eq 28){'AAAA'}else{'A'}))}
    }finally{$udp.Dispose()}
  }
}
function Test-MappedDns([string]$Server) {
  $records=@{}
  foreach($name in @('www.qobuz.com','qws-eu-prod.qobuz.com')){
    $a=Query-Dns $Server $name 1
    $ips=@($a.addresses | Where-Object {$_.type -eq 1} | ForEach-Object {$_.address})
    if($a.rcode -ne 0 -or $ips.Count -ne 1 -or $ips[0] -notmatch '^198\.19\.(?!255\.)\d+\.\d+$'){
      Fail-Probe $(if($Server -eq '198.19.255.2'){'engine-dns'}else{'hotspot-dns'}) ('DNS 未进入专用网卡：'+$name+'，服务器 '+$Server)
    }
    $aaaa=Query-Dns $Server $name 28
    if($aaaa.rcode -notin @(0,3) -or @($aaaa.addresses).Count -ne 0){Fail-Probe $(if($Server -eq '198.19.255.2'){'engine-dns'}else{'hotspot-dns'}) ('DNS 回退到了原网络：'+$name+'，服务器 '+$Server)}
    $records[$name]=$ips[0]
  }
  return $records
}
function Invoke-ProbeCurl([string[]]$Arguments) {
  $saved=$ErrorActionPreference
  $stderr=[IO.Path]::GetTempFileName()
  try{
    $ErrorActionPreference='Continue'
    $code=& curl.exe @Arguments 2>$stderr
    $exitCode=$LASTEXITCODE
    $parts=(($code -join '').Trim()) -split '\|'
    $detail=([IO.File]::ReadAllText($stderr)).Trim()
    if($detail.Length -gt 400){$detail=$detail.Substring(0,400)}
    return @{status=$parts[0];exit=$exitCode;seconds=$(if($parts.Length -gt 1){$parts[1]}else{''});bytes=$(if($parts.Length -gt 2){$parts[2]}else{''});detail=$detail}
  }finally{$ErrorActionPreference=$saved;[IO.File]::Delete($stderr)}
}
function Test-HttpProbe([string]$Stage,[string[]]$Arguments,[bool]$WebSocket=$false) {
  for($attempt=1;$attempt -le 2;$attempt++){
    $result=Invoke-ProbeCurl $Arguments
    $script:probeDetails.Add(@{stage=$Stage;attempt=$attempt;http=$result.status;curlExit=$result.exit;seconds=$result.seconds;bytes=$result.bytes;detail=$result.detail})
    $ok=if($WebSocket){$result.status -eq '101' -and $result.exit -in @(0,28)}else{$result.exit -eq 0 -and $result.status -match '^[23][0-9][0-9]$'}
    if($ok){return}
    # Retry transport failures once. HTTP auth/server errors remain visible.
    if($result.exit -notin @(7,28,35,52,55,56)){break}
  }
  $reason=switch([int]$result.exit){28{'请求超时'}7{'无法建立连接'}35{'TLS 握手失败'}52{'服务器未返回响应'}55{'发送中断'}56{'接收中断'}60{'证书验证失败'}0{'服务器响应异常'}default{'传输失败'}}
  $label=switch($Stage){'https'{'HTTPS 转发'}'qconnect'{'Qobuz Connect 握手'}'upstream'{'上游代理'}default{$Stage}}
  Fail-Probe $Stage ($label+'：'+$reason+'（HTTP '+$result.status+'，curl '+$result.exit+'）')
}
function Compare-Upstream([string]$Stage,[int]$Port) {
  $probeArgs=@('--proxy',('socks5h://127.0.0.1:'+$Port),'--connect-timeout','3','--max-time','6','-sS','-o','NUL','-w','%{http_code}|%{time_total}|%{size_download}')
  if($Stage -eq 'qconnect'){$probeArgs+=@('--http1.1','-H','Connection: Upgrade','-H','Upgrade: websocket','-H','Sec-WebSocket-Version: 13','-H','Sec-WebSocket-Key: c2xpbmstcHJvYmUtMDAwMQ==','https://qws-eu-prod.qobuz.com/ws')}
  else{$probeArgs+=@('--head','https://www.qobuz.com/')}
  $r=Invoke-ProbeCurl $probeArgs
  $script:probeDetails.Add(@{stage=('upstream-'+$Stage);http=$r.status;curlExit=$r.exit;seconds=$r.seconds;detail=$r.detail})
  if($Stage -eq 'qconnect'){return ($r.status -eq '101' -and $r.exit -in @(0,28))}
  return ($r.exit -eq 0 -and $r.status -match '^[23][0-9][0-9]$')
}
function Test-TunnelForwarding($Records) {
  $base=@('--noproxy','*','--interface','198.19.255.1','--connect-timeout','3','--max-time','6','-sS','-o','NUL','-w','%{http_code}|%{time_total}|%{size_download}')
  Test-HttpProbe 'https' ($base+@('--head','--resolve',('www.qobuz.com:443:'+$Records['www.qobuz.com']),'https://www.qobuz.com/'))
  Test-HttpProbe 'qconnect' ($base+@('--http1.1','--resolve',('qws-eu-prod.qobuz.com:443:'+$Records['qws-eu-prod.qobuz.com']),'-H','Connection: Upgrade','-H','Upgrade: websocket','-H','Sec-WebSocket-Version: 13','-H','Sec-WebSocket-Key: c2xpbmstcHJvYmUtMDAwMQ==','https://qws-eu-prod.qobuz.com/ws')) $true
  # An upgraded socket remains open; curl's bounded read then exits with 28.
}
