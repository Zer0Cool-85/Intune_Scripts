# Deploy Python with Microsoft Intune

This guide describes how to deploy a managed, device-wide installation of Python to Windows devices using Microsoft Intune.

The recommended approach is to package the official 64-bit offline Python installer as a Win32 app and install it in the **System** context. This provides a predictable installation directory, makes Python available to all users and system processes, and supports standard Intune detection and supersedence.

> **Important:** This guide is for deploying the Python runtime itself. If only one internal application requires Python, consider bundling a private Python runtime with that application instead of installing Python globally. See [Deploying a Python-based application](#deploying-a-python-based-application).

## Contents

- [Deployment design](#deployment-design)
- [Prerequisites](#prerequisites)
- [Prepare the source files](#prepare-the-source-files)
- [Create the Intune Win32 package](#create-the-intune-win32-package)
- [Create the application in Intune](#create-the-application-in-intune)
- [Configure detection](#configure-detection)
- [Assignments](#assignments)
- [Validate the deployment](#validate-the-deployment)
- [Updating Python](#updating-python)
- [Uninstall considerations](#uninstall-considerations)
- [Python package management](#python-package-management)
- [Deploying a Python-based application](#deploying-a-python-based-application)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Deployment design

| Setting | Recommended value |
| --- | --- |
| Intune application type | Windows app (Win32) |
| Installer | Official 64-bit offline CPython installer |
| Install context | System |
| Installation scope | All users |
| Installation directory | `C:\Program Files\Python314` |
| Detection | Custom PowerShell version check |
| Update method | Win32 app supersedence |

The examples in this document use Python `3.14.7`. Replace the version and installation directory where necessary if the required application or Python packages depend on another supported Python branch.

Python is transitioning from the traditional full installer to the Python Install Manager. The Install Manager is appropriate for user-managed development environments, but its normal runtime installations are per-user. The traditional full installer is currently more predictable for an Intune-managed, device-wide deployment that must also be available to processes running as `SYSTEM`.

> **Note:** The traditional Windows installer is deprecated beginning with Python 3.14. It remains available for Python 3.14 and 3.15 but is not planned for Python 3.16 or later. Reassess this deployment design before moving to Python 3.16.

## Prerequisites

Download the following:

1. The official **Windows installer (64-bit)** for the approved Python version:
   - [Python releases for Windows](https://www.python.org/downloads/windows/)
   - [Python 3.14.7 release](https://www.python.org/downloads/release/python-3147/)
2. The Microsoft Win32 Content Prep Tool:
   - [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)

Use the offline executable installer rather than the web installer so installation does not depend on downloading Python components at deployment time.

## Prepare the source files

Create a source directory containing only the Python installer:

```text
C:\IntuneSource\Python-3.14.7\
└── python-3.14.7-amd64.exe
```

Keep `IntuneWinAppUtil.exe` outside the source directory. The content prep tool packages every file and subdirectory found under the specified source directory.

## Create the Intune Win32 package

Run the following command from an elevated PowerShell or Command Prompt:

```powershell
IntuneWinAppUtil.exe `
    -c "C:\IntuneSource\Python-3.14.7" `
    -s "python-3.14.7-amd64.exe" `
    -o "C:\IntuneOutput" `
    -q
```

The resulting package will be created at approximately:

```text
C:\IntuneOutput\python-3.14.7-amd64.intunewin
```

## Create the application in Intune

1. Open the [Microsoft Intune admin center](https://intune.microsoft.com/).
2. Go to **Apps** > **Windows** > **Create**.
3. Select **Windows app (Win32)**.
4. Upload `python-3.14.7-amd64.intunewin`.

### App information

Suggested values:

| Field | Value |
| --- | --- |
| Name | Python 3.14.7 (64-bit) |
| Description | Managed 64-bit CPython runtime installed for all users |
| Publisher | Python Software Foundation |
| App version | 3.14.7 |
| Category | Developer tools |

### Program

#### Install command

```text
python-3.14.7-amd64.exe /quiet InstallAllUsers=1 TargetDir="C:\Program Files\Python314" PrependPath=1 Include_pip=1 Include_launcher=1 InstallLauncherAllUsers=1 Include_test=0 Include_doc=0 /log "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.14.7-Install.log"
```

The command performs the following actions:

- Installs Python for all users.
- Installs Python in a predictable location.
- Adds the Python and `Scripts` directories to the system `PATH`.
- Installs `pip`.
- Installs the Python launcher/Install Manager for all users.
- Excludes the Python test suite and offline documentation.
- Writes an installer log to the Intune Management Extension log directory.

If the organization wants to provide only one controlled Python runtime and does not want the Python launcher/Install Manager installed, replace these options:

```text
Include_launcher=1 InstallLauncherAllUsers=1
```

with:

```text
Include_launcher=0 AssociateFiles=0
```

#### Uninstall command

```text
python-3.14.7-amd64.exe /quiet /uninstall /log "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.14.7-Uninstall.log"
```

#### Additional program settings

| Setting | Value |
| --- | --- |
| Install behavior | System |
| Device restart behavior | App install may force a device restart |
| Installation time required | 15 minutes |
| Allow available uninstall | No, unless user-initiated removal is required |

Retain Intune's standard successful and restart-related return codes, including `0` and `3010`.

### Requirements

| Setting | Value |
| --- | --- |
| Operating system architecture | 64-bit |
| Minimum operating system | Organization's supported Windows 11 release |
| Required disk space | At least 250 MB recommended |

Python 3.14 supports Windows 10 and newer. If deploying another Python branch, confirm its supported Windows versions before deployment.

## Configure detection

Use a custom detection script so Intune verifies the actual Python runtime version rather than only checking for a directory or registry entry.

In the **Detection rules** section:

1. Set **Rules format** to **Use a custom detection script**.
2. Upload a PowerShell script containing the following code.
3. Set **Run script as 32-bit process on 64-bit clients** to **No**.

```powershell
$RequiredVersion = [version]'3.14.7'
$PythonExe = Join-Path $env:ProgramFiles 'Python314\python.exe'

if (Test-Path -LiteralPath $PythonExe) {
    $VersionOutput = & $PythonExe --version 2>&1

    if ($VersionOutput -match '^Python\s+(\d+\.\d+\.\d+)') {
        $InstalledVersion = [version]$Matches[1]

        if (
            $InstalledVersion.Major -eq $RequiredVersion.Major -and
            $InstalledVersion.Minor -eq $RequiredVersion.Minor -and
            $InstalledVersion.Build -ge $RequiredVersion.Build
        ) {
            Write-Output "Detected Python $InstalledVersion"
            exit 0
        }
    }
}

exit 1
```

This detection rule:

- Requires the approved major and minor branch.
- Accepts the required patch version or a newer patch on the same branch.
- Does not treat a different branch, such as Python 3.15, as a replacement for Python 3.14.

Intune considers a custom detection successful only when the script exits with code `0` and writes output to standard output.

## Assignments

Python can be assigned as either:

- **Required** for devices that must have Python installed.
- **Available for enrolled devices** when developers should install it from Company Portal.

For a device-wide installation, use device-based assignments where possible. If Python is required during Autopilot, add it to the Enrollment Status Page blocking application list only when provisioning cannot continue without it.

## Validate the deployment

After installation, open a new Command Prompt or PowerShell window and run:

```powershell
where.exe python
python --version
python -m pip --version
```

Expected results should reference:

```text
C:\Program Files\Python314\python.exe
```

To validate the installation while running as `SYSTEM`, use a suitable administrative test method and run:

```powershell
& 'C:\Program Files\Python314\python.exe' --version
```

> **Note:** Terminals and applications opened before installation retain their existing environment variables. Close and reopen the terminal before testing the updated system `PATH`. A sign-out or restart is normally unnecessary.

## Updating Python

### Patch update on the same branch

Example: Python `3.14.7` to `3.14.8`.

1. Download and package the new offline installer.
2. Create a new Win32 application with an updated detection script.
3. Configure the new application to supersede the previous application.
4. Set **Uninstall previous version** to **No**.
5. Test the in-place update with the organization's required Python packages and virtual environments.
6. Deploy through the normal application deployment rings.

The new installer should update the existing Python 3.14 installation in the same target directory.

### New minor branch

Example: Python `3.14` to `3.15`.

Treat a new minor branch as a separate runtime initially. Python minor versions can be installed side-by-side, and applications or virtual environments may depend on a specific branch.

Recommended process:

1. Install the new branch side-by-side.
2. Validate all organizational scripts and Python packages.
3. Recreate virtual environments using the new interpreter where necessary.
4. Update scripts and applications to reference the new runtime.
5. Remove the old branch only after dependency testing is complete.

Do not immediately configure supersedence to uninstall the previous minor branch unless every dependent workload has been validated.

## Uninstall considerations

Uninstalling Python removes the managed interpreter but may not remove:

- User-created virtual environments.
- Python files and scripts created outside the installation directory.
- Packages installed into user-specific locations.
- Applications that independently bundle their own Python runtime.

Uninstalling a Python branch can break scripts, scheduled tasks, development environments, or applications that reference its exact installation path. Validate dependencies before assigning an uninstall.

## Python package management

Avoid installing organizational packages globally into the base Python runtime. Global packages create dependency conflicts and make interpreter upgrades harder to validate.

Use a virtual environment for each project:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
```

Use `python -m pip` instead of calling `pip` directly so the command uses the intended interpreter.

If the organization must deploy a fixed set of packages, package the application and its isolated environment separately from the base Python runtime.

## Deploying a Python-based application

If users do not need a general-purpose Python development environment, avoid installing Python globally solely to support one application.

Preferred options include:

- Build a standalone executable using [PyInstaller](https://pyinstaller.org/) or [cx_Freeze](https://cx-freeze.readthedocs.io/).
- Bundle Python's [embeddable distribution](https://docs.python.org/3/using/windows.html#the-embeddable-package) in the application's installation directory.
- Vendor and test the application's Python dependencies as part of the application package.
- Do not add an application-private interpreter to the system `PATH`.

This isolates the application's dependencies and prevents an update to the shared Python runtime from unexpectedly breaking the application.

## Troubleshooting

### Running `python` opens the Microsoft Store

Check command resolution:

```powershell
where.exe python
```

Confirm the system `PATH` contains both:

```text
C:\Program Files\Python314
C:\Program Files\Python314\Scripts
```

Close and reopen the terminal after correcting the `PATH`. Windows App Execution Aliases may also need to be reviewed if the Store alias is still taking precedence.

### Detection succeeds for the wrong version

Confirm the detection script checks all three version components and verifies that the installed major and minor versions match the required branch.

### Detection fails even though Python is installed

Confirm:

- Python is installed at `C:\Program Files\Python314`.
- The detection script is configured to run as a 64-bit process.
- Running `C:\Program Files\Python314\python.exe --version` succeeds.
- The detection script writes output before exiting with code `0`.

### Installer failure

Review:

```text
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.14.7-Install.log
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log
```

Also test the exact silent installation command locally under an elevated context before uploading a new package.

## References

- [Using Python on Windows](https://docs.python.org/3/using/windows.html)
- [Python releases for Windows](https://www.python.org/downloads/windows/)
- [Status of Python versions](https://devguide.python.org/versions/)
- [Prepare a Win32 app for Microsoft Intune](https://learn.microsoft.com/en-us/intune/app-management/deployment/create-win32-package)
- [Add and assign Win32 apps in Microsoft Intune](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)
- [Configure Win32 app supersedence](https://learn.microsoft.com/en-us/intune/app-management/deployment/configure-win32-supersedence)

---

Last reviewed: August 11, 2026
