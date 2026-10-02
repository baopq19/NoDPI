@echo off
setlocal
set "log=%~dp0steam-connectivity.log"

echo ==== %date% %time% ====>> "%log%"
echo NoDPI process:>> "%log%"
tasklist /FI "IMAGENAME eq goodbyedpi.exe" >> "%log%" 2>&1

echo DNS A records for store.steampowered.com:>> "%log%"
powershell.exe -NoProfile -Command "Resolve-DnsName store.steampowered.com -Type A -NoHostsFile | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.IPAddress }" >> "%log%" 2>&1
echo DNS AAAA records for store.steampowered.com:>> "%log%"
powershell.exe -NoProfile -Command "Resolve-DnsName store.steampowered.com -Type AAAA -NoHostsFile | Where-Object { $_.Type -eq 'AAAA' } | ForEach-Object { $_.IPAddress }" >> "%log%" 2>&1

echo HTTPS over IPv4 TCP and HTTP/1.1:>> "%log%"
curl.exe -4 -I --http1.1 --connect-timeout 5 --max-time 12 -sS -o NUL -w "HTTP=%%{http_code} IP=%%{remote_ip} duration=%%{time_total}s error=%%{errormsg}\n" "https://store.steampowered.com/" >> "%log%" 2>&1
echo curl exit code: %errorlevel% >> "%log%"
echo HTTPS over IPv6 TCP and HTTP/1.1:>> "%log%"
curl.exe -6 -I --http1.1 --connect-timeout 5 --max-time 12 -sS -o NUL -w "HTTP=%%{http_code} IP=%%{remote_ip} duration=%%{time_total}s error=%%{errormsg}\n" "https://store.steampowered.com/" >> "%log%" 2>&1
echo curl exit code: %errorlevel% >> "%log%"
echo.>> "%log%"

echo Steam connectivity check saved to:
echo %log%
echo Run this once while Steam Store fails and once after it works again.
echo Keep the browser's exact error message or screenshot too.
if /I "%~1"=="--no-pause" exit /b 0
pause
