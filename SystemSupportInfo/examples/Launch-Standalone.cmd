@echo off
setlocal

rem Double-click this file to launch the modular PowerShell version.
start "" powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0..\SystemSupportInfo.ps1"

endlocal
