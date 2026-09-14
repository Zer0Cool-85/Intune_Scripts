@echo off
setlocal
set "OfficeWiFiPS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "OfficeWiFiPS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%OfficeWiFiPS%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Install-OfficeWiFi.ps1"
exit /b %errorlevel%
