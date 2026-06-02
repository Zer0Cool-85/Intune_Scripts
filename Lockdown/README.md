# Windows Termination Lockdown for Intune

This package contains a Microsoft Intune Win32 app approach for locking down Windows devices assigned to terminated users when Intune Remediations are not available.

The goal is to prevent the terminated user from continuing to use the device with cached credentials or an existing profile while still allowing IT to recover the device using a LAPS-managed local admin account such as `WINADMIN`.

## Files

| File | Purpose |
|---|---|
| `Invoke-TerminationLockdown.ps1` | Main install/lockdown script. |
| `Undo-TerminationLockdown.ps1` | Uninstall/rollback script. |
| `Detect-TerminationLockdown.ps1` | Intune Win32 detection script. |
| `README.md` | Usage notes and Intune setup guidance. |

## What the lockdown script does

The main script runs as `SYSTEM` and performs the following actions:

1. Resolves protected local admin accounts, such as `WINADMIN`, to local SIDs.
2. Finds existing user profiles under `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList`.
3. Excludes built-in profiles and protected local admin accounts.
4. Adds target user SIDs to:
   - `SeDenyInteractiveLogonRight`
   - `SeDenyRemoteInteractiveLogonRight`
5. Removes target user SIDs from:
   - `Administrators`
   - `Remote Desktop Users`
6. Backs up any removed local group memberships to:
   - `C:\ProgramData\Company\TerminationLockdown\RemovedLocalGroupMembership.json`
7. Optionally sets cached domain logons to `0`.
8. Optionally forces BitLocker recovery on next boot.
9. Optionally adds TPM+PIN BitLocker pre-boot authentication.
10. Optionally logs off active interactive sessions.
11. Optionally restarts the device.
12. Writes an Intune detection marker to:
   - `HKLM:\SOFTWARE\Company\TerminationLockdown`

## Recommended Intune packaging

Package these files together with the Microsoft Win32 Content Prep Tool:

```powershell
IntuneWinAppUtil.exe -c "C:\Path\TerminationLockdown" -s "Invoke-TerminationLockdown.ps1" -o "C:\Path\Output"
```

Create a Win32 app in Intune:

| Setting | Recommended value |
|---|---|
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Assignment | Required to a dedicated terminated-device group |
| Detection | Custom detection script using `Detect-TerminationLockdown.ps1` |

Recommended device group example:

```text
INTUNE-WIN-Terminated-Device-Lockdown
```

## Recommended install command

This is the recommended production command for a strong termination lockdown:

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File ".\Invoke-TerminationLockdown.ps1" -DisableCachedDomainLogons -LogoffInteractiveSessions -ForceBitLockerRecoveryOnNextBoot -BackupBitLockerRecoveryKeyToAAD -RestartAfterLockdown -RestartDelaySeconds 60
```

This command:

- Blocks the terminated user locally.
- Blocks RDP logon.
- Disables cached domain logons.
- Forces BitLocker recovery on next boot.
- Attempts to back up BitLocker recovery keys to Entra ID.
- Logs off active users.
- Restarts the device after 60 seconds.

## Safer test command

Use this first on a test PC so it does not immediately reboot:

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File ".\Invoke-TerminationLockdown.ps1" -DisableCachedDomainLogons
```

To include session logoff during testing:

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File ".\Invoke-TerminationLockdown.ps1" -DisableCachedDomainLogons -LogoffInteractiveSessions
```

## Optional TPM+PIN mode

TPM+PIN mode is supported, but it is **not** the recommended default unless IT has a secure way to escrow or retrieve the PIN.

Example:

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File ".\Invoke-TerminationLockdown.ps1" -DisableCachedDomainLogons -LogoffInteractiveSessions -EnableBitLockerTpmPin -PreBootPin "12345678" -RemoveTpmOnlyProtector -BackupBitLockerRecoveryKeyToAAD -RestartAfterLockdown -RestartDelaySeconds 60
```

Do not use a shared static PIN in production unless your organization explicitly accepts that risk.

For most termination scenarios, prefer:

```powershell
-ForceBitLockerRecoveryOnNextBoot
```

instead of TPM+PIN.

## Recommended uninstall command

Use this as the Intune Win32 uninstall command:

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File ".\Undo-TerminationLockdown.ps1" -RestoreCachedDomainLogons -RestoreBitLockerTpmProtector -RemoveDetectionRegistryKey
```

This removes target SIDs from the deny-logon rights, restores cached logons to the configured value, restores a TPM-only BitLocker protector if needed, and removes the detection registry key.

## Optional uninstall command with local group restore

Only use this when a device was accidentally targeted and you want to attempt restoring group memberships that the install script removed:

```powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File ".\Undo-TerminationLockdown.ps1" -RestoreCachedDomainLogons -RestoreRemovedLocalGroupMembership -RestoreBitLockerTpmProtector -RemoveDetectionRegistryKey
```

Restoring local group membership is intentionally optional because blindly restoring local admin or RDP access can be risky.

## Detection script

Use `Detect-TerminationLockdown.ps1` as the custom Intune detection script.

The app is detected when:

```powershell
HKLM:\SOFTWARE\Company\TerminationLockdown\State = Locked
```

The app is not detected after the uninstall script removes the registry key.

## Logs

Main lockdown logs:

```text
C:\ProgramData\Company\TerminationLockdown\Lockdown.log
```

Rollback logs:

```text
C:\ProgramData\Company\TerminationLockdown\Rollback.log
```

Bootstrap logs, useful when the main log is not created:

```text
C:\Windows\Temp\Invoke-TerminationLockdown-Bootstrap.log
C:\Windows\Temp\Undo-TerminationLockdown-Bootstrap.log
```

Intune Management Extension logs:

```text
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log
```

## Protected local admin account

By default, the script protects this account:

```text
WINADMIN
```

It protects the account by resolving it to the local SID on each device. This is safer than relying only on the profile folder name because Windows profile folders can become names like:

```text
C:\Users\WINADMIN.DESKTOP123
C:\Users\WINADMIN.000
```

To use a different LAPS admin account, edit the default value in both scripts or pass the account as a parameter:

```powershell
-AllowedLocalAdminAccounts WINADMIN
```

Multiple accounts are supported:

```powershell
-AllowedLocalAdminAccounts WINADMIN,LocalITAdmin
```

## Return codes

| Exit code | Meaning |
|---|---|
| `0` | Success |
| `1` | Failure |

## Operational recommendation

For normal offboarding:

1. Disable the user in your identity provider.
2. Revoke sessions/tokens.
3. Add the user's assigned Windows device to the terminated-device lockdown group.
4. Trigger device sync/restart where possible.
5. Recover the physical device.
6. Use LAPS account `.\WINADMIN` to sign in after recovery.
7. Rebuild, wipe, or Autopilot Reset before reassignment.

For high-risk or unrecoverable devices, consider Intune Wipe or Defender for Endpoint isolation instead of only local lockdown.

## Safety notes

- Test on spare hardware first.
- Do not add broad principals such as `Users`, `Everyone`, or `Administrators` to deny-logon rights.
- Deny rights override allow rights.
- If BitLocker recovery is forced, IT will need the BitLocker recovery key to boot the device.
- Do not use TPM+PIN mode unless PIN handling is operationally secure.
