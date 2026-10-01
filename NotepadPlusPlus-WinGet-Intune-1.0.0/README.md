# Notepad++ updater for Intune Win32 — 1.0.0

Assign this maintenance app as **Required** to **All devices**. Its requirement
allows only devices with an existing, registered, machine-wide Notepad++ install.
The install script upgrades that installation to the version offered by the
WinGet community source. Detection checks update availability, so later releases
can trigger another update when Intune reevaluates the required app.

## SYSTEM support limitation

This package uses the full-path `winget.exe` workaround under SYSTEM. Microsoft
explicitly states that the **WinGet CLI is not supported under SYSTEM**; its
`Microsoft.WinGet.Client` PowerShell module supports machine-wide packages in
that context. Resolving the executable solves PATH discovery, but cannot guarantee
that App Installer registration, dependencies, or source initialization will work
under SYSTEM on every device. Pilot the package on representative devices before
broad assignment. For a strictly Microsoft-supported implementation, use the
module approach instead of this CLI wrapper.

No PowerShell module or PowerShell 7 is installed by this package. App Installer /
WinGet must already be installed and functional in the SYSTEM context. This
package does not bootstrap or repair WinGet or reset its sources.

## Included files

| File | Use |
| --- | --- |
| `Source/Update-NotepadPlusPlus.ps1` | Package this as the Win32 app installation content. |
| `Requirement-NotepadPlusPlus.ps1` | Upload separately as the additional requirement script. |
| `Detect-NotepadPlusPlusCurrent.ps1` | Upload separately as the custom detection script. |

The requirement and detection scripts are standalone. Intune runs them from its
own script locations; they do not depend on the Win32 content cache.

## 1. Create the .intunewin

Extract this ZIP to `C:\Intune\NotepadPlusPlus-WinGet-Intune-1.0.0`.
Use Microsoft's Win32 Content Prep Tool on a Windows packaging computer:

```powershell
.\IntuneWinAppUtil.exe -c "C:\Intune\NotepadPlusPlus-WinGet-Intune-1.0.0\Source" -s Update-NotepadPlusPlus.ps1 -o "C:\Intune\Output" -q
```

The ZIP contains source files, not a prebuilt `.intunewin`. Keep the output folder
outside `Source` so it is not included recursively in the package.

## 2. Add the Win32 app

In the Intune admin center, add **Windows app (Win32)** and upload the generated
`.intunewin`. Suggested name: **Notepad++ — Update existing installations**.

**Install command:**

```text
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ".\Update-NotepadPlusPlus.ps1"
```

The scripts explicitly read both registry views and resolve the native WinGet
executable from Program Files, so this command also works when Intune starts
32-bit Windows PowerShell. On an x64-only assignment, you may instead launch
`%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe` with the same arguments.

| Program setting | Value |
| --- | --- |
| Install behavior | **System** |
| Installation time required | **60 minutes** |
| Device restart behavior | **Determine behavior based on return codes** |
| Uninstall command | `cmd.exe /c exit /b 0` |
| Allow available uninstall, if shown | **No** |

This is an update-only maintenance app. Its uninstall command is a no-op; it does
not remove Notepad++ or roll back an update. **Do not create an Uninstall
assignment.** To stop future enforcement, remove its Required assignment.

Keep these return-code mappings:

| Code | Intune type | Meaning |
| --- | --- | --- |
| `0` | Success | Already current, or upgrade completed and verified. Also used if Notepad++ was removed before the updater ran. |
| `3010` | Soft reboot | Upgrade verified; installer requested a restart. |
| `1618` | Retry | Notepad++ is open, files are in use, or another installer is busy. |
| `1` | Failed | WinGet missing/unusable, source problem, ambiguous installation, update failure, timeout, or failed verification. |

The script does not request an immediate restart. If an installer requires a
restart before the installed version can be verified, the script fails rather
than falsely declaring the update complete; inspect the log and retry after reboot.

## 3. Requirements

Select the Windows architectures and minimum OS appropriate for your fleet. The
scripts handle x86, x64, and ARM64 App Installer paths. An x86 Notepad++ installation
on an x64 Windows device is also found. Architecture here describes the OS/device,
not the installed Notepad++ edition.

Add one additional requirement of type **Script**:

| Requirement setting | Value |
| --- | --- |
| Script file | `Requirement-NotepadPlusPlus.ps1` |
| Run script as 32-bit process on 64-bit clients | **No** |
| Run using logged-on credentials | **No** |
| Enforce script signature check | **No**, unless you sign the supplied scripts |
| Output data type | **Integer** |
| Operator | **Equals** |
| Value | **1** |

Presence writes `1` and exits `0`. Absence writes `0` and exits `0`, so the
comparison fails and Intune can report **Not applicable**. Returning exit `1`
for ordinary absence would describe a script failure instead of the intended
requirement comparison.

