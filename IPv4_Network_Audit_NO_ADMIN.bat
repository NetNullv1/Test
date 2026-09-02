@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title NetNull IPv4 Network Audit - USER MODE
color 0A

rem ============================================================
rem NetNull IPv4 Network Audit - Windows 10/11 - NO ADMIN
rem Runs entirely in standard user context.
rem No UAC elevation is requested.
rem ============================================================

set "ROOT=%~dp0"
set "OUT=%ROOT%NetAudit_%COMPUTERNAME%_%RANDOM%"
mkdir "%OUT%" >nul 2>&1

echo.
echo ===============================================================
echo     NetNull IPv4 Network Audit - USER MODE / NO ADMIN
echo ===============================================================
echo.
echo [i] Администратор НЕ требуется.
echo [i] Папка отчёта: "%OUT%"
echo.
echo Что будет собрано:
echo   - IPv4 / маска / шлюз / DNS / MAC / интерфейсы
echo   - внешний IPv4 (если интернет доступен)
echo   - ARP / route / netstat
echo   - поиск устройств в локальной сети
echo   - hostname / ping / MAC
echo   - TCP scan популярных портов
echo   - локальные TCP listeners и соединения
echo   - UDP endpoints
echo   - HTML + CSV + TXT отчёты
echo.
echo Никакого UAC и никакого запроса пароля администратора.
echo.
pause

set "PS1=%TEMP%\nn_audit_%RANDOM%_%RANDOM%.ps1"

