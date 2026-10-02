@echo off
setlocal
set "_arch=x86"
if /I "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "_arch=x86_64"
if defined PROCESSOR_ARCHITEW6432 set "_arch=x86_64"

set "_exe=%~dp0%_arch%\goodbyedpi.exe"
set "_list=%~dp0hosts.txt"
if not exist "%_exe%" (
    echo Cannot find "%_exe%".
    echo Keep this script beside the x86 and x86_64 folders.
    pause
    exit /b 1
)
if not exist "%_list%" (
    echo Cannot find "%_list%".
    pause
    exit /b 1
)

tasklist /FI "IMAGENAME eq goodbyedpi.exe" /NH 2>NUL | find /I "goodbyedpi.exe" >NUL
if not errorlevel 1 (
    echo Another GoodbyeDPI or NoDPI process is already running.
    echo Close it before starting this profile.
    pause
    exit /b 1
)

echo NoDPI: focused TCP profile with Google DNS redirection.
echo Leave this window open while using NoDPI.
"%_exe%" -8 --dns-addr 8.8.8.8 --dnsv6-addr 2001:4860:4860::8888 --blacklist "%_list%"
if errorlevel 1 pause
