# Cisco Secure Client + Umbrella + DART — Intune Win32 Bundle

This package installs Cisco Secure Client Core, DART, and the Umbrella Roaming Security module as one Intune Win32 application. The wrapper is version-independent: it discovers the selected predeploy MSIs, verifies their Cisco signatures and MSI metadata, enforces matching package versions, evaluates the installed versions, installs only missing or older modules in Cisco's required order, and writes a validated state file for Intune detection.

No Cisco installers or organization-specific `OrgInfo.json` file are included. Supply those from your licensed Cisco download and Umbrella dashboard.

## Package layout

```text
Cisco-Secure-Client-Intune-Bundle
├── Install-CiscoSecureClient.ps1
├── Uninstall-CiscoSecureClient.ps1
├── Detect-CiscoSecureClient.ps1
├── Build-IntunePackage.ps1
├── Config.json
└── Files
    ├── cisco-secure-client-win-<version>-core-vpn-predeploy-k9.msi
    ├── cisco-secure-client-win-<version>-dart-predeploy-k9.msi
    ├── cisco-secure-client-win-<version>-umbrella-predeploy-k9.msi
    └── Profiles
        └── umbrella
            └── OrgInfo.json
```

Cisco identifies the Windows predeploy package as the correct package for MDM/enterprise software deployment. Cisco also requires the core module first, DART second, and optional modules such as Umbrella after those. Optional-module versions must match the installed core version.

## 1. Prepare the source

1. Download and extract the **Windows predeployment** package for your chosen Cisco Secure Client release.
2. Copy the matching Core, DART, and Umbrella MSIs into `Files`.
3. Download your current Umbrella module profile and place it at `Files\Profiles\umbrella\OrgInfo.json` without renaming it.
4. Review `Config.json`.
5. Confirm that `PackageRevision` in `Config.json` exactly matches `$ExpectedPackageRevision` near the top of `Detect-CiscoSecureClient.ps1`.

Always use all three MSIs from the same Cisco release. The installer deliberately rejects mixed versions before changing the endpoint.

Do not commit Cisco binaries or the real `OrgInfo.json` to a public GitHub or Bitbucket repository. The included `.gitignore` excludes them.

## 2. Configuration

| Setting | Default | Meaning |
| --- | ---: | --- |
| `PackageRevision` | `2026.09.08.2` | Your revision for this exact Intune payload. Increment it for every repackaging and update the same value in the detection script. |
| `InstallUmbrella` | `true` | Installs and verifies the Umbrella module. |
| `InstallDart` | `true` | Installs and verifies DART. |
| `RequireOrgInfo` | `true` | Fails before installation if the organization profile is missing or invalid. |
| `RequireValidCiscoSignature` | `true` | Rejects an MSI unless Windows reports a valid Cisco Systems signature. |
| `DisableVpn` | `false` | When `true`, passes `PRE_DEPLOY_DISABLE_VPN=1` to Core. Use only if your organization does not use Cisco for VPN. |
| `EnableLockdown` | `false` | Applies `LOCKDOWN=1` to Core and Umbrella. Cisco warns this is one-way and cannot be removed without reinstalling the product. Pilot it carefully. |
| `HideModulesFromProgramsAndFeatures` | `false` | Passes `ARPSYSTEMCOMPONENT=1` to hide the bundled modules from Programs and Features. |
| `DisableCustomerExperienceFeedback` | `false` | Passes Cisco's feedback-disable property to Core. |
| `RestrictUpgradeWhenVpnActive` | `false` | Prevents Core upgrades during an active Cisco VPN session. A blocked attempt will fail and Intune can retry later. |
| `FailIfExistingOrgInfoDiffers` | `true` | Stops before changing a different installed Umbrella organization profile. See the profile warning below. |
| `RemoveOrgInfoOnUninstall` | `false` | Removes the top-level `OrgInfo.json` during uninstall when enabled. |
| `BlockUninstallIfAdditionalModulesDetected` | `true` | Refuses Core removal when modules such as NVM, NAM, ISE Posture, ZTA, or ThousandEyes are detected. |

The Core MSI is always installed because Umbrella depends on shared Secure Client components even when Cisco VPN functionality is disabled.

### Important `OrgInfo.json` warning

Cisco states that the first deployed `OrgInfo.json` is copied into the Umbrella data directory. Replacing only the top-level file does not change an existing registration; changing organizations requires deleting that data directory or uninstalling and reinstalling the Umbrella module. For safety, this wrapper fails if the packaged and installed profiles differ—or if registration data exists but the top-level profile is unavailable for comparison—unless `FailIfExistingOrgInfoDiffers` is explicitly disabled.

## 3. Test locally

From an elevated 64-bit Windows PowerShell 5.1 prompt:

```powershell
Set-Location C:\Path\To\Cisco-Secure-Client-Intune-Bundle
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CiscoSecureClient.ps1
$LASTEXITCODE
```

Expected results:

- Missing or older modules are installed/upgraded to the packaged version.
- Modules already at the packaged version are not reinstalled.
- If all required modules are already installed at one newer version, no Cisco MSI runs; the existing installation is adopted into the bundle state.
- `C:\ProgramData\Cisco\Cisco Secure Client\Umbrella\OrgInfo.json` exists.
- `C:\ProgramData\CiscoSecureClientBundle\InstallState.json` is created only after full verification.
- Wrapper and verbose MSI logs appear under `C:\ProgramData\CiscoSecureClientBundle\Logs`.