> "%PS1%" (
echo $ErrorActionPreference = 'SilentlyContinue'
echo $ProgressPreference = 'SilentlyContinue'
echo $OutDir = [IO.Path]::GetFullPath('%OUT:\=\\%')
echo New-Item -ItemType Directory -Path $OutDir -Force ^| Out-Null
echo.
echo function W([string]$s,[ConsoleColor]$c='Gray'){ Write-Host $s -ForegroundColor $c }
echo function Section([string]$s){ Write-Host ''; Write-Host ('='*78) -ForegroundColor DarkGray; Write-Host ('  '+$s) -ForegroundColor Cyan; Write-Host ('='*78) -ForegroundColor DarkGray }
echo function SaveText([string]$Name,[object]$Data){ $Data ^| Out-File (Join-Path $OutDir $Name) -Encoding UTF8 -Width 500 }
echo function Html([string]$s){ [System.Net.WebUtility]::HtmlEncode($s) }
echo.
echo $start = Get-Date
echo $machine = $env:COMPUTERNAME
echo $user = $env:USERNAME
echo.
echo Section '1. БАЗОВАЯ ИНФОРМАЦИЯ'
echo W ('Компьютер: '+$machine) Green
echo W ('Пользователь: '+$user) Green
echo W ('Запуск: '+$start.ToString('yyyy-MM-dd HH:mm:ss')) DarkGray
echo W 'Режим: обычный пользователь, без UAC' Yellow
echo.
echo $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration ^| Where-Object { $_.IPEnabled -eq $true }
echo $adapterRows = @()
echo foreach($a in $adapters){
echo   $ipv4 = @($a.IPAddress ^| Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
echo   foreach($ip in $ipv4){
echo     $adapterRows += [pscustomobject]@{
echo       Description = $a.Description
echo       IPv4 = $ip
echo       Mask = (@($a.IPSubnet)[0])
echo       Gateway = (@($a.DefaultIPGateway)[0])
echo       DNS = (($a.DNSServerSearchOrder -join ', '))
echo       MAC = $a.MACAddress
echo       DHCP = $a.DHCPEnabled
echo     }
echo   }
echo }
echo if($adapterRows.Count -eq 0){ W 'Активные IPv4 интерфейсы не найдены.' Red } else { $adapterRows ^| Format-Table -AutoSize ^| Out-String ^| Write-Host }
echo $adapterRows ^| Export-Csv (Join-Path $OutDir 'interfaces.csv') -NoTypeInformation -Encoding UTF8
echo.
echo Section '2. ВНЕШНИЙ IPv4'
echo $wan = $null
echo foreach($url in @('https://api.ipify.org','https://ifconfig.me/ip','https://icanhazip.com')){
echo   if(-not $wan){
echo     try{
echo       $x = (Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 4).ToString().Trim()
echo       if($x -match '^\d{1,3}(\.\d{1,3}){3}$'){ $wan=$x }
echo     }catch{}
echo   }
echo }
echo if($wan){ W ('WAN IPv4: '+$wan) Green } else { W 'WAN IPv4 определить не удалось. Интернет/HTTPS может быть ограничен.' Yellow }
echo SaveText 'wan_ipv4.txt' $wan
echo.
echo Section '3. СИСТЕМНЫЕ СЕТЕВЫЕ ДАННЫЕ'
echo W 'Сохраняю ipconfig /all, route print -4, arp -a, netstat...' DarkGray
echo cmd /c 'ipconfig /all' ^| Out-File (Join-Path $OutDir 'ipconfig_all.txt') -Encoding UTF8 -Width 500
echo cmd /c 'route print -4' ^| Out-File (Join-Path $OutDir 'route_ipv4.txt') -Encoding UTF8 -Width 500
echo cmd /c 'arp -a' ^| Out-File (Join-Path $OutDir 'arp.txt') -Encoding UTF8 -Width 500
echo cmd /c 'netstat -ano' ^| Out-File (Join-Path $OutDir 'netstat_ano.txt') -Encoding UTF8 -Width 500
echo.
echo function IpToUInt32([string]$ip){
echo   $b=[Net.IPAddress]::Parse($ip).GetAddressBytes()
echo   [Array]::Reverse($b)
echo   return [BitConverter]::ToUInt32($b,0)
echo }
echo function UInt32ToIp([uint32]$n){
echo   $b=[BitConverter]::GetBytes($n)
echo   [Array]::Reverse($b)
echo   return ([Net.IPAddress]::new($b)).ToString()
echo }
echo function PrefixFromMask([string]$m){
echo   try{
echo     $bits=0
echo     foreach($o in $m.Split('.')){
echo       $v=[int]$o
echo       for($i=7;$i-ge 0;$i--){ if($v -band (1 -shl $i)){ $bits++ } }
echo     }
echo     return $bits
echo   }catch{return 24}
echo }
echo function GetSubnet([string]$ip,[int]$prefix){
echo   $u=IpToUInt32 $ip
echo   if($prefix -eq 0){$mask=[uint32]0}else{$mask=[uint32]::MaxValue -shl (32-$prefix)}
echo   $net=$u -band $mask
echo   $bcast=$net -bor (-bnot $mask)
echo   [pscustomobject]@{Network=$net;Broadcast=$bcast;Prefix=$prefix}
echo }
echo.
echo $private = $adapterRows ^| Where-Object {
echo   $_.IPv4 -match '^10\.' -or
echo   $_.IPv4 -match '^192\.168\.' -or
echo   ($_.IPv4 -match '^172\.(1[6-9]|2\d|3[01])\.')
echo } ^| Select-Object -First 1
echo.
echo if(-not $private){
echo   Section '4. ЛОКАЛЬНАЯ СЕТЬ'
echo   W 'RFC1918 IPv4 не найден. Автоматический LAN sweep пропущен, чтобы случайно не сканировать сеть провайдера.' Yellow
echo   $hosts=@()
echo } else {
echo   $localIp=$private.IPv4
echo   $mask=$private.Mask
echo   $prefix=PrefixFromMask $mask
echo   $gw=$private.Gateway
echo   $sub=GetSubnet $localIp $prefix
echo   $networkIp=UInt32ToIp $sub.Network
echo   $broadcastIp=UInt32ToIp $sub.Broadcast
echo   Section '4. ЛОКАЛЬНАЯ СЕТЬ'
echo   W ('IPv4: '+$localIp) Green
echo   W ('Подсеть: '+$networkIp+'/'+$prefix) Green
echo   W ('Шлюз: '+$gw) Green
echo.
echo   $scanPrefix=$prefix
echo   if($prefix -lt 24){
echo     W ('Подсеть /'+$prefix+' слишком большая для бездумного полного sweep.') Yellow
echo     W ('Для безопасности будет проверен текущий /24 вокруг '+$localIp+'.') Yellow
echo     $scanPrefix=24
echo     $sub=GetSubnet $localIp 24
echo   }
echo   $first=[uint32]($sub.Network+1)
echo   $last=[uint32]($sub.Broadcast-1)
echo   $count=[int64]$last-[int64]$first+1
echo   if($count -gt 1022){$last=$first+1021;$count=1022}
echo   W ('Адресов для проверки: '+$count) Cyan
echo   W 'Ping sweep выполняется параллельно...' DarkGray
echo.
echo   $targets = for($i=$first;$i -le $last;$i++){ UInt32ToIp ([uint32]$i) }
echo   $runspacePool=[RunspaceFactory]::CreateRunspacePool(1,64)
echo   $runspacePool.Open()
echo   $jobs=@()
echo   foreach($t in $targets){
echo     $ps=[PowerShell]::Create()
echo     $ps.RunspacePool=$runspacePool
echo     [void]$ps.AddScript({
echo       param($ip)
echo       $sw=[Diagnostics.Stopwatch]::StartNew()
echo       try{
echo         $p=New-Object Net.NetworkInformation.Ping
echo         $r=$p.Send($ip,350)
echo         $sw.Stop()
echo         if($r.Status -eq 'Success'){
echo           [pscustomobject]@{IP=$ip;Alive=$true;Ping=[int]$r.RoundtripTime}
echo         }else{
echo           [pscustomobject]@{IP=$ip;Alive=$false;Ping=$null}
echo         }
echo       }catch{[pscustomobject]@{IP=$ip;Alive=$false;Ping=$null}}
echo     }).AddArgument($t)
echo     $jobs += [pscustomobject]@{PS=$ps;Handle=$ps.BeginInvoke()}
echo   }
echo   $pingRows=@()
echo   $done=0
echo   foreach($j in $jobs){
echo     $r=$j.PS.EndInvoke($j.Handle)
echo     $j.PS.Dispose()
echo     if($r){$pingRows += $r}
echo     $done++
echo     if(($done %% 32)-eq 0){ Write-Host -NoNewline '.' -ForegroundColor DarkGray }
echo   }
echo   $runspacePool.Close();$runspacePool.Dispose()
echo   Write-Host ''
echo.
echo   Start-Sleep -Milliseconds 400
echo   $arpText = cmd /c 'arp -a'
echo   $arpMap=@{}
echo   foreach($line in $arpText){
echo     if($line -match '^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F-]{17})\s+'){
echo       $arpMap[$matches[1]]=$matches[2].ToUpper()
echo     }
echo   }
echo   $allIps = New-Object System.Collections.Generic.HashSet[string]
echo   foreach($r in $pingRows ^| Where-Object Alive){[void]$allIps.Add($r.IP)}
echo   foreach($k in $arpMap.Keys){
echo     $ku=IpToUInt32 $k
echo     if($ku -ge $first -and $ku -le $last){[void]$allIps.Add($k)}
echo   }
echo   [void]$allIps.Add($localIp)
echo   if($gw){[void]$allIps.Add($gw)}
echo.
echo   $hosts=@()
echo   foreach($ip in $allIps){
echo     $pr=$pingRows ^| Where-Object IP -eq $ip ^| Select-Object -First 1
echo     $name=''
echo     try{$name=[Net.Dns]::GetHostEntry($ip).HostName}catch{}
echo     $role=''
echo     if($ip -eq $localIp){$role='THIS-PC'}
echo     elseif($ip -eq $gw){$role='GATEWAY'}
echo     else{$role='DEVICE'}
echo     $hosts += [pscustomobject]@{
echo       IP=$ip
echo       Hostname=$name
echo       MAC=$arpMap[$ip]
echo       Ping_ms=if($pr){$pr.Ping}else{$null}
echo       Role=$role
echo     }
echo   }
echo   $hosts=$hosts ^| Sort-Object {[version]$_.IP}
echo   W ('Найдено устройств: '+$hosts.Count) Green
echo   $hosts ^| Format-Table IP,Hostname,MAC,Ping_ms,Role -AutoSize ^| Out-String ^| Write-Host
echo   $hosts ^| Export-Csv (Join-Path $OutDir 'hosts.csv') -NoTypeInformation -Encoding UTF8
echo }
echo.
echo Section '5. TCP PORT SCAN'
echo $ports = @(
echo 20,21,22,23,25,53,67,68,69,80,81,88,110,111,119,123,135,137,138,139,143,161,389,443,445,465,500,514,515,548,554,587,631,636,873,993,995,1080,1194,1433,1521,1723,1883,2049,2181,2375,2376,3000,3128,3268,3306,3389,3478,3690,4000,4369,5000,5001,5060,5432,5555,5672,5900,5985,5986,6379,6443,6667,7001,8000,8008,8080,8081,8088,8090,8443,8888,9000,9090,9100,9200,9418,10000,11211,15672,25565,27017,27018,28017
echo )
echo $svc=@{
echo 20='FTP-DATA';21='FTP';22='SSH';23='TELNET';25='SMTP';53='DNS';80='HTTP';81='HTTP-ALT';88='KERBEROS';110='POP3';111='RPCBIND';123='NTP';135='MS-RPC';139='NETBIOS';143='IMAP';161='SNMP';389='LDAP';443='HTTPS';445='SMB';465='SMTPS';500='IKE';515='LPD';548='AFP';554='RTSP';587='SMTP-SUB';631='IPP';636='LDAPS';873='RSYNC';993='IMAPS';995='POP3S';1080='SOCKS';1194='OPENVPN';1433='MSSQL';1521='ORACLE';1723='PPTP';1883='MQTT';2049='NFS';2375='DOCKER';2376='DOCKER-TLS';3000='HTTP-DEV';3128='PROXY';3306='MYSQL';3389='RDP';5432='POSTGRES';5555='ADB';5672='AMQP';5900='VNC';5985='WINRM';5986='WINRM-TLS';6379='REDIS';6443='K8S-API';8000='HTTP-ALT';8080='HTTP-PROXY';8081='HTTP-ALT';8443='HTTPS-ALT';8888='HTTP-ALT';9000='APP';9090='APP';9100='JETDIRECT';9200='ELASTIC';10000='WEBMIN';11211='MEMCACHED';15672='RABBITMQ';25565='MINECRAFT';27017='MONGODB'
echo }
echo $scanRows=@()
echo if($hosts.Count -eq 0){
echo   W 'Нет LAN-хостов для сканирования.' Yellow
echo } else {
echo   $targets=@($hosts.IP)
echo   $pool=[RunspaceFactory]::CreateRunspacePool(1,96);$pool.Open()
echo   $jobs=@()
echo   foreach($ip in $targets){
echo     foreach($port in $ports){
echo       $ps=[PowerShell]::Create();$ps.RunspacePool=$pool
echo       [void]$ps.AddScript({
echo         param($ip,$port)
echo         $c=New-Object Net.Sockets.TcpClient
echo         try{
echo           $ar=$c.BeginConnect($ip,$port,$null,$null)
echo           if($ar.AsyncWaitHandle.WaitOne(220,$false) -and $c.Connected){
echo             try{$c.EndConnect($ar)}catch{}
echo             [pscustomobject]@{IP=$ip;Port=$port;Open=$true}
echo           }
echo         }catch{}finally{$c.Close()}
echo       }).AddArgument($ip).AddArgument($port)
echo       $jobs += [pscustomobject]@{PS=$ps;H=$ps.BeginInvoke()}
echo     }
echo   }
echo   $i=0
echo   foreach($j in $jobs){
echo     $r=$j.PS.EndInvoke($j.H);$j.PS.Dispose()
echo     if($r){$scanRows += $r}
echo     $i++
echo     if(($i %% 250)-eq 0){Write-Host -NoNewline '.' -ForegroundColor DarkGray}
echo   }
echo   $pool.Close();$pool.Dispose()
echo   Write-Host ''
echo   foreach($r in $scanRows){
echo     $name=$svc[[int]$r.Port]
echo     if(-not $name){$name='UNKNOWN'}
echo     Add-Member -InputObject $r -NotePropertyName Service -NotePropertyValue $name
echo   }
echo   if($scanRows.Count){
echo     W ('Открытых портов найдено: '+$scanRows.Count) Green
echo     $scanRows ^| Sort-Object IP,Port ^| Format-Table IP,Port,Service -AutoSize ^| Out-String ^| Write-Host
echo   } else { W 'На выбранном наборе популярных TCP-портов открытых портов не найдено.' Yellow }
echo   $scanRows ^| Export-Csv (Join-Path $OutDir 'open_ports.csv') -NoTypeInformation -Encoding UTF8
echo }
echo.
echo Section '6. ЛОКАЛЬНЫЕ TCP LISTENERS'
echo $listen=@()
echo try{
echo   $listen=Get-NetTCPConnection -State Listen ^| ForEach-Object {
echo     $pname=''
echo     try{$pname=(Get-Process -Id $_.OwningProcess -ErrorAction Stop).ProcessName}catch{$pname='(protected/system)'}
echo     [pscustomobject]@{LocalAddress=$_.LocalAddress;LocalPort=$_.LocalPort;PID=$_.OwningProcess;Process=$pname}
echo   } ^| Sort-Object LocalPort
echo }catch{
echo   $lines=cmd /c 'netstat -ano -p tcp'
echo   foreach($l in $lines){
echo     if($l -match '^\s*TCP\s+(\S+):(\d+)\s+\S+\s+LISTENING\s+(\d+)'){
echo       $listen += [pscustomobject]@{LocalAddress=$matches[1];LocalPort=[int]$matches[2];PID=[int]$matches[3];Process=''}
echo     }
echo   }
echo }
echo $listen ^| Format-Table -AutoSize ^| Out-String ^| Write-Host
echo $listen ^| Export-Csv (Join-Path $OutDir 'local_tcp_listeners.csv') -NoTypeInformation -Encoding UTF8
echo.
echo Section '7. АКТИВНЫЕ TCP CONNECTIONS'
echo $conns=@()
echo try{
echo   $conns=Get-NetTCPConnection ^| Where-Object {$_.State -eq 'Established'} ^| ForEach-Object {
echo     $pname=''
echo     try{$pname=(Get-Process -Id $_.OwningProcess -ErrorAction Stop).ProcessName}catch{$pname='(protected/system)'}
echo     [pscustomobject]@{Local=($_.LocalAddress+':'+$_.LocalPort);Remote=($_.RemoteAddress+':'+$_.RemotePort);State=$_.State;PID=$_.OwningProcess;Process=$pname}
echo   }
echo }catch{}
echo $conns ^| Sort-Object Process,Remote ^| Format-Table -AutoSize ^| Out-String ^| Write-Host
echo $conns ^| Export-Csv (Join-Path $OutDir 'tcp_connections.csv') -NoTypeInformation -Encoding UTF8
echo.
echo Section '8. UDP ENDPOINTS'
echo $udp=@()
echo try{
echo   $udp=Get-NetUDPEndpoint ^| ForEach-Object {
echo     $pname=''
echo     try{$pname=(Get-Process -Id $_.OwningProcess -ErrorAction Stop).ProcessName}catch{$pname='(protected/system)'}
echo     [pscustomobject]@{LocalAddress=$_.LocalAddress;LocalPort=$_.LocalPort;PID=$_.OwningProcess;Process=$pname}
echo   } ^| Sort-Object LocalPort
echo }catch{}
echo $udp ^| Export-Csv (Join-Path $OutDir 'udp_endpoints.csv') -NoTypeInformation -Encoding UTF8
echo W ('UDP endpoints: '+$udp.Count) Green
echo.
echo Section '9. DNS ПРОВЕРКА'
echo $dnsRows=@()
echo foreach($name in @('localhost','dns.google','cloudflare.com','microsoft.com')){
echo   try{
echo     $res=[Net.Dns]::GetHostAddresses($name) ^| Where-Object AddressFamily -eq InterNetwork ^| Select-Object -ExpandProperty IPAddressToString -Unique
echo     $dnsRows += [pscustomobject]@{Name=$name;IPv4=($res -join ', ')}
echo   }catch{
echo     $dnsRows += [pscustomobject]@{Name=$name;IPv4='FAILED'}
echo   }
echo }
echo $dnsRows ^| Format-Table -AutoSize ^| Out-String ^| Write-Host
echo $dnsRows ^| Export-Csv (Join-Path $OutDir 'dns_test.csv') -NoTypeInformation -Encoding UTF8
echo.
echo Section '10. HTML ОТЧЁТ'
echo $css=@'
echo body{background:#0b0f14;color:#d8dee9;font-family:Segoe UI,Arial,sans-serif;margin:0;padding:30px}h1{color:#7ee787;margin-top:0}h2{color:#79c0ff;border-bottom:1px solid #30363d;padding-bottom:8px;margin-top:32px}.card{background:#111820;border:1px solid #26303a;border-radius:12px;padding:18px;margin:14px 0;box-shadow:0 3px 12px #0006}.ok{color:#7ee787}.warn{color:#e3b341}.muted{color:#8b949e}table{width:100%%;border-collapse:collapse;margin-top:10px;font-size:14px}th{background:#161b22;color:#79c0ff;text-align:left}td,th{border:1px solid #30363d;padding:7px 9px}tr:nth-child(even){background:#0f141b}.pill{display:inline-block;padding:3px 8px;border-radius:999px;background:#1f2937;margin-right:6px}.open{color:#7ee787;font-weight:600}code{background:#161b22;border:1px solid #30363d;padding:2px 5px;border-radius:5px}
echo '@
echo function TableHtml($rows){
echo   if(-not $rows -or @($rows).Count -eq 0){return '<div class="muted">Нет данных</div>'}
echo   return ($rows ^| ConvertTo-Html -Fragment)
echo }
echo $adapterHtml=TableHtml $adapterRows
echo $hostsHtml=TableHtml $hosts
echo $portsHtml=TableHtml ($scanRows ^| Sort-Object IP,Port)
echo $listenHtml=TableHtml $listen
echo $connHtml=TableHtml $conns
echo $dnsHtml=TableHtml $dnsRows
echo $elapsed=(Get-Date)-$start
echo $wanText=if($wan){Html $wan}else{'Не определён'}
echo $html=@"
echo <!doctype html><html lang="ru"><head><meta charset="utf-8"><title>NetNull Network Audit</title><style>$css</style></head><body>
echo <h1>NetNull IPv4 Network Audit</h1>
echo <div class="card"><b>Компьютер:</b> $(Html $machine)<br><b>Пользователь:</b> $(Html $user)<br><b>Режим:</b> обычный пользователь, без UAC<br><b>Время:</b> $(Html $start.ToString('yyyy-MM-dd HH:mm:ss'))<br><b>Длительность:</b> $([math]::Round($elapsed.TotalSeconds,1)) сек<br><b>WAN IPv4:</b> <span class="ok">$wanText</span></div>
echo <h2>Интерфейсы</h2><div class="card">$adapterHtml</div>
echo <h2>Устройства LAN</h2><div class="card">$hostsHtml</div>
echo <h2>Открытые TCP-порты</h2><div class="card">$portsHtml</div>
echo <h2>Локальные TCP listeners</h2><div class="card">$listenHtml</div>
echo <h2>Активные TCP connections</h2><div class="card">$connHtml</div>
echo <h2>DNS test</h2><div class="card">$dnsHtml</div>
echo <div class="card muted">Дополнительные файлы: ipconfig_all.txt, route_ipv4.txt, arp.txt, netstat_ano.txt и CSV-таблицы.</div>
echo </body></html>
echo "@
echo $report=Join-Path $OutDir 'REPORT.html'
echo $html ^| Out-File $report -Encoding UTF8
echo W ('Готово: '+$report) Green
echo.
echo Section '11. ДОПОЛНИТЕЛЬНЫЙ DEEP SCAN ОДНОГО ХОСТА'
echo W 'Можно проверить ВСЕ TCP-порты 1-65535 на одном IPv4.' Cyan
echo W 'Это необязательно. Просто Enter = пропустить.' DarkGray
echo $deep=Read-Host 'IPv4'
echo if($deep -match '^\d{1,3}(\.\d{1,3}){3}$'){
echo   W ('Полный TCP scan '+$deep+': 1-65535. Это может занять время...') Yellow
echo   $pool=[RunspaceFactory]::CreateRunspacePool(1,180);$pool.Open()
echo   $jobs=New-Object System.Collections.ArrayList
echo   $open=New-Object System.Collections.ArrayList
echo   $batch=1200
echo   for($base=1;$base -le 65535;$base+=$batch){
echo     $end=[Math]::Min($base+$batch-1,65535)
echo     $jobs.Clear()
echo     for($port=$base;$port -le $end;$port++){
echo       $ps=[PowerShell]::Create();$ps.RunspacePool=$pool
echo       [void]$ps.AddScript({
echo         param($ip,$port)
echo         $c=New-Object Net.Sockets.TcpClient
echo         try{
echo           $ar=$c.BeginConnect($ip,$port,$null,$null)
echo           if($ar.AsyncWaitHandle.WaitOne(160,$false) -and $c.Connected){
echo             try{$c.EndConnect($ar)}catch{}
echo             return $port
echo           }
echo         }catch{}finally{$c.Close()}
echo       }).AddArgument($deep).AddArgument($port)
echo       [void]$jobs.Add([pscustomobject]@{PS=$ps;H=$ps.BeginInvoke();Port=$port})
echo     }
echo     foreach($j in $jobs){
echo       $r=$j.PS.EndInvoke($j.H);$j.PS.Dispose()
echo       if($r){[void]$open.Add([int]$r)}
echo     }
echo     $pct=[math]::Round(($end/65535)*100,1)
echo     Write-Host ("`r  "+$pct+"%%  ["+$base+"-"+$end+"]   Open: "+$open.Count+"        ") -NoNewline -ForegroundColor DarkGray
echo   }
echo   Write-Host ''
echo   $pool.Close();$pool.Dispose()
echo   $deepRows=@($open ^| Sort-Object -Unique ^| ForEach-Object {[pscustomobject]@{IP=$deep;Port=$_;Service=$svc[[int]$_]}})
echo   $deepRows ^| Export-Csv (Join-Path $OutDir ('deep_scan_'+($deep -replace '\.','_')+'.csv')) -NoTypeInformation -Encoding UTF8
echo   if($deepRows.Count){$deepRows ^| Format-Table -AutoSize ^| Out-String ^| Write-Host}else{W 'Открытых TCP портов не найдено.' Yellow}
echo }
echo.
echo Section 'ГОТОВО'
echo W ('Результаты: '+$OutDir) Green
echo W 'Открываю HTML-отчёт и папку...' DarkGray
echo Start-Process (Join-Path $OutDir 'REPORT.html')
echo Start-Process explorer.exe $OutDir
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "ERR=%ERRORLEVEL%"
del "%PS1%" >nul 2>&1

echo.
if not "%ERR%"=="0" (
    color 0C
    echo [!] PowerShell завершился с кодом %ERR%.
    echo [!] Частичные результаты всё равно могут лежать в:
    echo     "%OUT%"
) else (
    color 0A
    echo [OK] Аудит завершён.
    echo [OK] "%OUT%"
)
echo.
pause
exit /b %ERR%
