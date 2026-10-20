# Post-enrollment Setup UI

**Version 1.0.0 · Windows PowerShell 5.1 · WPF · Your existing SYSTEM + ServiceUI launch**

A configurable, Fluent-inspired first-desktop setup window. Keep your current post-enrollment trigger and replace the popup with this front end. Add your PowerShell code to individual step files; the window handles progress, animation, status, and results.

## Start here

1. Extract the entire ZIP to a local folder on a Windows test PC.
2. Double-click **Run-Demo.cmd**. No administrator rights are needed for the demo.
3. Watch the third step fail intentionally and the dependent fourth step become skipped. Expand its technical details, then choose **Retry unfinished**. The retry succeeds.
4. Edit **Config/Setup.json** to change your company name, welcome text, theme, logo/banner paths, and step labels.
5. Put your actual commands in **Steps/Step-01.ps1** through **Step-10.ps1**. Remove the placeholder `throw` in each step you implement.
6. Disable unused entries with `"Enabled": false`. Reorder the JSON objects to change execution order.
7. Run **Validate-Config.cmd**, then the Windows smoke tests in **Tests/Invoke-SmokeTests.ps1**.
8. Pilot live execution using your existing SYSTEM + ServiceUI workflow with **-Live**. See [deployment instructions](Docs/DEPLOYMENT.md).

**Safe by default:** launching Start-DeviceSetup.ps1 with no mode switch runs a simulation. Only **-Live** executes your step scripts. All ten supplied step scripts deliberately fail in live mode until you replace their placeholders. Demo mode never calls those scripts.

## What is included

| Feature | Behavior |
|---|---|
| 1-10 steps | Independent title, description, script, parameters, time limit, dependencies, and success codes |
| Modern appearance | Light/dark presets, rounded cards, accent color, readable typography, and status badges |
| Branding | Company name, welcome heading/message, optional logo, optional full-width banner, or both |
| Animated status | Spinning current-step indicator; completed checkmarks, failure crosses, and skipped markers |
| Progress | Overall steps-finished bar; optional per-step percentage and live message |
| Details | Expandable errors, elapsed times, run logs, and a copy-details button |
| Retry | Retry failed/skipped steps; leave successful steps alone |
| Resume | Remember successful steps per device, package ID, version, and execution fingerprint |
| Reliability | Separate worker process, responsive UI, time limits, duplicate-run prevention, and JSON results |
| Reboot reporting | Preserve reboot-required success as exit 3010; never initiate a reboot |

This is custom WPF styled to resemble modern Windows. It is **not WinUI 3 or PSADT**, and it has no additional UI framework dependency.

## Files you will usually edit

| File | Purpose |
|---|---|
| Config/Setup.json | Main configuration; starts with 5 enabled and 5 disabled steps |
| Steps/Step-01.ps1 ... Step-10.ps1 | Your actual installation/configuration code |
| Assets/ | Your PNG/JPG/BMP branding files |
| UI/MainWindow.xaml | Optional advanced layout/style changes |
| Run-Live-ServiceUI.cmd | Optional convenience launcher; customize your existing launcher instead if preferred |

## Documentation

- [Configuration reference](Docs/CONFIGURATION.md): all settings and branding examples.
- [Writing steps](Docs/STEP-AUTHORING.md): success/failure rules, progress, parameters, installer examples.
- [Deployment and first-logon integration](Docs/DEPLOYMENT.md): ServiceUI, SYSTEM, Intune staging, state, and exit codes.
- [Testing and troubleshooting](Docs/TESTING.md): validation status, Windows checks, and common issues.
- [Design preview](Docs/Design-Preview.html): HTML visual reference, **not a Windows runtime screenshot**.
- **START-HERE.html**: offline, formatted copy of this documentation.

## Quick commands

From an extracted package folder in Windows PowerShell:

```powershell
# Safe simulation; no step scripts run.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -Demo

# Dark theme example.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -Demo -ConfigPath .\Config\Dark-Demo.json

# All 10 steps enabled, to inspect the scrolling layout.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -Demo -ConfigPath .\Config\All10-Demo.json

# Configuration-only check; no UI or steps.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-DeviceSetup.ps1 -ValidateOnly

# Windows tests; no app installs or ServiceUI invocation.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Tests\Invoke-SmokeTests.ps1
```

The demo/config-check CMD launchers choose Sysnative when called from a 32-bit process. The live wrapper instead expects x64 ServiceUI, which launches 64-bit PowerShell through System32.

## Scope and compatibility

- Target: Windows 10/11 x64 with Windows PowerShell 5.1 and the Windows WPF/.NET Framework components.
- The UI requires an STA session. PowerShell 7 is intentionally rejected for the UI to keep one supported host/runtime target.
- Your ServiceUI launcher, first-logon scheduling, and enrollment/ESP readiness checks remain your responsibility.
- This is **device-level** completion tracking. HKCU, APPDATA, and USERPROFILE refer to SYSTEM in a SYSTEM-run step, not the signed-in user.
- ServiceUI.exe and application installers are not included.
- No network calls, telemetry, package downloads, or built-in application changes are performed by the framework. Your live step scripts determine those actions.

## Verification status

Source parsing, configuration checks, XAML/XML structure, resource/element references, package links, and the HTML design reference are checked in the build environment. That environment is Linux, so **Windows PowerShell execution, WPF rendering, ServiceUI session presentation, and real installers have not been run here**. The included Windows smoke tests and pilot checklist cover those remaining checks.
