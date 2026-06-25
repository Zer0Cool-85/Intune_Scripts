# Troubleshooting

## Log locations

The wrapper scripts write logs here by default:

```text
C:\ProgramData\Company\Logs\WinGet
```

For each app, you should see wrapper logs and native WinGet logs:

```text
<AppId>-install-wrapper.log
<AppId>-winget-install.log
<AppId>-uninstall-wrapper.log
<AppId>-winget-uninstall.log
```

Intune Management Extension logs are here:

```text
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs
```

Useful IME logs include:

```text
IntuneManagementExtension.log
AgentExecutor.log
AppActionProcessor.log
```

## Common failure causes

### winget.exe was not found

WinGet is provided by App Installer. On new or freshly migrated devices, App Installer / WinGet may not be registered yet for the context running the install. The wrapper tries to resolve winget.exe from WindowsApps instead of relying only on PATH.

### Source agreement prompt or source query problem

Use `--source winget` or `--source msstore` and keep `--accept-source-agreements` in the install command. The uninstall wrapper also restricts to a source by default to avoid unexpected Microsoft Store source prompts.

### Installer works manually but fails from Intune

Check whether the app supports machine scope. Some WinGet packages are user-context installers. Try `-Scope none` so WinGet uses the installer default instead of forcing `--scope machine`.

### Intune says failed but the app is installed

Usually this is detection. Prefer MSI product code, registry, or file detection over `winget list`.

### Intune says success but the app is not installed

Make sure your script exits with the native installer exit code. These wrappers explicitly call `exit $ExitCode` after WinGet finishes.

## Quick local test

Run from an elevated 64-bit PowerShell session:

```powershell
.\src\Install-WinGetApp.ps1 -AppId "Git.Git" -Source winget -Scope machine
```

Test uninstall:

```powershell
.\src\Uninstall-WinGetApp.ps1 -AppId "Git.Git" -Source winget -Scope machine -TreatNotInstalledAsSuccess
```
