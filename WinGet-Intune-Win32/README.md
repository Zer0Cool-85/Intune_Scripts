# WinGet Intune Win32 Wrapper

Reusable PowerShell wrappers for deploying WinGet packages through Microsoft Intune Win32 apps.

This repo is intended for environments where you want to keep using WinGet for certain app installs, but want better Intune reliability than a raw `winget install` command. The install and uninstall wrappers are designed for Intune Management Extension / SYSTEM-context execution.

## Why use this wrapper?

Raw WinGet commands can be inconsistent from Intune because of:

- `winget.exe` not being in the SYSTEM PATH
- App Installer / Windows Package Manager registration timing
- source agreement prompts
- package agreement prompts
- source ambiguity between `winget` and `msstore`
- installer scope differences between user and machine installs
- scripts that do not return the native WinGet exit code to Intune
- detection rules that rely on `winget list` instead of the actual installed app

This wrapper helps by:

- resolving `winget.exe` from `C:\Program Files\WindowsApps`
- using exact package IDs
- forcing source selection
- accepting package and source agreements
- disabling interactivity
- supporting optional version pinning
- supporting `machine`, `user`, or `none` scope
- writing wrapper and WinGet logs to `C:\ProgramData`
- retrying transient failures
- exiting with the actual WinGet exit code

## Repo layout

```text
WinGet-Intune-Win32/
├── src/
│   ├── Install-WinGetApp.ps1
│   └── Uninstall-WinGetApp.ps1
├── detection/
│   ├── Detect-AppByFile.ps1
│   ├── Detect-AppByRegistry.ps1
│   └── Detect-WinGetAvailable.ps1
├── docs/
│   └── Troubleshooting.md
├── examples/
│   ├── Intune-Command-Examples.md
│   └── Package-With-IntuneWinAppUtil.ps1
├── .gitignore
└── README.md
```

## Quick start

### Install example

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-WinGetApp.ps1 -AppId "Git.Git" -Source "winget" -Scope "machine"
```

### Install a specific version

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-WinGetApp.ps1 -AppId "Git.Git" -Version "2.45.2" -Source "winget" -Scope "machine"
```

### Install when scope is unsupported or unreliable

Some WinGet packages do not support `--scope machine`. For those apps, use `-Scope none` so WinGet uses the installer default.

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Install-WinGetApp.ps1 -AppId "Vendor.App" -Source "winget" -Scope "none"
```

### Uninstall example

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Uninstall-WinGetApp.ps1 -AppId "Git.Git" -Source "winget" -Scope "machine" -TreatNotInstalledAsSuccess
```

### Uninstall by MSI product code

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\Uninstall-WinGetApp.ps1 -ProductCode "{00000000-0000-0000-0000-000000000000}" -Scope "machine" -TreatNotInstalledAsSuccess
```

## Recommended Intune Win32 app settings

| Setting | Recommendation |
|---|---|
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Install command | Use `Sysnative` PowerShell command shown above |
| Uninstall command | Use `Sysnative` PowerShell command shown above |
| Detection | Registry, file, or MSI product code when possible |
| Detection to avoid | Avoid `winget list` as your primary detection method |

Recommended return codes:

| Return code | Type |
|---:|---|
| 0 | Success |
| 1707 | Success |
| 3010 | Soft reboot |
| 1641 | Hard reboot |
| Other | Failed |

## Detection guidance

Use Intune detection based on the actual installed app, not WinGet state.

Good detection options:

- MSI product code
- install folder/file path
- file version
- HKLM uninstall registry key
- custom PowerShell detection script

Less reliable detection option:

- `winget list`

Example registry detection script:

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\detection\Detect-AppByRegistry.ps1 -DisplayNameMatch "Git" -MinVersion "2.45.2"
```

## Logging

By default, wrapper and native WinGet logs are written to:

```text
C:\ProgramData\Company\Logs\WinGet
```

Example log files:

```text
Git.Git-install-wrapper.log
Git.Git-winget-install.log
Git.Git-uninstall-wrapper.log
Git.Git-winget-uninstall.log
```

Intune Management Extension logs are here:

```text
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs
```

Useful IME logs:

```text
IntuneManagementExtension.log
AgentExecutor.log
AppActionProcessor.log
```

## Packaging with IntuneWinAppUtil

Download the Microsoft Win32 Content Prep Tool separately, then package the repo folder.

Example:

```powershell
.\examples\Package-With-IntuneWinAppUtil.ps1 -IntuneWinAppUtilPath "C:\Tools\IntuneWinAppUtil.exe"
```

Or manually:

```powershell
IntuneWinAppUtil.exe -c "C:\Path\WinGet-Intune-Win32" -s "src\Install-WinGetApp.ps1" -o "C:\Path\Output" -q
```

## Parameters: Install-WinGetApp.ps1

| Parameter | Required | Default | Description |
|---|---:|---|---|
| `AppId` | Yes | N/A | Exact WinGet package ID |
| `Version` | No | Empty | Exact version to install |
| `Source` | No | `winget` | `winget` or `msstore` |
| `Scope` | No | `machine` | `machine`, `user`, or `none` |
| `Retries` | No | `2` | Retry attempts after the first failure |
| `RetryDelaySeconds` | No | `30` | Base retry delay |
| `LogRoot` | No | `C:\ProgramData\Company\Logs\WinGet` | Log folder |
| `SkipSourceUpdate` | No | Disabled | Skip `winget source update` |

## Parameters: Uninstall-WinGetApp.ps1

| Parameter | Required | Default | Description |
|---|---:|---|---|
| `AppId` | Yes for AppId mode | N/A | Exact WinGet package ID |
| `ProductCode` | Yes for ProductCode mode | N/A | MSI product code filter |
| `Source` | No | `winget` | `winget` or `msstore` |
| `Scope` | No | `machine` | `machine`, `user`, or `none` |
| `Version` | No | Empty | Exact version to uninstall |
| `AllVersions` | No | Disabled | Attempt to uninstall all versions |
| `Retries` | No | `1` | Retry attempts after the first failure |
| `RetryDelaySeconds` | No | `30` | Base retry delay |
| `LogRoot` | No | `C:\ProgramData\Company\Logs\WinGet` | Log folder |
| `TreatNotInstalledAsSuccess` | No | Disabled | Return 0 if package appears to be absent |

## Microsoft references

- WinGet install command: https://learn.microsoft.com/en-us/windows/package-manager/winget/install
- WinGet uninstall command: https://learn.microsoft.com/en-us/windows/package-manager/winget/uninstall
- WinGet source command: https://learn.microsoft.com/en-us/windows/package-manager/winget/source
- Intune Win32 app deployment: https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32
- Intune Win32 app management: https://learn.microsoft.com/en-us/intune/app-management/deployment/win32

## Notes

This wrapper does not replace proper app detection. The most reliable Intune deployments still use app-specific registry, file, or MSI detection rules.
