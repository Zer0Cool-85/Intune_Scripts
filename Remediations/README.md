# Intune Scheduled Remediation Win32 App

This package is a Win32 app template for replacing simple Intune Remediations workflows when Remediations licensing is not available.

## What it does

- Installs `Invoke-RemediationRunner.ps1` to:
  - `C:\ProgramData\Contoso\ScheduledRemediation`
- Creates a SYSTEM scheduled task:
  - `\Contoso\Contoso - Scheduled Remediation`
- Runs once at startup and on a recurring daily trigger.
- Writes local logs:
  - `C:\ProgramData\Contoso\ScheduledRemediation\Logs`
- Writes registry status:
  - `HKLM\SOFTWARE\Contoso\ScheduledRemediation`

## Customize before packaging

Edit these values in all scripts or pass matching parameters from the install/uninstall/detection commands:

- `CompanyName`
- `AppName`
- `TaskName`
- `TaskPath`
- `Version`

Most importantly, edit these functions in `Invoke-RemediationRunner.ps1`:

- `Test-Compliance`
- `Invoke-Remediation`

The included demo logic creates/checks a marker file. Replace that with your real detection and repair logic.

## Intune app settings

### Program

Install command:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Install-ScheduledRemediation.ps1
```

Uninstall command:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Uninstall-ScheduledRemediation.ps1
```

Install behavior:

```text
System
```

Device restart behavior:

```text
No specific action
```

### Requirements

Recommended:

- Operating system architecture: 64-bit
- Minimum operating system: Windows 10 21H2 or Windows 11, depending on your environment

### Detection

Use a custom detection script:

```text
Detect-ScheduledRemediation.ps1
```

Run script as 32-bit process on 64-bit clients:

```text
No
```

## Packaging

Download `IntuneWinAppUtil.exe` from Microsoft's Win32 Content Prep Tool GitHub repo, then run:

```powershell
.\Package-Win32App.ps1 -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe' -OutputFolder 'C:\IntuneOutput'
```

Or run the tool directly:

```powershell
IntuneWinAppUtil.exe -c "C:\Path\To\Intune-ScheduledRemediation-Win32App" -s "Install-ScheduledRemediation.ps1" -o "C:\IntuneOutput" -q
```

Upload the generated `.intunewin` file to Intune as a Windows app (Win32).

## Local testing

From an elevated PowerShell prompt:

```powershell
.\Install-ScheduledRemediation.ps1
Get-ScheduledTask -TaskPath '\Contoso\' -TaskName 'Contoso - Scheduled Remediation'
Start-ScheduledTask -TaskPath '\Contoso\' -TaskName 'Contoso - Scheduled Remediation'
Get-Content 'C:\ProgramData\Contoso\ScheduledRemediation\Logs\RemediationRunner.log' -Tail 50
.\Detect-ScheduledRemediation.ps1
.\Uninstall-ScheduledRemediation.ps1
```

## Notes

- This approach does not give you Intune Remediations reporting. It gives you app install status plus local logs and local registry status.
- Intune can reinstall/repair the framework if detection fails.
- For richer fleet reporting, have the runner write to a location you collect with another inventory mechanism, or use a separate Win32 app/reporting workflow.
