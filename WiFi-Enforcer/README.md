# Office Wi-Fi Enforcer for Intune

A configurable Win32 app that installs a scheduled task running as SYSTEM. Version 1.1.0 keeps the new office SSID configured to connect automatically and lets you choose whether listed legacy SSIDs are retained with automatic connection disabled or removed. It does not require Intune Remediations licensing.

Only the new SSID and the legacy SSIDs explicitly listed in your configuration are eligible for profile changes. The previous option to change automatic-switch behavior on other saved networks has been removed.

| Network/profile | Behavior |
|---|---|
| `PreferredSsid` | Set Connect Automatically on, disable switching away, and maintain priority 1. |
| SSIDs in `LegacySsids` | Apply `DisableAutoConnect` or `Remove`, as configured. |
| Unlisted home, hotspot, or remote SSIDs | Preserve their profile XML/settings. Never explicitly switch away from them. |
| A profile containing both a listed and unlisted SSID | Leave the whole profile unchanged. |

Moving the preferred profile to the top changes its position in the list; the relative order of unlisted profiles is preserved. Windows can still make normal automatic connection decisions when networks appear/disappear. The app does not rewrite unlisted profiles or issue a forced connection away from them.

Scope is based on exact SSID names, not location: a network using an explicitly listed SSID is in scope wherever the device is.

The download contains editable source and a packaging helper. Run the helper on Windows with Microsoft's Content Prep Tool to create your tenant's `.intunewin` after entering your actual SSIDs. It does not create a Wi-Fi authentication profile or package credentials. Deploy the new connection and any certificates through your existing Intune Wi-Fi configuration first, or alongside this app.

## Configure your SSIDs

Edit `Source/config.json`. These are the fields you must review:

```json
{
  "ConfigurationReady": true,
  "PolicyVersion": "1.1.0",
  "PreferredSsid": "Your-New-Office-SSID",
  "PreferredProfileName": "",
  "LegacySsids": ["Your-Old-Office-SSID", "Another-Old-SSID"],
  "EnforcementIntervalMinutes": 15,
  "LegacySsidAction": "DisableAutoConnect",
  "ConnectWhenVisible": false,
  "MinimumSignalQuality": 40,
  "ConnectionAttemptCooldownMinutes": 30,
  "ConnectionTimeoutSeconds": 25,
  "RequireSuccessfulPreferredConnectionBeforeRemoval": true
}
```

The shipped file deliberately has `ConfigurationReady: false` and placeholder SSIDs. Build and install refuse to proceed until those are replaced. Use `[]` for `LegacySsids` to manage only the new network.

