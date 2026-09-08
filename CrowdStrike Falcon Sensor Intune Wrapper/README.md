# CrowdStrike Falcon Windows Sensor — Intune Win32 Wrapper

This package deploys the CrowdStrike Falcon Windows Sensor as a silent, System-context Intune Win32 app. The version-aware wrapper validates the packaged installer, checks the existing installation and tenant, installs only when the sensor is missing or older, and writes a verified state file for custom Intune detection.

No CrowdStrike installer, CID, provisioning token, or maintenance token is included in this repository-ready template. Supply those values from your own licensed Falcon tenant.

## What the wrapper does

- Finds exactly one sensor EXE in `Files`; the filename can change between CrowdStrike releases.
- Reads the packaged version from the EXE metadata and verifies its SHA-256 hash.
- By default, rejects the EXE unless Windows reports a valid CrowdStrike Authenticode signature.
- Finds an installed sensor without querying `Win32_Product`.
- Reads the running sensor binary version first, with the uninstall registry as a fallback.
- Confirms that an existing sensor belongs to the configured CID before adopting or upgrading it.
- Uses CrowdStrike's silent parameters: `/install /quiet /norestart CID=<CID>`.
- Supports an optional provisioning token, grouping tags, proxy host, and proxy port.
- Never logs or stores the CID, provisioning token, or maintenance token in plaintext.
- Verifies the sensor version, CID, service registration, executable, and optionally running service state.
- Writes `C:\ProgramData\CrowdStrikeFalconIntune\InstallState.json` only after verification succeeds.
- Keeps wrapper logs in `C:\ProgramData\CrowdStrikeFalconIntune\Logs`.

The sensor itself may write additional diagnostic logs in CrowdStrike-defined Windows locations.

## Package layout

```text
CrowdStrike-Falcon-Sensor-Intune-Wrapper
├── Install-CrowdStrikeFalcon.ps1
├── Uninstall-CrowdStrikeFalcon.ps1
├── Detect-CrowdStrikeFalcon.ps1
├── Build-IntunePackage.ps1
├── Config.json
├── TenantConfig.json.example
├── TenantConfig.json                 # create this; Git ignored
└── Files
    └── FalconSensor_Windows.exe       # example name; Git ignored
```

## Existing-version behavior

| Endpoint state | Wrapper action |
| --- | --- |
| Sensor missing | Silently installs the packaged sensor. |
| Installed sensor older than package | Runs an in-place upgrade. |
| Installed sensor equals package | Skips the EXE and adopts the healthy installation into wrapper state. |
| Installed sensor newer than package | Skips the EXE and adopts the healthy newer installation; no downgrade is attempted. |
| Equal/newer sensor is unhealthy | Fails safely and directs you to a supported CrowdStrike repair workflow. |
| Existing CID differs | Fails before running the installer; it does not rehome or remove the other tenant's sensor. |
| Existing version cannot be determined | Fails before running the installer because downgrade safety cannot be evaluated. |

CrowdStrike sensor update policies can upgrade the sensor after this package is installed. Detection therefore requires the current version to be **at least** the packaged version recorded in state; it does not require an exact version match. A normal Falcon-managed self-update will not make Intune reinstall the older package.

## 1. Add your licensed content

1. Download the correct Windows Sensor installer from your Falcon console.
2. Put exactly one sensor `.exe` in `Files`.
3. Copy `TenantConfig.json.example` to `TenantConfig.json`.
4. Replace the example CID with the CID shown in your Falcon console, including its checksum suffix.
5. Add a provisioning token only if your Falcon installation-token policy requires one.
6. Leave `MaintenanceToken` empty for a normal deployment package.
7. Review `Config.json`.

Do not commit the installer or `TenantConfig.json` to a public GitHub or Bitbucket repository. The included `.gitignore` excludes both.

Example tenant file:

```json
{
  "CID": "0123456789ABCDEF0123456789ABCDEF-12",
  "ProvisioningToken": "",
  "MaintenanceToken": ""
}
```

## 2. Configuration

