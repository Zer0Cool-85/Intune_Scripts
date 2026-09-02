# Standalone PowerShell usage

The modular source version runs directly from the repository folder. Keep the
launcher, `src`, and `config` folders together.

## Supported launch methods

### Double-click launcher

Double-click:

```text
Launch-SystemSupportInfo.cmd
```

The CMD wrapper starts Windows PowerShell 5.1 in STA mode with its console host
hidden, then exits immediately while the WPF window continues running.

### PowerShell console

From the repository root:

```powershell
.\SystemSupportInfo.ps1
```

If the current host is not using a single-threaded apartment, use:

```powershell
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass `
    -File .\SystemSupportInfo.ps1
```

WPF requires STA. Windows PowerShell 5.1 defaults to STA, but including the
switch makes shortcuts and wrappers explicit.

## Use a different configuration

```powershell
.\SystemSupportInfo.ps1 `
    -ConfigPath '.\config\SystemSupportInfo.config.psd1'
```

Absolute paths are accepted. Relative paths are resolved from the application
root, not from an arbitrary current working directory.

## Temporary runtime overrides

```powershell
.\SystemSupportInfo.ps1 `
    -WindowTitle 'Contoso Support Information' `
    -LogoPath 'assets\company-logo.png' `
    -ServiceDeskUrl 'https://support.contoso.com' `
    -ServiceDeskButtonText 'Open Service Desk'
```

Overrides affect only that launch. They do not modify the PSD1 file.

## Create a desktop shortcut

Use the following target and change the repository path:

```text
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "C:\Program Files\SystemSupportInfo\SystemSupportInfo.ps1"
```

Set **Start in** to the repository root. The application does not require
administrative rights.

## Execution policy

The example uses `-ExecutionPolicy Bypass` only for the newly created
PowerShell process. It does not change registry-based execution-policy settings.
In managed environments, prefer code signing and the organization's approved
policy rather than relying permanently on Bypass.

Microsoft reference:
[`about_PowerShell_exe`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1).

## Files that must remain together

```text
SystemSupportInfo.ps1
config\SystemSupportInfo.config.psd1
src\SystemSupportInfo.Core.psm1
src\SystemSupportInfo.UI.psm1
assets\...                 (only when configured)
```

For true single-file distribution, build the EXE.
