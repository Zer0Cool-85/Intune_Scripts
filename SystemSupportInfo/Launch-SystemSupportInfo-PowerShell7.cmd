@echo off
setlocal

rem Optional one-click launcher for PowerShell 7 on Windows.
where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh.exe^) was not found in PATH.
    echo Use Launch-SystemSupportInfo.cmd or install PowerShell 7 first.
    pause
    exit /b 1
)

start "" pwsh.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0SystemSupportInfo.ps1"

endlocal