| Setting | Default | Meaning |
| --- | ---: | --- |
| `PackageRevision` | `2026.09.08.1` | Revision of this exact Intune payload. Increment it for every repackaging and update the identical value in the detection script. |
| `RequireValidCrowdStrikeSignature` | `true` | Rejects the packaged EXE unless its Authenticode signature is valid and its signer contains `CrowdStrike`. |
| `RequireTenantMatch` | `true` | Requires the installed CID to match the configured CID before adoption, upgrade, detection, or uninstall. |
| `RequireRunningServices` | `true` | Requires both `CSFalconService` and `csagent` to be running for normal detection and adoption. |
| `RequireProvisioningToken` | `false` | When `true`, packaging and installation fail if `ProvisioningToken` is empty. |
| `ProvisioningWaitTimeMilliseconds` | `1200000` | Passes `ProvWaitTime` to the installer; the default is 20 minutes. |
| `GroupingTags` | `[]` | Optional sensor grouping tags. Allowed template characters are letters, numbers, `.`, `_`, `:`, and `-`. |
| `ProxyHost` | empty | Optional sensor proxy hostname or IP address. Do not include a URL scheme. |
| `ProxyPort` | `0` | Set to `1`–`65535` when `ProxyHost` is configured; otherwise leave `0`. |
| `PostInstallVerificationTimeoutSeconds` | `180` | Time allowed for files, services, version, and CID registration to become verifiable. |
| `InstallerBusyRetryCount` | `3` | Retries when the installer returns `1618`. |
| `InstallerBusyRetryDelaySeconds` | `30` | Delay between `1618` retries. |
| `EnableUninstall` | `false` | Intentional safeguard. The uninstall script refuses to remove Falcon until explicitly enabled and repackaged. |
| `AllowPackagedInstallerForUninstall` | `false` | Allows the packaged sensor EXE as an uninstall fallback when the current installed cache cannot be found. Keep disabled unless CrowdStrike confirms compatibility. |

When an equal or newer installation is adopted, EXE-only settings such as grouping tags and proxy values are not reapplied because the installer is intentionally skipped.

## 3. Test locally

Use an elevated **64-bit Windows PowerShell 5.1** prompt:

```powershell
Set-Location C:\Path\To\CrowdStrike-Falcon-Sensor-Intune-Wrapper
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install-CrowdStrikeFalcon.ps1
$LASTEXITCODE
```

Then test detection:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Detect-CrowdStrikeFalcon.ps1
$LASTEXITCODE
```

Expected results:

- The sensor EXE runs only if Falcon is missing or older.
- A healthy equal/newer sensor is adopted without an installer launch.
- Detection prints one success line and exits `0`.
- A failed detection prints nothing and exits `1`.
- The wrapper log contains no plaintext CID or token.

Pilot with the exact sensor build and policies used by your tenant. This template cannot perform a real sensor install test without your licensed EXE and tenant values.

## 4. Build the `.intunewin`

Download Microsoft's Win32 Content Prep Tool and run:

```powershell
.\Build-IntunePackage.ps1 `
    -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe'
```

The builder validates the source, revision match, CID format, token requirements, installer version, hash, and signature before creating a revision-named package in the sibling `CrowdStrike-Falcon-Sensor-Intune-Output` folder.

Use `-OutputPath` to choose a different output folder. The output must remain outside the source directory.

## 5. Intune Win32 app settings

| Intune field | Value |
| --- | --- |
| Install command | `%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File .\Install-CrowdStrikeFalcon.ps1` |
| Uninstall command | `%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File .\Uninstall-CrowdStrikeFalcon.ps1` |
| Install behavior | `System` |
| Device restart behavior | `Determine behavior based on return codes` |
| Architecture | `64-bit` |

For **Detection rules**, choose **Use a custom detection script** and upload `Detect-CrowdStrikeFalcon.ps1`.

- Run script as 32-bit process on 64-bit clients: **No**
- Enforce script signature check: use your organization's signing policy; select **No** for this unsigned template

Retain or add these return-code mappings:

