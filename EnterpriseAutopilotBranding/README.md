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
- PSAppDeployToolkit 4.1.8 displays a step counter and pending/running/completed list from the SYSTEM
  task without `ServiceUI.exe`.
- Device- and user-scoped onboarding state is persisted after every step, so interrupted setup
  resumes at the first incomplete critical step.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Install-AutopilotBranding.ps1` | SYSTEM-context installer and step orchestrator |
| `Config.xml` | Branding, OS configuration, debloat catalog, and post-enrollment settings |
| `Config.xsd` | Strict configuration schema used by validation and XML-aware editors |
| `Modules/EnterpriseAutopilotBranding.psm1` | Shared implementation and logging functions |
| `Invoke-PostEnroll.ps1` | Manifest-driven, retry/resume first-login SYSTEM worker |
| `Invoke-Debloat.ps1` | Standalone, confirmation-gated debloat audit/enforcement runner |
| `Onboarding` | Pinned PSADT 4.1.8 host, secure user-session UI, and third-party license |
| `Custom/Steps/Install-AwsVpn.ps1` | Optional wrapper for an existing AWS VPN PSADT package |
| `Custom/PostEnroll.Custom.ps1` | Optional organization-owned PowerShell step template |
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
4. Review `<PostEnroll><ExcludedUsers>` and add technician, break-glass, or staging accounts that
   must not claim the one-time onboarding workflow.
5. Add or enable versioned `<PostEnroll><Steps>` entries. To use the bundled AWS wrapper, copy your
   complete package beneath `Custom\Payloads\AWSVPN_PSADT` and enable `AwsVpn.Install`.
6. Increment `PackageVersion` whenever code, configuration, or assets change. Increment an
   individual onboarding step's `Version` whenever that step changes.
7. Run validation from 64-bit Windows PowerShell 5.1:

   ```powershell
   .\Validate-Project.ps1
   ```

8. Create the source ZIP and versioned detection script:

   ```powershell
   .\Build-IntuneWin.ps1
   ```

9. To also create the Intune package, download Microsoft's official
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
dist\Detect-AutopilotBranding-4.1.0.ps1
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

## First-login onboarding task

The installer stages the complete offline runtime under:

```text
%ProgramData%\EnterpriseAutopilotBranding\Runtime
```

It then registers `\EnterpriseAutopilotBranding\PostEnroll` as SYSTEM with highest privileges,
an any-user logon trigger, a two-minute delay, a four-hour execution ceiling, and Ignore New
multiple-instance behavior. When UI is enabled, the task starts the pinned PSADT 4.1.8 launcher in
Interactive mode. PSADT's client/server model displays the Fluent progress surface in the active
session without a ServiceUI token bridge.

The default UI shows:

- `Step n of total` plus the current action.
- The full configured list with pending, running, completed, and warning markers.
- Percentage progress.
- A success prompt, and Restart now/Restart later choices only when a completed step reports exit
  code `1641` or `3010` (or the debloat engine reports a restart requirement).
- A retry message after a critical failure.

The UI is presentation only. `Invoke-PostEnroll.ps1` remains the authoritative SYSTEM worker and
writes each result immediately beneath `State\PostEnroll`. A crash, user sign-out, process timeout,
or reboot therefore resumes from the first unsatisfied step version. A named global mutex prevents
overlapping task and manual executions.

### Step manifest

Enabled `<Step>` entries run in XML order. Supported handlers are:

| Handler | Purpose |
| --- | --- |
| `Debloat` | Runs the existing first-login Appx/classic cleanup catalog |
| `PowerShell` | Executes an idempotent script with standard context parameters |
| `WaitForFile` | Waits for a separately deployed app's detection file |
| `WaitForApplication` | Waits for a matching HKLM uninstall-registry display name |

`Scope="Device"` PowerShell steps run as SYSTEM. `Scope="User"` PowerShell steps use PSADT's
active-user process launcher and run unelevated as that user. Use user scope only for HKCU,
`%APPDATA%`, shortcuts, or other profile-specific work; machine-wide installers belong in device
scope.

Every step has its own `Id` and `Version`. Changing the root package version repairs the staged
runtime, while changing a step version is what deliberately reruns that step. Critical failures
keep the task registered and stop later steps. Noncritical failures are recorded as warnings and do
not block completion. The project defaults `UnregisterAfterMaximumAttempts="false"` so a transient
network or installer failure is not silently converted into permanent success.

### AWS VPN and future applications

For normal lifecycle management, keep AWS VPN and future applications as separate Intune Win32
apps with their own detection, dependencies, supersedence, assignments, and reporting. An
onboarding `WaitForFile` or `WaitForApplication` step can visibly wait for a Required app delivered
by Intune without taking ownership of that app's installer.

When exact first-login sequencing is mandatory, the disabled `AwsVpn.Install` example can launch
your existing PSADT package. Copy the whole package to:

```text
Custom\Payloads\AWSVPN_PSADT
```

Then enable the step and increment its version. The wrapper detects the client before and after
installation, accepts only `0`, `1641`, and `3010`, enforces a timeout, and fails honestly when the
payload or final detection is missing. The AWS installer is not included.

Do not put Office removal or speculative OEM uninstall switches back into this first-login path.
Office/OneDrive removal should remain separately detected device work, and Dell cleanup should use
the guarded catalog already in this repository.

### Self-deploying Autopilot and primary user

Microsoft does not automatically assign a primary user to devices provisioned through Autopilot
self-deploying mode. This onboarding task therefore does not query or wait for Intune primary-user
state; it uses the eligible local interactive session and maintains separate Device and per-SID
state. Your existing hourly Graph reconciliation can continue setting the most frequent logged-in
user independently:

https://learn.microsoft.com/autopilot/self-deploying

Review `<ExcludedUsers>` before production. A technician, staging, LAPS, or break-glass account
that is allowed through can otherwise complete the one-time user portion before the eventual owner
arrives. The sample already excludes `defaultuser0`, built-in Administrator, `WINADMIN`, and
`WDAGUtilityAccount`.

Computer renaming is intentionally absent. The old script assumed `first.last`, failed for many
valid usernames, generated a new random suffix on retry, and could name a device for a technician
who was not later selected as primary user. Apply a deterministic serial-based name during the
device phase, or perform user-derived naming from the server only after the same primary-user
algorithm has selected the owner.

If a separate first-login controller remains in use, set `PostEnroll Enabled="false"` to prevent a
second task. The standalone debloat runner remains available for controlled maintenance.

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
| `Logs\PSADT` | PSADT session and secure UI-host logs |
| `State\InstallState.json` | Version, config/runtime hashes, OS context, step results, and completion result |
| `State\Debloat-Device.json` | Device-phase debloat actions |
| `State\Debloat-PostEnroll.json` | First-login debloat actions |
| `State\Debloat-Manual.json` | Standalone catalog results plus sanitized full inventory |
| `State\PostEnrollState.json` | Latest onboarding run, attempt count, current user, warnings, and result |
| `State\PostEnroll\Device.json` | Durable device-scoped result for each step ID/version |
| `State\PostEnroll\Users\<SID>.json` | Durable user-scoped result for each eligible Windows SID |

No passwords, tokens, or downloaded content are written to these logs.

## Testing safely

Recommended rollout:

1. Set `Debloat Mode="Audit"`.
2. Run on disposable x64 and ARM64 Windows 11 test devices from each OEM/model family.
3. Review both debloat JSON reports.
4. Enable only confirmed removal entries.
5. Test a fresh self-deploying Autopilot deployment, an excluded technician sign-in, the intended
   user's first sign-in, a forced manual rerun, a mid-step failure, a reboot, and a step-version
   upgrade.
6. Confirm the Graph primary-user job remains independent and that the local workflow does not
   rename the computer for a staging account.
7. Change to `Mode="Enforce"` and deploy to a small pilot ring.

The GitHub Actions workflow parses all PowerShell files, runs PSScriptAnalyzer errors, validates the
project, and executes the Pester suite on `windows-latest`.

## Intentionally separate deployments

Keep these out of the branding package so each receives its own version, detection, timeout, and
retry behavior:

- Microsoft 365/Office removal or installation
- Language packs and organization-specific regional settings
- Edge and Chrome updates
- AWS VPN Client and its user profile, unless exact onboarding-owned sequencing is explicitly used
- Okta Verify and device-access components
- VC++ runtime
- Windows LAPS policy
- WinGet applications
- Inbox-app updates and Windows Update scans
- Enterprise subscription activation

The `Custom` extension point is available when a first-login dependency truly must be coordinated,
but ordinary applications are still best deployed as separate Intune apps with dependencies.

## License and attribution

Organization-authored project code is released under the MIT License. The bundled
PSAppDeployToolkit runtime remains under LGPL-3.0; its license and upstream source notice are
preserved beneath `Onboarding\PSAppDeployToolkit` and in `NOTICE.md`.
