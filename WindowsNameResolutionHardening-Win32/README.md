# Windows Name Resolution Hardening — Intune Win32 app

Version 1.0.0 disables NBT-NS, LLMNR, the Windows mDNS resolver, and WPAD. It is designed for organizations that can deploy Win32 apps but don't have Intune Remediations licensing.

## How it stays enforced

Installation applies the controls immediately and creates a SYSTEM scheduled task named **Windows Name Resolution Hardening**. The task runs:

- At startup
- At any user logon
- Every four hours

The Intune detection script independently checks:

- Package version and enforcement-script SHA-256
- Installed script and enabled scheduled task
- Startup, logon, and recurring task triggers
- All device registry controls for NBT-NS, LLMNR, mDNS, and WPAD
- NetbiosOptions=2 on every current NetBT interface
- WPAD state for every currently loaded human-user hive

If any check fails, detection exits 1. A Required assignment therefore causes Intune to offer the app again, while the scheduled task normally repairs drift first.

## Contents

- **Source\Install.ps1** — installs and immediately enforces the controls
- **Source\Set-WindowsNameResolutionHardening.ps1** — idempotent enforcement engine
- **Source\Detect.ps1** — custom Intune detection rule
- **Source\Uninstall.ps1** — removes the enforcement mechanism but retains hardened settings
- **Build-IntuneWin.ps1** — wrapper for Microsoft's Win32 Content Prep Tool

## Build the .intunewin

1. Download the latest [Microsoft Win32 Content Prep Tool](https://learn.microsoft.com/en-us/intune/app-management/deployment/create-win32-package) (IntuneWinAppUtil.exe) from Microsoft's official release.
2. Extract this bundle on a Windows administrative workstation.
3. From the bundle root, run:

~~~powershell
.\Build-IntuneWin.ps1 -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe'
~~~

The result is **Output\Install.intunewin**. The output folder is intentionally outside **Source**; never place an .intunewin file inside the source folder.

## Create the Intune app

In **Intune admin center > Apps > All apps > Create**, choose **Windows app (Win32)** and upload **Output\Install.intunewin**.

Suggested app information:

| Field | Value |
|---|---|
| Name | Windows Name Resolution Hardening |
| Description | Disables NBT-NS, LLMNR, Windows mDNS, and WPAD with recurring local enforcement. |
| Publisher | Your organization |
| Version | 1.0.0 |

### Program

| Setting | Value |
|---|---|
| Install command | powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1 |
| Uninstall command | powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Uninstall.ps1 |
| Install behavior | System |
| Device restart behavior | No specific action |
| Installation time required | 15 minutes |
| Allow available uninstall | No |

The scripts automatically relaunch in native 64-bit Windows PowerShell when Intune starts them in a 32-bit process.

### Requirements

- Architecture: select the architectures in your managed Windows estate
- Minimum operating system: your oldest supported Windows 10 or Windows 11 release
- No logged-on user is required

### Detection rules

Choose **Use a custom detection script** and upload **Source\Detect.ps1**.

| Setting | Value |
|---|---|
| Run script as 32-bit process on 64-bit clients | No |
| Enforce script signature check | No, unless your organization signs the script |

The detection script must remain paired with package version 1.0.0. It returns exit code 0 plus STDOUT only when every control is compliant.

### Assignments

Assign the app as **Required** to a pilot **device group**, then broaden the device assignment after validation. Device targeting is preferable because the controls and scheduled task are machine-scoped and must install as SYSTEM.

## Validate a pilot device

1. Confirm Intune reports the Win32 app as installed.
2. Run **Source\Detect.ps1** locally in elevated 64-bit Windows PowerShell; it should return exit code 0.
3. Confirm Task Scheduler shows **Windows Name Resolution Hardening** running as SYSTEM.
4. Review these logs:
   - C:\ProgramData\WindowsNameResolutionHardening\Installer.log
   - C:\ProgramData\WindowsNameResolutionHardening\WindowsNameResolutionHardening.log
   - C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log
   - C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppActionProcessor.log
5. Restart at least one pilot device and retest line-of-business applications, proxy access, printing/discovery, and Delivery Optimization behavior.

## Operational notes

- A restart is recommended after first deployment, but the installer doesn't force one.
- The uninstall command removes the task, files, and package marker. It deliberately leaves the hardened settings in place so an uninstall assignment cannot silently reopen legacy name-resolution paths. Build and test a separate rollback package if re-enabling them is ever required.
- Do not assign conflicting Settings Catalog, OMA-URI, Group Policy, or other scripts with different values for these controls.
- Disabling LLMNR/mDNS can affect DNS-SD and LAN peer discovery. Validate Delivery Optimization and any discovery-dependent applications before broad deployment.
- The registry controls disable the Windows mDNS resolver. They cannot prevent third-party applications from implementing mDNS directly. For that requirement, deploy centrally managed inbound and outbound UDP 5353 block rules through Intune Firewall policy.
- Local firewall rules aren't included because an OIB-aligned firewall policy may disable local rule merging.

## Updating the package

For a new release:

1. Update the enforcement script.
2. Recalculate its SHA-256 and update the constants in **Install.ps1** and **Detect.ps1**.
3. Increment the version constants in both scripts.
4. Rebuild the .intunewin.
5. Replace the app content or deploy the new Win32 app with Intune supersedence. Don't leave two independent versions assigned as Required.
