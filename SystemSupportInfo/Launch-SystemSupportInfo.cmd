@echo off
setlocal

rem One-click launcher for the modular PowerShell version.
start "" powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0SystemSupportInfo.ps1"

endlocal

