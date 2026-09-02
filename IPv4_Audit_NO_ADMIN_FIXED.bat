@echo off
setlocal EnableExtensions
chcp 65001 >nul
title IPv4 Network Audit - NO ADMIN - FIXED
color 0A

set "OUT=%~dp0Network_Audit_%COMPUTERNAME%"
if not exist "%OUT%" mkdir "%OUT%"

echo ============================================================
echo   IPv4 NETWORK AUDIT - NO ADMIN
echo ============================================================
echo [*] Output: %OUT%
echo [*] Starting...
echo.

rem Raw reports FIRST, so folder is never mysteriously empty.
ipconfig /all > "%OUT%\01_ipconfig_all.txt" 2>&1
route print -4 > "%OUT%\02_routes_ipv4.txt" 2>&1
arp -a > "%OUT%\03_arp.txt" 2>&1
netstat -ano > "%OUT%\04_netstat_ano.txt" 2>&1
getmac /v /fo csv > "%OUT%\05_adapters.csv" 2>&1
nslookup google.com > "%OUT%\06_dns_test.txt" 2>&1

set "PS=%TEMP%\net_audit_fixed_%RANDOM%.ps1"
> "%PS%" echo $ErrorActionPreference='Continue'
>>"%PS%" echo $out='%OUT:\=\\%'
>>"%PS%" echo function H($s,$c='Gray'){Write-Host $s -ForegroundColor $c}
>>"%PS%" echo function IsPrivate([string]$ip){return ($ip -match '^10\.' -or $ip -match '^192\.168\.' -or $ip -match '^172\.(1[6-9]^|2[0-9]^|3[01])\.')}
>>"%PS%" echo H '=== IPv4 NETWORK AUDIT ===' Cyan
>>"%PS%" echo H ('Computer: '+$env:COMPUTERNAME) Green
>>"%PS%" echo H ('User: '+$env:USERNAME) Green
>>"%PS%" echo $cfg=Get-CimInstance Win32_NetworkAdapterConfiguration ^| Where-Object {$_.IPEnabled}
>>"%PS%" echo $rows=@()
>>"%PS%" echo foreach($a in $cfg){foreach($ip in @($a.IPAddress)){if($ip -match '^\d{1,3}(\.\d{1,3}){3}$'){$rows+=[pscustomobject]@{Adapter=$a.Description;IPv4=$ip;Mask=@($a.IPSubnet)[0];Gateway=@($a.DefaultIPGateway)[0];DNS=($a.DNSServerSearchOrder -join ', ');MAC=$a.MACAddress;DHCP=$a.DHCPEnabled}}}}
>>"%PS%" echo $rows ^| Export-Csv (Join-Path $out '07_interfaces.csv') -NoTypeInformation -Encoding UTF8
>>"%PS%" echo $rows ^| Format-Table -AutoSize
>>"%PS%" echo $wan=''
>>"%PS%" echo try{$wan=(Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 5).ToString().Trim()}catch{}
>>"%PS%" echo if($wan){$wan ^| Set-Content (Join-Path $out '08_wan_ipv4.txt');H ('WAN IPv4: '+$wan) Yellow}
>>"%PS%" echo $lan=$rows ^| Where-Object {IsPrivate $_.IPv4} ^| Select-Object -First 1
>>"%PS%" echo $hosts=@()
>>"%PS%" echo if($lan){
>>"%PS%" echo   $parts=$lan.IPv4.Split('.');$base=$parts[0]+'.'+$parts[1]+'.'+$parts[2]+'.'
>>"%PS%" echo   H ('LAN sweep: '+$base+'1-254') Cyan
>>"%PS%" echo   $pool=[RunspaceFactory]::CreateRunspacePool(1,64);$pool.Open();$jobs=@()
>>"%PS%" echo   1..254 ^| ForEach-Object {
>>"%PS%" echo     $ip=$base+$_;$ps=[PowerShell]::Create();$ps.RunspacePool=$pool
>>"%PS%" echo     [void]$ps.AddScript({param($ip);try{$p=New-Object Net.NetworkInformation.Ping;$r=$p.Send($ip,300);if($r.Status -eq 'Success'){[pscustomobject]@{IP=$ip;Ping=[int]$r.RoundtripTime}}}catch{}}).AddArgument($ip)
>>"%PS%" echo     $jobs+=[pscustomobject]@{P=$ps;H=$ps.BeginInvoke()}
>>"%PS%" echo   }
>>"%PS%" echo   foreach($j in $jobs){$r=$j.P.EndInvoke($j.H);$j.P.Dispose();if($r){$hosts+=$r}}
>>"%PS%" echo   $pool.Close();$pool.Dispose()
>>"%PS%" echo   Start-Sleep -Milliseconds 300
>>"%PS%" echo   $arp=@{};arp -a ^| ForEach-Object {if($_ -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F-]{17})'){$arp[$matches[1]]=$matches[2]}}
>>"%PS%" echo   foreach($h in $hosts){$n='';try{$n=[Net.Dns]::GetHostEntry($h.IP).HostName}catch{};Add-Member -InputObject $h -NotePropertyName Hostname -NotePropertyValue $n;Add-Member -InputObject $h -NotePropertyName MAC -NotePropertyValue $arp[$h.IP]}
>>"%PS%" echo   $hosts ^| Sort-Object {[version]$_.IP} ^| Export-Csv (Join-Path $out '09_hosts.csv') -NoTypeInformation -Encoding UTF8
>>"%PS%" echo   H ('Alive hosts: '+$hosts.Count) Green
>>"%PS%" echo   $hosts ^| Sort-Object {[version]$_.IP} ^| Format-Table -AutoSize
>>"%PS%" echo }
>>"%PS%" echo $ports=21,22,23,25,53,80,110,135,139,143,443,445,554,587,631,993,995,1433,1883,3000,3306,3389,5000,5432,5555,5900,5985,5986,6379,8000,8080,8081,8443,8888,9000,9090,9100,9200,10000,25565,27017
>>"%PS%" echo $open=@()
>>"%PS%" echo if($hosts.Count){
>>"%PS%" echo   H 'Scanning common TCP ports...' Cyan
>>"%PS%" echo   $pool=[RunspaceFactory]::CreateRunspacePool(1,96);$pool.Open();$jobs=@()
>>"%PS%" echo   foreach($h in $hosts){foreach($port in $ports){$ps=[PowerShell]::Create();$ps.RunspacePool=$pool;[void]$ps.AddScript({param($ip,$port);$c=New-Object Net.Sockets.TcpClient;try{$a=$c.BeginConnect($ip,$port,$null,$null);if($a.AsyncWaitHandle.WaitOne(200,$false)-and$c.Connected){[pscustomobject]@{IP=$ip;Port=$port}}}catch{}finally{$c.Close()}}).AddArgument($h.IP).AddArgument($port);$jobs+=[pscustomobject]@{P=$ps;H=$ps.BeginInvoke()}}}
>>"%PS%" echo   foreach($j in $jobs){$r=$j.P.EndInvoke($j.H);$j.P.Dispose();if($r){$open+=$r}}
>>"%PS%" echo   $pool.Close();$pool.Dispose()
>>"%PS%" echo }
>>"%PS%" echo $open ^| Sort-Object IP,Port ^| Export-Csv (Join-Path $out '10_open_ports.csv') -NoTypeInformation -Encoding UTF8
>>"%PS%" echo H ('Open ports: '+$open.Count) Green
>>"%PS%" echo $open ^| Format-Table -AutoSize
>>"%PS%" echo $listeners=@();try{$listeners=Get-NetTCPConnection -State Listen ^| Select-Object LocalAddress,LocalPort,OwningProcess}catch{}
>>"%PS%" echo $listeners ^| Export-Csv (Join-Path $out '11_local_listeners.csv') -NoTypeInformation -Encoding UTF8
>>"%PS%" echo $connections=@();try{$connections=Get-NetTCPConnection ^| Where-Object State -eq Established ^| Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,State,OwningProcess}catch{}
>>"%PS%" echo $connections ^| Export-Csv (Join-Path $out '12_connections.csv') -NoTypeInformation -Encoding UTF8
>>"%PS%" echo $summary=@()
>>"%PS%" echo $summary+='IPv4 NETWORK AUDIT'
>>"%PS%" echo $summary+='Computer: '+$env:COMPUTERNAME
>>"%PS%" echo $summary+='User: '+$env:USERNAME
>>"%PS%" echo $summary+='WAN: '+$wan
>>"%PS%" echo if($lan){$summary+='LAN: '+$lan.IPv4;$summary+='Gateway: '+$lan.Gateway}
>>"%PS%" echo $summary+='Alive hosts: '+$hosts.Count
>>"%PS%" echo $summary+='Open common TCP ports: '+$open.Count
>>"%PS%" echo $summary ^| Set-Content (Join-Path $out '00_SUMMARY.txt') -Encoding UTF8
>>"%PS%" echo $style='body{font-family:Segoe UI;background:#0d1117;color:#c9d1d9;padding:25px}h1,h2{color:#58a6ff}table{border-collapse:collapse;width:100%%;margin-bottom:25px}td,th{border:1px solid #30363d;padding:7px}th{background:#161b22;color:#7ee787}tr:nth-child(even){background:#11161d}.box{padding:15px;border:1px solid #30363d;background:#161b22;border-radius:10px;margin-bottom:20px}'
>>"%PS%" echo $body='<h1>IPv4 Network Audit</h1><div class="box"><b>Computer:</b> '+$env:COMPUTERNAME+'<br><b>User:</b> '+$env:USERNAME+'<br><b>WAN:</b> '+$wan+'<br><b>Alive hosts:</b> '+$hosts.Count+'<br><b>Open ports:</b> '+$open.Count+'</div>'
>>"%PS%" echo $body+='<h2>Interfaces</h2>'+($rows ^| ConvertTo-Html -Fragment)
>>"%PS%" echo $body+='<h2>LAN Hosts</h2>'+($hosts ^| Sort-Object {[version]$_.IP} ^| ConvertTo-Html -Fragment)
>>"%PS%" echo $body+='<h2>Open TCP Ports</h2>'+($open ^| Sort-Object IP,Port ^| ConvertTo-Html -Fragment)
>>"%PS%" echo ConvertTo-Html -Head ('<meta charset="utf-8"><style>'+$style+'</style>') -Body $body ^| Set-Content (Join-Path $out 'REPORT.html') -Encoding UTF8
>>"%PS%" echo H ('DONE: '+$out) Green

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS%" > "%OUT%\13_scan_console.txt" 2>&1
set "RC=%ERRORLEVEL%"
del "%PS%" >nul 2>&1

echo.
echo ============================================================
if "%RC%"=="0" (
  echo [OK] ГОТОВО. Файлы точно должны быть здесь:
) else (
  echo [!] PowerShell вернул код %RC%.
  echo [!] Но базовые TXT отчёты уже сохранены здесь:
)
echo %OUT%
echo ============================================================
echo.
type "%OUT%\00_SUMMARY.txt" 2>nul
echo.
if exist "%OUT%\REPORT.html" start "" "%OUT%\REPORT.html"
start "" explorer.exe "%OUT%"
echo.
echo Если опять что-то упало - открой 13_scan_console.txt.
pause