Test detection separately:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Detect-CiscoSecureClient.ps1
$LASTEXITCODE
```

Detection succeeds only when the package revision, every recorded MSI product/version, and the deployed `OrgInfo.json` hash are correct.

### Existing-version and downgrade protection

Before invoking any MSI, the wrapper uses each package's Windows Installer `UpgradeCode` to find the related installed module and compares versions:

| Installed state | Action |
| --- | --- |
| Module missing | Install the packaged module. |
| Module older than package | Upgrade that module. |
| Module equal to package | Skip its MSI and record the existing product. |
| All required modules installed at the same newer version | Skip every MSI and write/refresh the bundle state JSON. |
| A newer module exists, but another required module is missing or at a different version | Fail safely before running any MSI; package a release at least as new as the endpoint. |

This prevents an older Intune payload from downgrading a newer Cisco deployment and prevents the wrapper from creating a mixed-version client. When an equal/newer installation is adopted, the Umbrella profile is still validated and staged, but MSI-only configuration properties are not reapplied because the MSI is intentionally skipped.

## 4. Build the `.intunewin`

Download Microsoft's Win32 Content Prep Tool and run:

```powershell
.\Build-IntunePackage.ps1 `
    -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe'
```

The builder validates the required content and creates a revision-named package in a sibling `Cisco-Secure-Client-Intune-Output` folder. You can provide a different folder with `-OutputPath`.

## 5. Intune Win32 app settings

Use these values when creating the app:

| Intune field | Value |
| --- | --- |
| Install command | `%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File .\Install-CiscoSecureClient.ps1` |
| Uninstall command | `%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File .\Uninstall-CiscoSecureClient.ps1` |
| Install behavior | `System` |
| Device restart behavior | `Determine behavior based on return codes` |
| Architecture | `64-bit` |

For **Detection rules**, choose **Use a custom detection script** and upload `Detect-CiscoSecureClient.ps1`.

- Run script as 32-bit process on 64-bit clients: **No**
- Enforce script signature check: select based on your own signing workflow; use **No** for the unsigned template

Retain or add these return-code mappings:

| Code | Intune result |
| ---: | --- |
| `0` | Success |
| `3010` | Soft reboot |
| `1641` | Hard reboot |
| `1618` | Retry |
| Other | Failed |

## Migrating from the three existing Intune apps

Do not assign **Uninstall** for the old Core, Umbrella, or DART apps during the migration. Their uninstall commands can remove components that the new bundle just installed.

A safe rollout is:

1. Create a pilot device group.
2. Exclude that group from the three legacy apps' Required assignments. Removing a Required assignment does not uninstall the existing software.
3. Assign this bundle as Required to the pilot group.
4. Verify install state, logs, Cisco VPN behavior if used, Umbrella protection, and DART.
5. Expand the exclusions and bundle assignment in rings.
6. Retire the old app objects only after the fleet has moved to the bundle.

This exclusion step matters if the old apps use version-specific MSI detection. Otherwise, an old Required app can see the upgraded product code as missing and reinstall an older MSI.

## Updating Cisco Secure Client later

1. Replace all selected MSIs with files from the new matching predeploy release.
2. Increment `PackageRevision` in `Config.json`.
3. Set the identical value in `Detect-CiscoSecureClient.ps1`.
4. Build a new `.intunewin` package.
5. Test it over the installed production version before wider deployment.

The installer skips equal versions, upgrades only older or missing modules, and never intentionally downgrades a newer installation. It does not preemptively uninstall the existing modules. This avoids an unnecessary unprotected gap and lets MSI handle supported upgrades.

## Uninstall safeguards

The uninstall script uses product codes captured during the successful installation; it never queries `Win32_Product`. It also:

- refuses to run if its package revision differs from the installed bundle state, preventing an older cached package from removing a newer deployment;
- checks for additional Cisco Secure Client modules before making changes;
- follows Cisco's removal order: Umbrella, Core, then DART;
- preserves logs and, by default, the top-level `OrgInfo.json`.

## References

- [Cisco Secure Client deployment and Windows predeployment guidance](https://www.cisco.com/c/en/us/td/docs/security/vpn_client/anyconnect/Cisco-Secure-Client-5/admin/guide/b-cisco-secure-client-admin-guide-5-1/deploy-anyconnect.html)
- [Cisco guidance for disabling VPN while retaining Umbrella](https://www.cisco.com/c/en/us/support/docs/security/umbrella/224787-disable-the-vpn-module-in-secure-client.html)
- [Cisco installation behavior, Lockdown, and ARPSYSTEMCOMPONENT](https://www.cisco.com/c/en/us/td/docs/security/vpn_client/anyconnect/Cisco-Secure-Client-5/admin/guide/cisco-secure-client-admin-guide-new/customize-secure-client-intro/c_modify_anyconnect_installation_behavior.html)
- [Cisco Umbrella profile behavior and replacement warning](https://www.cisco.com/c/en/us/td/docs/security/vpn_client/anyconnect/Cisco-Secure-Client-5/admin/guide/cisco-secure-client-admin-guide-new/umbrella-roaming-security-intro/umbrella-module-for-anyconnect-for-windows-or-macos.html)
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