For your requested behavior, keep `LegacySsidAction` set to `DisableAutoConnect` and `ConnectWhenVisible` set to `false`. The listed old networks remain saved with their credentials and can be selected manually. Their automatic-switch flag is also set to false because Windows requires that for manual profiles. The new office profile is repeatedly set to automatic; there is no configuration option that turns its automatic connection off. [Windows connection-mode and autoSwitch rules](https://learn.microsoft.com/en-us/windows/win32/nativewifi/wlan-profileschema-wlanprofile-element#autoswitch)

To remove the listed old networks instead, change just this field:

```json
"LegacySsidAction": "Remove"
```

| Setting | Behavior |
|---|---|
| `PreferredSsid` | Actual network SSID. Matching uses its UTF-8 bytes and is case-sensitive. Maximum 32 bytes. |
| `PreferredProfileName` | Leave empty to find the profile by SSID. If multiple saved profiles match, enter the exact desired saved profile name. |
| `LegacySsids` | Exact SSIDs eligible for the selected action. No wildcard expansion. Every SSID in a profile must be on this list before the profile is modified. |
| `LegacySsidAction` | `DisableAutoConnect` (default) retains profiles with `connectionMode=manual` and `autoSwitch=false`; `Remove` deletes eligible profiles after the removal safeguards pass. |
| `PolicyVersion` | Your deployment revision; increment when updating the configuration, for example `1.1.1`. |
| `EnforcementIntervalMinutes` | 5–1440 minutes; default 15. Also runs once after install and one minute after startup or logon. |
| `ConnectWhenVisible` | Default false: no explicit connection requests. When true, connect to the new network only from an identifiable, fully listed all-user legacy profile or a known disconnected state. Never force a switch from an unlisted connection. |
| `MinimumSignalQuality` | 0–100 Windows signal-quality percentage for scripted connection attempts. Default 40. This is not RSSI in dBm. |
| `ConnectionAttemptCooldownMinutes` | Minimum time between explicit attempts on an adapter; default 30. Applies to successful and failed attempts. |
| `ConnectionTimeoutSeconds` | Wait for Windows to report the preferred SSID connected; default 25. |
| `RequireSuccessfulPreferredConnectionBeforeRemoval` | Applies only to `Remove`. Default true: observe the new SSID connected on that adapter before deletion. Proof is retained for later offsite cleanup and reset on config changes. Disable mode needs the new saved profile but does not need connection proof. |

Windows can switch automatically independently of the task. The signal threshold and cooldown govern this package's explicit attempts, not Windows AutoConfig's own decisions.

## What runs on the device

1. Enumerate wireless adapters and saved profiles using the Windows WLAN API.
2. Resolve the new SSID to one all-user infrastructure profile. If it is missing or ambiguous, defer changes on that adapter.
3. Enable automatic connection and disable switching away on the preferred profile. Never enable autoSwitch on unrelated profiles.
4. Move the preferred profile to the first position, provided there are no overriding Group Policy profiles.
5. In `DisableAutoConnect` mode, set only eligible listed legacy profiles to manual connection and autoSwitch=false. If explicit switching is off, finish without querying connection/availability or waiting for migration proof. Even a currently connected listed legacy profile can have these saved settings updated; no disconnect command is issued.
6. If explicit switching is enabled, first check that the active connection is an eligible listed legacy profile or the adapter is disconnected. Check availability, signal, and cooldown, then recheck the active connection immediately before connecting. No explicit scan is requested.
7. In `Remove` mode, verify the new connection when required, then delete eligible inactive legacy profiles. If connection state is unknown or a connection attempt fails, retain the old profile. A successful connection request alone is not considered proof.

Connection proof means Windows reports Wi-Fi connected to the SSID. It does not validate DHCP, DNS, internet access, or corporate application access. Test those with your new Wi-Fi policy before broad rollout.

If an attempt leaves the adapter disconnected, the task requests reconnection to the previous saved profile when its name is known. This is best effort; credentials and network availability still determine the result. Active old connections are retained rather than intentionally disconnected for deletion.

Profiles containing both a legacy SSID and an unrelated SSID are not modified at all. Group Policy and per-user profiles are not edited. No passwords, keys, or profile XML are written to the runtime logs or state files.

## Build the Intune package

Use a Windows computer with Windows PowerShell 5.1. The managed runtime targets Windows 10/11 x64 and requires FullLanguage mode for the native WLAN helper. PowerShell 7 is not required on endpoints.

1. Download [Microsoft's Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool). Keep `IntuneWinAppUtil.exe` outside this project's `Source` folder.
2. Edit `Source/config.json` as above.
3. From the extracted project folder, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-IntuneWin.ps1 -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe'
```

The build produces:

| Output | Use |
|---|---|
| `Output/Install.intunewin` | Upload as the Windows app (Win32) content. |
| `Output/Detect-OfficeWiFi.ps1` | Upload as the app's custom detection script. |
| `Output/build-info.json` | Configuration and payload hashes for your build record. |

The detection script is generated from your actual configuration and source hashes. Do not upload `Tools/Detection.template.ps1`. Do not edit source files after building; rebuild both content and detection after any change. Sign scripts before building if your organization requires signatures.

`-PrepareOnly` validates configuration and generates detection/build metadata without creating an `.intunewin`:

```powershell
.\Build-IntuneWin.ps1 -PrepareOnly
```

The official packaging tool includes the contents of its source directory, so keep build output separate. [Microsoft packaging documentation](https://learn.microsoft.com/en-us/intune/app-management/deployment/create-win32-package)

## Add the app in Intune

Create a **Windows app (Win32)** and upload `Output/Install.intunewin`.

| Intune setting | Value |
|---|---|
| Name | Office Wi-Fi Enforcer |
| Install command | `Install.cmd` |
| Uninstall command | `Uninstall.cmd` |
| Install behavior | System |
| Device restart behavior | No specific action |
| Allow available uninstall | No for a required enforcement app |
| Architecture | x64 |
| Minimum OS | A Windows version supported by your organization and Intune |
| Detection rule format | Use a custom detection script |
| Detection script | `Output/Detect-OfficeWiFi.ps1` |
| Run detection as 32-bit process on 64-bit clients | No |
| Enforce detection signature check | Follow your signing policy; No for the unsigned download |
| Assignment | Required, initially to a small device pilot group |
| Return codes | 0 = success; 1 = failed. No reboot codes are emitted. |

The CMD launchers select 64-bit Windows PowerShell when launched from Intune's 32-bit context. They also avoid relying on environment-variable expansion in Intune's uninstall command field.

Detection checks the installed version, exact configuration and payload hashes, and an enabled SYSTEM task with the expected action and recurring triggers. It detects the installed enforcement mechanism, not whether the computer is currently in the office. An offsite laptop or a device still waiting for its Wi-Fi profile can correctly show **Installed**.

Intune custom detection requires exit code zero plus output; the generated script emits output only when installed. Intune configuration profiles cannot be added as Win32 app dependencies. The runtime's missing-profile retry handles independent Wi-Fi-policy delivery. [Microsoft Win32 deployment and detection documentation](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)

In the Intune profile for the new SSID, set automatic connection to **Yes** and **Connect to more preferred network if available** to **No**. For listed legacy profiles retained in disable mode, set automatic connection to **No** in their original Intune profiles too. This prevents policy refresh from undoing the task's setting. Keep those assignments if you want Intune to retain the profiles; removing an assignment can remove a managed Wi-Fi profile. In remove mode, remove obsolete assignments so profiles stop being provisioned. Do not apply these settings to home/remote profiles. [Intune Wi-Fi settings](https://learn.microsoft.com/en-us/intune/device-configuration/templates/ref-wifi-settings-windows), [profile removal behavior](https://learn.microsoft.com/en-us/intune/device-configuration/troubleshoot-device-profiles)

## Schedule and installed files

The task is `\OfficeWiFi-Enforcer`, with a SYSTEM service-account principal and highest privileges. It runs at install, one minute after startup, one minute after logon, and at the configured interval indefinitely. It runs on battery, does not require network availability, does not wake sleeping devices, and ignores overlapping task launches. A runtime file lock also coordinates with install/uninstall. Each invocation has a five-minute task limit.

The task is created through the Task Scheduler COM API. Its repeating trigger has no duration or end date; no maximum-DateTime workaround or task XML file is used. [Task Scheduler repetition documentation](https://learn.microsoft.com/en-us/windows/win32/taskschd/repetitionpattern)

| Location | Contents |
|---|---|
| `%ProgramFiles%\OfficeWiFiEnforcer` | Runtime scripts, native API source, config, and install manifest. |
| `%ProgramData%\OfficeWiFiEnforcer\enforcement.jsonl` | JSON-lines log; rotates at 5 MB with three retained generations. |
| `%ProgramData%\OfficeWiFiEnforcer\last-status.json` | Most recent runtime result, including waiting or restricted states. |
| `%ProgramData%\OfficeWiFiEnforcer\state.json` | Per-adapter migration proof and connection-attempt cooldown. |
| `%ProgramData%\OfficeWiFiEnforcer\install.log` | Most recent installer transcript. |
| `HKLM\SOFTWARE\OfficeWiFiEnforcer` | Installation metadata. |

Only Administrators and SYSTEM can change the installed code and configuration. Runtime state and logs are restricted to those principals. Users cannot edit the scheduled task to substitute code. Local administrators can still change or remove the app; this is administrative enforcement, not protection against a local administrator.

## Verify on a Windows pilot

Before installing, preview proposed changes from an elevated Windows PowerShell session:

```powershell
.\Source\Enforce-OfficeWiFi.ps1 -AuditOnly -Verbose
```

Audit mode does not change WLAN profiles or install a task. It uses the current process's profile visibility, so compare with the deployed SYSTEM task for your final result.

Install locally with `Source\Install.cmd`, then inspect:

```powershell
Get-ScheduledTask -TaskName 'OfficeWiFi-Enforcer'
Get-ScheduledTaskInfo -TaskName 'OfficeWiFi-Enforcer'
Get-Content "$env:ProgramData\OfficeWiFiEnforcer\last-status.json" -Raw
Get-Content "$env:ProgramData\OfficeWiFiEnforcer\enforcement.jsonl" -Tail 20
netsh wlan show profiles
```

Trigger another enforcement run:

```powershell
Start-ScheduledTask -TaskName 'OfficeWiFi-Enforcer'
```

Verify these deployment behaviors:

| Scenario | Expected outcome |
|---|---|
| New profile/certificate not delivered yet | App installs; task waits; legacy profiles remain. |
| Offsite in default disable mode | New profile automatic; listed legacy profiles manual; unlisted profile settings unchanged. No connection proof needed. |
| New SSID in range while using an unlisted home/hotspot connection | No explicit switch away from the unlisted connection, even if switching is enabled. |
| Using a listed legacy connection with explicit switching enabled | Switch only after availability checks; disable or remove according to the selected action. |
| Remove mode before the first verified new-SSID connection | Initial deletion waits. |
| Old profile is recreated or automatic connection re-enabled | A later run reapplies the configured action. |
| Reboot, logon, battery operation | Task triggers and retries as configured. |

To identify a saved profile name when several refer to the same SSID, use `netsh wlan show profiles`, then `netsh wlan show profile name="Profile Name"`. Do not add `key=clear`; this workflow does not need passwords.

## Windows limitations and troubleshooting

- **Device/all-user scope:** deploy the new Wi-Fi profile at device scope. A SYSTEM process does not operate in every user's private WLAN profile context. This app deliberately skips per-user profiles rather than claiming to clean all user stores.
- **Group Policy:** GPO Wi-Fi profiles are read-only and can take precedence. The app records that condition; fix the original GPO to achieve the intended ordering. [Windows profile behavior](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/nf-wlanapi-wlangetprofile), [profile ordering](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/nf-wlanapi-wlansetprofileposition)
- **Connection preference:** the new profile stays automatic and first in the preference list. With explicit switching off, a current manual connection can remain until the user changes networks or Windows reconnects. This version never enables autoSwitch on unlisted networks. Optional explicit switching is limited to eligible listed legacy profiles and disconnected adapters. [Windows WLAN connection behavior](https://learn.microsoft.com/en-us/windows/win32/nativewifi/wlan-profileschema-wlanprofile-element#autoswitch)
- **Windows Wi-Fi information access:** newer Windows versions can restrict available-network and current-connection queries based on location/access policy. The package uses Microsoft's SSID-only WinRT alternative when the native current-connection query fails. If availability still cannot be read, it defers explicit switching; if the active connection is unknown, it defers deletion. It does not modify privacy settings. [Microsoft Wi-Fi API access changes](https://learn.microsoft.com/en-us/windows/win32/nativewifi/wi-fi-access-location-changes)
- **Hidden networks:** explicit switching requires an entry in Windows' available-network list. Provision hidden-network settings through the Wi-Fi profile; the task does not blindly probe a hidden SSID.
- **Service stopped/radio disabled/no adapter:** no service startup type or radio state is overridden. The next scheduled invocation retries.
- **PowerShell control policies:** the runtime uses `Add-Type` to load a small native API wrapper. App Control/WDAC, AppLocker, or Constrained Language restrictions must allow that code through your organization's normal policy. Execution-policy bypass does not bypass those controls.
- **Manual connection remains available:** disable mode retains profiles and credentials; users can still select those listed legacy networks manually. Remove mode periodically forgets eligible inactive old profiles. Neither mode adds an SSID block filter.

An `Enforced` status means that invocation completed its configured work. Windows, a user, or another policy can subsequently change the state; the task re-evaluates on its next run. Review per-adapter status for waiting/restricted cases. Task exit 0 includes expected deferrals, while exit 1 signals a runtime error. Use the JSON status for the reason.

## Change the policy or upgrade

For a 1.0.0-to-1.1.0 upgrade, start with the new `Source/config.json`, copy in your SSIDs, select `LegacySsidAction`, and set `ConfigurationReady` to true. The obsolete `EnableAutoSwitchOnOtherAutoProfiles` field is rejected with an upgrade message. The task name and installation location stay the same.

Version 1.0.0 could enable autoSwitch on other all-user automatic profiles. If it was already deployed, those earlier changes are not automatically undone: the original values were not recorded, and guessing them would change unlisted networks again. Version 1.1.0 stops making those changes. Likewise, a profile deleted by the earlier version cannot be recovered by switching to disable mode; reprovision it if it should remain available manually.

Edit the source configuration, increment `PolicyVersion`, and rerun the build. Update the **same Intune app** with both the new `.intunewin` and the newly generated detection script. Installation replaces the runtime and updates the existing task. The changed config hash resets connection proof and cooldown so the new policy is validated again.

Do not leave two different required versions of this app targeting the same device: exact-content detection would cause conflicting reinstall attempts. If you use separate app objects, manage assignments/supersedence so only the intended policy remains required.

## Uninstall and rollback

Use an Intune Uninstall assignment with `Uninstall.cmd`, or run `Source\Uninstall.cmd` as administrator. The installed fallback is:

```powershell
& "$env:ProgramFiles\OfficeWiFiEnforcer\Uninstall-OfficeWiFi.ps1"
```

Uninstall stops/deletes the task, removes installed code and registry metadata, and removes migration state. It retains logs by default; add `-PurgeLogs` to the PowerShell uninstall command to remove them.

Uninstall **does not re-enable automatic connection on legacy profiles, restore deleted profiles, or revert ordering/automatic-switch settings**. Reprovision or update the explicitly managed connections through Intune if you want to roll back those settings. This package intentionally stores no credential-bearing profile backups. Remove the app's Required assignment when retiring it so Intune does not reinstall it.

## Source and validation

| File | Purpose |
|---|---|
| `Source/Install-OfficeWiFi.ps1` | Validate configuration, protect runtime directories, install/update task and metadata. |
| `Source/Enforce-OfficeWiFi.ps1` | Scheduled entry point, logging, lock, state persistence, exit codes. |
| `Source/OfficeWiFi.psm1` | Configuration validation and enforcement decisions. |
| `Source/NativeWifi.cs` | Windows WLAN profile enumeration, exact deletion, ordering, availability, and connection calls. |
| `Source/Uninstall-OfficeWiFi.ps1` | Remove enforcement and optionally logs. |
| `Source/Install.cmd`, `Source/Uninstall.cmd` | Intune command launchers. |
| `Tools/Detection.template.ps1` | Build-time template for standalone Intune detection. |
| `Build-IntuneWin.ps1` | Generate detection and invoke Microsoft's content-prep tool. |
| `Tests/Test-Logic.ps1` | Offline behavior tests using a fake WLAN client. |
| `Tests/Test-Syntax.ps1` | Parse PowerShell, compile the C# helper, and check native structure layouts. |

Tests do not change the machine's Wi-Fi settings or scheduled tasks:

```powershell
.\Tests\Test-Syntax.ps1
.\Tests\Test-Logic.ps1
```

See `VALIDATION.md` for the checks completed for this release and the platform limitations.
