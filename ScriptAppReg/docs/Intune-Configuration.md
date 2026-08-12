# Intune configuration

These settings deploy the registration package only to devices where the original PowerShell application is already present.

## 1. Build the package

Edit `config\AppRegistration.json`, then run:

```powershell
.\tools\Build-Package.ps1 `
    -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe'
```

The build produces the following deployment files:

- `build\Package\Install.intunewin`
- `build\Rules\Requirement.ps1`
- `build\Rules\Detection.ps1`

## 2. Create the application

In the Microsoft Intune admin center:

1. Go to **Apps > All apps > Create**.
2. Select **Windows app (Win32)**.
3. Upload `build\Package\Install.intunewin`.

Suggested app information:

| Field | Suggested value |
| --- | --- |
| Name | The configured `Package.Name` |
| Description | Registers the existing PowerShell application for Windows and Intune inventory. |
| Publisher | Your organization |
| Show as featured app | No |

## 3. Program settings

### Install command

```text
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Install.ps1
```

Using `Sysnative` forces 64-bit Windows PowerShell when the command is launched by the 32-bit Intune Management Extension process. The generated scripts also explicitly access the 64-bit registry view.

### Uninstall command

```text
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

The uninstall command removes only the inventory registration. It does not remove the underlying PowerShell application.

Configure the remaining Program settings as follows:

| Setting | Value |
| --- | --- |
| Install behavior | System |
| Device restart behavior | No specific action |
| Allow available uninstall | No |
| Installation time required | 15 minutes |

Use the standard success return code `0`.

## 4. Base requirements

Configure your supported architectures and minimum operating system. For a standard Windows 11 fleet:

| Setting | Suggested value |
| --- | --- |
| Operating system architecture | 64-bit |
| Minimum operating system | Your oldest supported Windows 11 release |

## 5. Custom requirement rule

Select **Add** under additional requirement rules:

| Setting | Value |
| --- | --- |
| Requirement type | Script |
| Script file | `build\Rules\Requirement.ps1` |
| Run script as 32-bit process on 64-bit clients | No |
| Run script using logged-on credentials | No |
| Enforce script signature check | Match your organization's signing policy |
| Select output data type | Integer |
| Operator | Equals |
| Value | `1` |

The rule outputs `1` only when the configured existing-application markers are satisfied. Devices that return `0` are **Not applicable**.

## 6. Detection rule

Choose **Use a custom detection script**:

| Setting | Value |
| --- | --- |
| Script file | `build\Rules\Detection.ps1` |
| Run script as 32-bit process on 64-bit clients | No |
| Enforce script signature check | Match your organization's signing policy |

The script validates:

- Registry key existence in the 64-bit uninstall registry view.
- Exact `DisplayName`.
- Exact `Publisher`.
- A `DisplayVersion` greater than or equal to the configured application version.

## 7. Assignments

Assign the Win32 app as **Required** to either:

- The existing device group that received the original application, or
- A broad corporate Windows device group when the original deployment population is unknown.

Broad assignment is safe only when the configured requirement markers uniquely identify the original application.

## 8. Pilot validation

Test these three conditions before broad deployment:

| Test device state | Expected status |
| --- | --- |
| Original application absent | Not applicable |
| Original application present and registration missing | Installed after the registration is created |
| Original application present and registration valid | Installed without rerunning the installer |

After successful installation, validate locally:

```powershell
$key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\YourCompany.AdminElevation'
Get-ItemProperty -LiteralPath $key
```

The application should also appear in Windows Installed apps unless Windows hides it due to local display behavior or registration flags.

## 9. Inventory timing

Legacy Intune Discovered apps Win32 inventory generally refreshes every 24 hours through the Intune Management Extension. Microsoft's newer Windows App inventory feature can collect registry-based inventory multiple times per day after its Properties catalog policy is assigned.