## 4. Detection

Choose **Use a custom detection script**:

| Detection setting | Value |
| --- | --- |
| Script file | `Detect-NotepadPlusPlusCurrent.ps1` |
| Run script as 32-bit process on 64-bit clients | **No** |
| Enforce script signature check | **No**, unless you sign the supplied scripts |

Do not add an additional rule that merely checks for `notepad++.exe`. A presence
check alone could make Intune consider an outdated installation already compliant.

Detection requests a refresh of the `winget` catalog and queries the exact
`Notepad++.Notepad++` package in machine scope. It succeeds only when there is one
matching installation with a known version and no available upgrade reported by
WinGet. It checks the package ID and version fields without depending on English
column headings. Source-column variations are supported; unexpected output fails
closed and is logged.

Reported command failures, timeouts, an unknown installed version, or an unmatched
package do not count as compliant. Detection uses a 20-second limit per WinGet
command; the updater allows longer for initialization and downloads. Catalog
freshness still depends on the WinGet client and source: a client that serves
cached metadata can only describe updates known to that cache. The package does
not independently scrape the vendor's latest release.

There is no permanent success marker or scheduled task. Reevaluation follows
Intune's normal required-app processing, not a precise patching schedule.
Microsoft documents reoffering a required app within approximately 24 hours after
detecting it is absent. Online catalog checks on each evaluation also mean that
network problems can temporarily cause an installation failure/not-detected state.

## 5. Assign and choose open-app behavior

Use a pilot device group first, then change the Required assignment to **All
devices**. Do not add Notepad++ as an automatic-install dependency: that could
install it on computers where it is intentionally absent.

The default install command returns `1618` if an update is needed while Notepad++
is running. Intune retries according to its retry behavior; persistent open
sessions may defer the update until a later evaluation or require user action.

To forcibly terminate open Notepad++ processes before updating, add the switch:

```text
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ".\Update-NotepadPlusPlus.ps1" -ForceCloseNotepad
```

This closes **all Notepad++ sessions**, and can discard unsaved work. The WinGet
`--force` flag is already supplied in both modes; it is separate from closing
running processes and can override package pins/non-security upgrade restrictions.
Installer hash verification remains enabled.

## Scope and diagnostics

- Includes normal machine-wide installations registered in either HKLM uninstall
  view, including installations originally installed outside WinGet.
- Excludes per-user/HKCU installations, portable copies, and copies inside another
  user's profile. Updating those requires a separate user-context approach.
- Multiple registered machine installations are reported as an error for review;
  the package does not guess which architecture/registration to replace.
- A stale uninstall registry entry can pass the requirement, but failure to
  correlate it in WinGet causes the update to fail visibly.
- Uses only `winget upgrade` for `Notepad++.Notepad++`; there is no fresh-install
  fallback, no `upgrade --all`, no source reset, and no ACL changes to WindowsApps.
- Allow SYSTEM access to the configured WinGet community source and the installer
  download URLs in its Notepad++ manifest. User-authenticated proxies can behave
  differently under SYSTEM.
- A 30-minute upgrade timeout stops the WinGet process; an installer it launched
  might remain running. Inspect the device before starting a manual second run.

Logs (one rotated backup retained after 2 MB):

```text
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\NotepadPlusPlus-WinGet-Update.log
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\NotepadPlusPlus-WinGet-Detection.log
```

Review these with the usual Intune Management Extension app logs. Successful
updates include the WinGet exit code and the verified installed version.

## Validation and pilot checks

PowerShell syntax and isolated logic checks are performed during preparation.
A live Windows SYSTEM/Intune deployment cannot be validated in the Linux build
environment. Check these cases on Windows before assigning broadly:

| Device state | Expected result |
| --- | --- |
| No machine-wide Notepad++ | Requirement output `0`; Not applicable; no fresh installation. |
| Old Notepad++, closed | Requirement `1`; update runs; detection succeeds after verification. |
| Current Notepad++ | Requirement `1`; detection succeeds; no installation needed. |
| Old Notepad++, open, default command | Retry `1618`; open processes are retained. |
| Old Notepad++, open, force-close command | Processes terminate; upgrade is attempted. |
| WinGet absent, broken, or blocked | Error logged; not treated as compliant. |
| Source/network failure | Reported failures are logged; no assumed compliance from an error code. |
| Both 32-bit and 64-bit registrations | Error for manual review. |

## References

- [Microsoft: WinGet SYSTEM context limitation](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting#system-context)
- [Microsoft: Intune Win32 requirements and detection](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Microsoft: WinGet list](https://learn.microsoft.com/en-us/windows/package-manager/winget/list)
- [Microsoft: WinGet upgrade](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade)
- [Microsoft: WinGet source](https://learn.microsoft.com/en-us/windows/package-manager/winget/source)
- [Microsoft: WinGet return codes](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md)
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
