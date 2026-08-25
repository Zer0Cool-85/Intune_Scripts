# Enterprise Autopilot Branding

A configuration-driven Windows 11 branding and first-login cleanup framework for Microsoft Intune
and Windows Autopilot. This project is a modular rewrite inspired by
[mtniehaus/AutopilotBranding](https://github.com/mtniehaus/AutopilotBranding), designed for
production environments where accurate detection, safe retries, readable configuration, and
controlled OEM debloating matter more than fitting every provisioning task into one script.

## What changed from the original model

- Successful completion state is written only after critical steps succeed.
- Critical failures return exit code `1`; best-effort failures are recorded as warnings.
- Each capability is idempotent and independently logged.
- The installer requires no internet access.
- No password, credential, or shared local administrator account is embedded.
- WinGet repair, PSGallery installs, Edge downloads, Office removal, GVLK changes, and IP-based time
  zone services are intentionally excluded.
- Configuration remains XML, but uses positive `Enabled="true|false"` controls instead of inverted
  `SkipSomething` values.
- Detection validates package version, completion result, and hashes for the installed configuration
  and complete staged runtime.
- Debloat runs once during the device phase and again after the first user profile exists.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Install-AutopilotBranding.ps1` | SYSTEM-context installer and step orchestrator |
| `Config.xml` | Branding, OS configuration, debloat catalog, and post-enrollment settings |
| `Config.xsd` | Strict configuration schema used by validation and XML-aware editors |
| `Modules/EnterpriseAutopilotBranding.psm1` | Shared implementation and logging functions |
| `Invoke-PostEnroll.ps1` | Delayed first-login SYSTEM runner |
| `Invoke-Debloat.ps1` | Standalone, confirmation-gated debloat audit/enforcement runner |
| `Custom/PostEnroll.Custom.ps1` | Organization-owned extension point for your existing workflow |
| `Detect-AutopilotBranding.ps1` | Source template for custom Intune detection |
| `Uninstall-AutopilotBranding.ps1` | Detection/runtime removal and optional asset cleanup |
| `Build-IntuneWin.ps1` | Validation, ZIP generation, detection generation, and optional `.intunewin` build |
| `Validate-Project.ps1` | Configuration and file-safety validation |
| `Assets` | Sample wallpaper, lock screen, logo, theme, and optional taskbar XML |
| `PolicyExamples` | Supported-policy examples for Start and taskbar management |
| `Tests` | Pester safety tests |

## Quick start

1. Replace the three sample images under `Assets`.
2. Update `OrganizationName`, OEM information, and support URL in Config.xml. Associate
   `Config.xsd` in your XML editor for completion and typo detection.
3. Review every enabled debloat entry. The repository ships in non-destructive `Mode="Audit"`.
4. Replace the no-op body of `Custom/PostEnroll.Custom.ps1` with any existing post-enrollment work.
5. Increment `PackageVersion` whenever code, configuration, or assets change.
6. Run validation from 64-bit Windows PowerShell 5.1:

   ```powershell
   .\Validate-Project.ps1
   ```

7. Create the source ZIP and versioned detection script:

   ```powershell
   .\Build-IntuneWin.ps1
   ```

8. To also create the Intune package, download Microsoft's official
   [Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) and run:

   ```powershell
   .\Build-IntuneWin.ps1 -ContentPrepToolPath C:\Tools\IntuneWinAppUtil.exe
   ```

Artifacts are written to `dist`.

Before packaging, you can create a standalone inventory report from an elevated 64-bit Windows
PowerShell session:

```powershell
.\Invoke-Debloat.ps1 -Mode Audit
```

The manual report contains both catalog matches and a sanitized full Appx/classic inventory. It
records whether each classic application exposes MSI or quiet-uninstall metadata, without copying
the raw uninstall command into the report.

After reviewing the JSON report and preservation rules, enforce the same catalog interactively:

```powershell
.\Invoke-Debloat.ps1 -Mode Enforce
```

For an unattended, previously piloted deployment, explicitly add `-Confirm:$false` or change the
configuration to `Mode="Enforce"` and deploy the complete package.

## Intune Win32 application settings

Use the versioned files produced by `Build-IntuneWin.ps1`.

### Program

Install command:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-AutopilotBranding.ps1
```

Uninstall command:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-AutopilotBranding.ps1
```

Install behavior: `System`

Device restart behavior: `No specific action`

### Requirements

- Architecture: 64-bit or ARM64 Windows 11
- Minimum OS: align this with `Execution.MinimumSupportedBuild` in Config.xml
- Run script as 32-bit process on 64-bit clients: `No`

### Detection

Choose **Use a custom detection script** and upload the generated file:

```text
dist\Detect-AutopilotBranding-4.0.0.ps1
```

The script writes standard output only when the installed result is `Success` or
`SuccessWithWarnings`, the installed package meets the required version, and the staged runtime
still matches the manifest recorded at successful completion. Configuration and executable code
are SHA-256 checked; files under `Custom\Payloads` use presence and length checks to keep recurring
detection fast even when you stage a large installer.

Microsoft documents that an Intune custom detection script must return exit code `0` and write a
value to standard output to report the application as detected:
https://learn.microsoft.com/intune/intune-service/apps/apps-win32-add

### Assignment

Assign the app as Required to the appropriate Autopilot device group and include it in the ESP
blocking-app list when branding must finish before the desktop appears. The installer no longer
bails out merely because Windows reports that OOBE completed, so upgrades, wipes, Fresh Start, and
manual `-Force` executions have deterministic behavior.

## Debloat design

The debloat engine does not remove everything that is not on a giant allowlist. It removes only
packages or programs that match an enabled catalog entry in Config.xml. Classic rules can require
both a display-name pattern and an optional publisher pattern; the supplied Dell removals require
a Dell publisher as a second guard.

### Appx/MSIX packages

The device-phase pass removes matching provisioned packages so Windows does not install them for
new profiles. It also attempts removal from existing profiles. Microsoft distinguishes these two
operations: removing a provisioned package affects future users, while `Remove-AppxPackage` handles
already registered user packages:

- https://learn.microsoft.com/powershell/module/dism/remove-appxprovisionedpackage
- https://learn.microsoft.com/powershell/module/appx/remove-appxpackage

The post-enrollment pass repeats both operations after Windows has created the first user profile.
Protected Windows components may reject removal; those failures are logged and remain noncritical
unless `FailOnError="true"`.

### Classic applications

Classic applications are inventoried from both 64-bit and 32-bit HKLM uninstall registry locations.
The engine will automatically use:

1. An MSI product code with `msiexec /x /qn /norestart`, or
2. The application's registered `QuietUninstallString`.

An unknown EXE with only an interactive `UninstallString` is skipped. This prevents a generic
debloat pass from opening UI, guessing vendor switches, or hanging ESP indefinitely. The timeout is
controlled by `ClassicUninstallTimeoutSeconds`; `ClassicOverallTimeoutSeconds` caps the entire
classic-application pass so a damaged factory image cannot consume ESP indefinitely.

MSI removals always request no restart. For non-MSI applications, the engine uses the vendor's
registered quiet command exactly as published and records restart-required exit codes in the JSON
report; this is another reason to pilot each factory image before enforcement.

McAfee and Norton matching examples are supplied but disabled because complete removal frequently
requires vendor-specific cleanup tooling. Package that tooling as a separate Win32 application if
your Dell image includes a security trial that does not expose a reliable silent uninstaller.

### Dell defaults

The default removal catalog (shipped in Audit mode) targets consumer/home support components such
as SupportAssist, Optimizer, Digital Delivery, Customer Connect, Pair, Mobile Connect, MyDell,
Cinema components, Dell Update, Data Vault, and legacy Foundation Services when they register an
MSI or quiet uninstall command.

Preservation rules are evaluated first and protect:

- Dell Command Update, including common name variants
- Dell Command Configure, Monitor, and Power Manager
- Dell Power Manager
- Dell Trusted Device
- Dell Core Services, TechHub, Tech Management, and Client Device Management components
- Dell Display Manager and Peripheral Manager
- Dell dock and Thunderbolt utilities
- Dell Instrumentation

Dell describes Command Update as its commercial-client update tool. Its current support notes also
warn that removing Dell Core Services can disrupt associated agents, so this project preserves the
shared Core Services and TechHub stack by default:
https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update

If the factory image has only consumer `Dell Update`, make Dell Command Update a separately
detected dependency before enforcing that removal rule; this project preserves DCU but does not
install or upgrade it.

Run Audit mode against representative Latitude, Precision, OptiPlex, and any consumer-model devices
before enabling enforcement across the fleet. OEM display names and uninstall behavior can change
between factory images.

### Reducing reinstallation

The default machine registry catalog enables `DisableWindowsConsumerFeatures`, while provisioned
package removal prevents matching apps from being staged for newly created profiles. These controls
reduce consumer app reappearance but cannot guarantee that a future Windows feature update or OEM
recovery image will never introduce a new package name.

Without Intune Remediations, use one of these controlled options after a feature-update cycle:

- Increment `PackageVersion` and redeploy this app.
- Run `Invoke-PostEnroll.ps1 -Force` through a separate scheduled maintenance package.
- Create a small dedicated debloat Win32 app using the module and Config.xml from this repository.

Avoid running the complete custom post-enrollment hook at every user logon.

## First-login post-enrollment task

The installer stages the module, Config.xml, custom hook, and payload directory under:

```text
%ProgramData%\EnterpriseAutopilotBranding\Runtime
```

It then registers this delayed SYSTEM task:

```text
\EnterpriseAutopilotBranding\PostEnroll
```

Default behavior:

- Trigger: any interactive logon
- Delay: 2 minutes
- Principal: SYSTEM, highest privileges
- Maximum attempts: 3
- Remove task after success: yes
- First action: repeat debloat after the user profile exists
- Second action: run `Custom\PostEnroll.Custom.ps1`

The task is created through the Task Scheduler API; there is no embedded XML, VBS launcher, or
hard-coded author account. A SYSTEM task does not automatically display UI on the user's desktop.
If your existing workflow requires ServiceUI or another separately licensed bridge, place it in
`Custom\Payloads` and call it from the custom hook.

### Using your existing post-enrollment runner

If you already have a reliable first-login runner, set `PostEnroll Enabled="false"` to avoid a
second scheduled task. The installer still stages the standalone runner, module, schema, and
configuration. Your existing elevated PowerShell workflow can call:

```powershell
$debloatScript = "$env:ProgramData\EnterpriseAutopilotBranding\Runtime\Invoke-Debloat.ps1"
& $debloatScript -Mode Enforce -Confirm:$false
if ($LASTEXITCODE -ne 0) {
    throw "Post-enrollment debloat failed with exit code $LASTEXITCODE."
}
```

Keep the configuration in Audit mode until the report from representative Dell models is approved.

## Configuration guidance

### Package version

Always increment the root `PackageVersion` when changing:

- PowerShell code
- Config.xml behavior or catalogs
- Branding assets
- Custom post-enrollment content

The build script synchronizes that version into the generated Intune detection script.

### Registry ownership

The XML contains separate `DefaultUserRegistry` and `MachineRegistry` collections. Disable an entry
when Intune manages the same setting. Applying the same setting from both places makes ownership and
troubleshooting ambiguous.

The OneDrive namespace entry is disabled because that CLSID can hide the general OneDrive Explorer
node, not exclusively consumer OneDrive.

### Start and taskbar

The undocumented `Start2.bin` path is disabled and deliberately build-bounded. Microsoft documents
the supported Start JSON and taskbar policy options here:

- https://learn.microsoft.com/windows/configuration/start/layout
- https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps

Use the files in `PolicyExamples` as a starting point. Retain the local layout options only when you
specifically need one-time pre-profile seeding and have tested the exact Windows build.

### Time zone

Modes:

- `Unchanged`: make no time-zone changes.
- `Explicit`: set the Windows time-zone ID in `Id`, for example `Eastern Standard Time`.
- `Automatic`: enable Windows location and automatic time-zone services.

There is no public-IP or external geolocation dependency.

## Logging and state

All local operational data is under:

```text
%ProgramData%\EnterpriseAutopilotBranding
```

Important files:

| File | Purpose |
| --- | --- |
| `Logs\EnterpriseAutopilotBranding.log` | Human-readable append-only operational log |
| `Logs\EnterpriseAutopilotBranding.jsonl` | Structured JSON Lines log suitable for collection |
| `State\InstallState.json` | Version, config/runtime hashes, OS context, step results, and completion result |
| `State\Debloat-Device.json` | Device-phase debloat actions |
| `State\Debloat-PostEnroll.json` | First-login debloat actions |
| `State\Debloat-Manual.json` | Standalone catalog results plus sanitized full inventory |
| `State\PostEnrollState.json` | Attempt count and post-enrollment result |

No passwords, tokens, or downloaded content are written to these logs.

## Testing safely

Recommended rollout:

1. Set `Debloat Mode="Audit"`.
2. Run on disposable x64 and ARM64 Windows 11 test devices from each OEM/model family.
3. Review both debloat JSON reports.
4. Enable only confirmed removal entries.
5. Test a fresh Autopilot deployment, a manual rerun, a failed custom hook, and a package upgrade.
6. Change to `Mode="Enforce"` and deploy to a small pilot ring.

The GitHub Actions workflow parses all PowerShell files, runs PSScriptAnalyzer errors, validates the
project, and executes the Pester suite on `windows-latest`.

## Intentionally separate deployments

Keep these out of the branding package so each receives its own version, detection, timeout, and
retry behavior:

- Microsoft 365/Office removal or installation
- Language packs and organization-specific regional settings
- Edge and Chrome updates
- AWS VPN Client and its user profile
- Okta Verify and device-access components
- VC++ runtime
- Windows LAPS policy
- WinGet applications
- Inbox-app updates and Windows Update scans
- Enterprise subscription activation

The `Custom` extension point is available when a first-login dependency truly must be coordinated,
but ordinary applications are still best deployed as separate Intune apps with dependencies.

## License and attribution

Released under the MIT License. See `NOTICE.md` for upstream inspiration and vendor-name notices.
