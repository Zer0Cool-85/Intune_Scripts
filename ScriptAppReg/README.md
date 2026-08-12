# Intune PowerShell App Inventory Registration

A reusable Win32 app wrapper that registers an existing PowerShell-based application in the Windows uninstall registry so Microsoft Intune can inventory it as an installed application.

This project is designed for environments where:

- A custom PowerShell application is already installed on some Windows devices.
- The application does not currently appear in **Settings > Apps > Installed apps** or Intune **Discovered apps**.
- The registration should only be added when reliable application artifacts already exist.
- Intune Remediations is unavailable or unnecessary.

The repository uses one JSON configuration file to generate self-contained install, uninstall, requirement, and detection scripts. This keeps the values used by all four scripts synchronized.

## How it works

| Original application | Registration | Intune result |
| --- | --- | --- |
| Not present | Missing | Not applicable |
| Present | Valid | Installed; no action |
| Present | Missing or invalid | Registration is created or repaired |

The Win32 app is assigned broadly. A custom requirement script checks for the original application's files or scheduled tasks. A custom detection script then validates the uninstall-registry registration.

## Repository structure

```text
.
├── .github/workflows/validate.yml
├── config/AppRegistration.json
├── docs/
│   ├── Intune-Configuration.md
│   └── Troubleshooting.md
├── templates/
│   ├── Detection.ps1.template
│   ├── Install.ps1.template
│   ├── Requirement.ps1.template
│   └── Uninstall.ps1.template
├── tests/Test-Repository.ps1
└── tools/Build-Package.ps1
```

The build process produces:

```text
build/
├── Package/Install.intunewin
├── Rules/
│   ├── Detection.ps1
│   └── Requirement.ps1
└── Source/
    ├── Install.ps1
    └── Uninstall.ps1
```

## Quick start

### 1. Configure the application

Edit [`config/AppRegistration.json`](config/AppRegistration.json). At minimum, update:

- `DisplayName`
- `DisplayVersion`
- `Publisher`
- `InstallLocation`
- `RegistryKeyName`
- `RequiredFiles` and/or `RequiredScheduledTasks`

The configured version must represent the version of the existing application, not merely the version of this registration package.

### 2. Download Microsoft's packaging tool

Download the latest Microsoft Win32 Content Prep Tool from:

<https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool>

Do not copy `IntuneWinAppUtil.exe` into this repository. Pass its location to the build script instead.

### 3. Generate the deployment files

From PowerShell:

```powershell
.\tools\Build-Package.ps1 `
    -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe'
```

To generate and validate the PowerShell files without creating an `.intunewin` package:

```powershell
.\tools\Build-Package.ps1 -SkipIntuneWin
```

### 4. Create the Win32 app

Upload `build\Package\Install.intunewin` as a **Windows app (Win32)** and follow [`docs/Intune-Configuration.md`](docs/Intune-Configuration.md).

## Configuration reference

### Application

| Property | Purpose |
| --- | --- |
| `DisplayName` | Name reported to Windows and Intune inventory. |
| `DisplayVersion` | Actual version of the installed PowerShell application. |
| `Publisher` | Publisher reported to inventory. |
| `InstallLocation` | Existing application directory. |
| `RegistryKeyName` | Stable subkey under the 64-bit uninstall registry path. Do not include a version. |
| `UninstallScriptPath` | Optional real uninstaller for the original application. Leave empty if none exists. |
| `DisplayIconPath` | Optional path to an existing icon or executable. |
| `EstimatedSizeKB` | Optional estimated installed size in KB. Use `0` to omit it. |

### Presence

| Property | Purpose |
| --- | --- |
| `MatchMode` | `All` requires every configured marker; `Any` requires at least one. |
| `RequiredFiles` | Existing files that prove the original application is installed. |
| `RequiredScheduledTasks` | Existing scheduled-task names that prove installation. |

At least one file or scheduled-task marker is required. Prefer markers unique to the application.

### Registration

| Property | Purpose |
| --- | --- |
| `NoModify` | Prevents Windows from offering a Modify operation. |
| `NoRepair` | Prevents Windows from offering a Repair operation. |
| `NoRemove` | Prevents Windows from offering a Remove operation. This does not control Intune's uninstall assignment. |

## Important behavior

- The installer writes to the 64-bit registry view at `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`.
- The installer refuses to create a registration unless the configured presence markers are satisfied.
- The generated `Uninstall.ps1` removes only the inventory registration. It does **not** uninstall the original PowerShell application.
- Devices without the original application should report **Not applicable**, not failed.
- Keep the registry key name stable across releases. Update `DisplayVersion` rather than creating a version-specific key.
- If several versions are already deployed, do not assign the same hardcoded version to all of them. Derive or standardize the real application version first.

## Validation

Run the dependency-free repository tests:

```powershell
.\tests\Test-Repository.ps1
```

The test builds the generated scripts in a temporary directory, parses every PowerShell file, and confirms no unresolved template tokens remain.

## Microsoft documentation

- [Prepare Win32 app content for upload](https://learn.microsoft.com/en-us/intune/app-management/deployment/create-win32-package)
- [Add, assign, and monitor a Win32 app](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Intune Discovered apps](https://learn.microsoft.com/en-us/intune/app-management/discovered-apps)
- [App inventory for Windows devices](https://learn.microsoft.com/en-us/intune/app-management/deployment/enhanced-app-inventory)

## License

This project is available under the [MIT License](LICENSE). Replace the placeholder copyright holder before publishing if needed.
