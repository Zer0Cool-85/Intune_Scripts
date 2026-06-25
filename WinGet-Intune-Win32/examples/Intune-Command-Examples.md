# Intune command examples

## Install command

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-WinGetApp.ps1 -AppId "Git.Git" -Source "winget" -Scope "machine"
```

## Install command with pinned version

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-WinGetApp.ps1 -AppId "Git.Git" -Version "2.45.2" -Source "winget" -Scope "machine"
```

## Install command where scope is unsupported or inconsistent

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-WinGetApp.ps1 -AppId "Vendor.App" -Source "winget" -Scope "none"
```

## Microsoft Store source example

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-WinGetApp.ps1 -AppId "XP89DCGQ3K6VLD" -Source "msstore" -Scope "machine"
```

## Uninstall command

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Uninstall-WinGetApp.ps1 -AppId "Git.Git" -Source "winget" -Scope "machine" -TreatNotInstalledAsSuccess
```

## Uninstall by MSI product code

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Uninstall-WinGetApp.ps1 -ProductCode "{00000000-0000-0000-0000-000000000000}" -Scope "machine" -TreatNotInstalledAsSuccess
```

## Intune app settings

- Install behavior: `System`
- Device restart behavior: `Determine behavior based on return codes`
- Detection: registry, file, MSI product code, or a customized detection script
- Avoid detection based on `winget list` unless there is no better option

## Recommended return codes

| Return code | Type |
|---:|---|
| 0 | Success |
| 1707 | Success |
| 3010 | Soft reboot |
| 1641 | Hard reboot |
| Other | Failed |