| Code | Intune result |
| ---: | --- |
| `0` | Success |
| `3010` | Soft reboot |
| `1641` | Hard reboot |
| `1618` | Retry |
| `106` | Failed — uninstall protection/token issue |
| `1244` | Failed — provisioning/connectivity/token issue |
| Other | Failed |

The install is fully silent: PowerShell is launched hidden and the CrowdStrike installer receives `/quiet /norestart`. The package uses the offline sensor EXE and does not invoke a web downloader.

## Moving from an older Intune app

Do not assign **Uninstall** to the old CrowdStrike app as part of the migration.

1. Create a pilot device group.
2. Exclude it from the old app's Required assignment without creating an Uninstall assignment.
3. Assign this wrapper as Required to the pilot group.
4. Confirm the wrapper adopts the existing sensor, detection succeeds, services remain running, and the host continues checking in to Falcon.
5. Expand the change in rings.
6. Retire the old app object only after the fleet has moved.

This matters when the old app has version-specific detection. It may otherwise consider a Falcon-managed sensor update missing and try to reinstall its older package.

## Updating the package later

1. Replace the EXE in `Files` with the newly approved sensor installer.
2. Increment `PackageRevision` in `Config.json`.
3. Set the same value in `$ExpectedPackageRevision` near the top of `Detect-CrowdStrikeFalcon.ps1`.
4. Build a new `.intunewin` file.
5. Update the Intune app content and upload the matching new detection script.
6. Test over both an older sensor and a sensor already made newer by its Falcon update policy.

The wrapper never intentionally downgrades a newer sensor and does not pre-uninstall an older one before an upgrade.

## Uninstall safeguards

Uninstall is disabled by default because this is endpoint protection and Falcon commonly enforces uninstall/maintenance protection.

When an approved removal is required:

1. Prefer a CrowdStrike policy that temporarily permits uninstall for the narrowly targeted devices, or obtain an appropriate maintenance token through your approved Falcon process.
2. Set `EnableUninstall` to `true`.
3. If using a shared maintenance token, place it in `TenantConfig.json` only for the short-lived removal package. Understand that a shared token embedded in Intune content is sensitive.
4. Increment both package-revision values and rebuild.
5. Test on a pilot device before making any Uninstall assignment.
6. Retire the removal-enabled payload promptly after the approved change.

The uninstall wrapper:

- requires the successful install state from the same package revision;
- rechecks the CID before removal;
- prefers the currently installed CrowdStrike cache rather than the older EXE held by Intune;
- validates the cached uninstaller's CrowdStrike signature before execution;
- passes the maintenance token without writing it to the wrapper log;
- reports exit `106` clearly when uninstall protection rejects the request.

Per-device maintenance tokens are not suitable for one shared Intune app. Do not hard-code a fleet-wide or bulk maintenance token in a long-lived production package.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Exit `1244` | CID, provisioning token, proxy settings, SSL inspection, and access to the correct Falcon cloud endpoints. |
| Existing sensor is not adopted | Review CID access and the status of `CSFalconService` and `csagent`. Equal/newer but unhealthy sensors intentionally fail. |
| Detection fails after packaging | Confirm the detection script revision exactly matches `Config.json`, run it as 64-bit, and inspect `InstallState.json`. |
| Detection briefly fails during a Falcon update | Services can restart during an update. Intune should reevaluate; the wrapper will not downgrade a newer healthy sensor. |
| Uninstall cannot locate its cache | Keep the packaged fallback disabled unless CrowdStrike approves that installer for the fleet's installed versions. Use CrowdStrike's supported uninstall tooling if the cache is damaged. |
| Revision mismatch during uninstall | A cached older payload attempted removal after a newer wrapper revision was installed. Use the current package. |

## References

- [CrowdStrike PowerShell sensor installation and uninstallation guidance](https://developer.crowdstrike.com/falcon-sensor/scripts/powershell/install/)
- [CrowdStrike-maintained Falcon deployment scripts](https://github.com/CrowdStrike/falcon-scripts)
- [CrowdStrike Windows deployment guide using SYSTEM and the silent sensor command](https://github.com/CrowdStrike/deployment-guides/tree/main/microsoft/gpo)
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
