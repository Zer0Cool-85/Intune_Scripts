# Troubleshooting

## Status is Not applicable

This normally means the custom requirement script returned `0`.

Check each configured marker in `config\AppRegistration.json`:

```powershell
Test-Path -LiteralPath 'C:\ProgramData\YourCompany\AdminElevation\AdminElevation.ps1' -PathType Leaf

Get-ScheduledTask -TaskName 'Your scheduled task name' -ErrorAction SilentlyContinue
```

Also verify `Presence.MatchMode`:

- `All` requires every configured marker.
- `Any` requires at least one configured marker.

After changing the JSON configuration, rebuild the scripts and package. Intune rules contain embedded configuration and do not read the repository JSON at runtime.

## Installation succeeded but Intune says the app was not detected

Inspect the 64-bit registry key:

```powershell
$key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YourCompany.AdminElevation'

Get-ItemProperty -LiteralPath $key |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation
```

Compare the results with `config\AppRegistration.json`. Detection requires:

- Exact `DisplayName`
- Exact `Publisher`
- A valid dotted `DisplayVersion` greater than or equal to the configured value

Common causes include:

- The package was rebuilt but the detection script was not replaced in Intune.
- The application version contains non-version text such as `v1.0-beta`.
- A 32-bit registry key was created manually instead of the expected 64-bit key.
- The configured presence markers disappeared between requirement evaluation and installation.

## Registry entry is present but Discovered apps has not updated

Check the following:

1. The device is corporate-owned and enrolled in Intune.
2. The Intune Management Extension is installed and healthy.
3. `DisplayName`, `DisplayVersion`, and `Publisher` contain valid values.
4. The key exists under the 64-bit uninstall registry path.
5. Allow time for the inventory cycle. Legacy Win32 Discovered apps inventory is not immediate.

If Windows App inventory is enabled through a Properties catalog policy, check the device's **All Apps > App Inventory** view as well.

## Intune Management Extension logs

Review:

```text
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs
```

Useful logs can include:

- `IntuneManagementExtension.log`
- `AppWorkload.log`
- `AppActionProcessor.log`
- `AgentExecutor.log`

Log names and processing details can vary as the Intune Management Extension evolves.

## Test in SYSTEM context

For an accurate local test, run the generated installer as Local System using an approved administration tool such as PsExec:

```text
psexec.exe -i -s powershell.exe
```

Then run:

```powershell
& 'C:\Path\To\build\Source\Install.ps1'
```

Do this only on a test device. The installer intentionally modifies the machine-wide uninstall registry.

## Remove the test registration

The generated uninstall script removes only the registration:

```powershell
& 'C:\Path\To\build\Source\Uninstall.ps1'
```

It does not remove application files, scheduled tasks, services, or other original-app artifacts.
