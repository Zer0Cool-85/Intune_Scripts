# System Support Information

A configurable Windows WPF utility that presents common device information in
a support-friendly format. Users can copy one value, copy a complete ticket
summary, refresh the data, or open the configured service-desk site.

The repository can be used directly with Windows PowerShell or compiled into a
single-click Windows EXE.

## Features

- Modern, resizable WPF interface with no required image files
- Individual copy buttons and selectable read-only values
- Clean, automatically generated support-ticket summary
- Optional service-desk button that opens the default browser
- Optional in-window logo and Windows EXE icon
- Configuration-driven labels, field order, visibility, sections, and colors
- Separate data and UI modules for easier maintenance
- Windows PowerShell 5.1-compatible source
- Reproducible PS2EXE build, project validation, and release-archive scripts
- No elevation requirement and no automatic data submission

## Requirements

### Running the PowerShell version

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- A normal interactive user session

### Building the EXE

- Windows PowerShell 5.1 on Windows
- [PS2EXE 1.0.18 or later](https://www.powershellgallery.com/packages/ps2exe/)

PS2EXE generates .NET Framework/Windows PowerShell 5.1-compatible executables.
Its official documentation describes the `-noConsole`, `-STA`, `-DPIAware`,
metadata, icon, and embedded-file options used by this project:
[MScholtes/PS2EXE](https://github.com/MScholtes/PS2EXE).

## Quick start: PowerShell

1. Download or clone the repository.
2. Optionally edit `config/SystemSupportInfo.config.psd1`.
3. Double-click `Launch-SystemSupportInfo.cmd`.

You can also launch it from PowerShell:

```powershell
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass `
    -File .\SystemSupportInfo.ps1
```

The command-line execution-policy value applies only to that new PowerShell
process; it does not rewrite the machine or user policy. See Microsoft's
[`about_PowerShell_exe`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1)
documentation for the `-File`, `-STA`, and `-ExecutionPolicy` behavior.

## Quick start: build the EXE

From the repository root on a Windows machine:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `
    .\build\Build-Exe.ps1 -InstallPS2EXE
```

The finished file is written to:

```text
dist\SystemSupportInfo.exe
```

Only the EXE needs to be distributed. At launch, its embedded modules,
configuration, and optional logo are expanded beneath the current user's temp
directory and loaded automatically.

## Basic customization

To display the service-desk button, update the configuration:

```powershell
ServiceDesk = @{
    Enabled    = $true
    Url        = 'https://support.contoso.com'
    ButtonText = 'Open IT Service Desk'
}
```

To add branding:

```powershell
Branding = @{
    LogoPath         = 'assets\company-logo.png'
    AccentColor      = '#5BA63C'
    AccentHoverColor = '#70BF50'
    # Keep the remaining Branding values from the supplied configuration.
}

Build = @{
    IconPath = 'assets\app.ico'
    # Keep the remaining Build values from the supplied configuration.
}
```

To hide or reorder a field, edit the `Fields` array. The UI and copied summary
are generated in that order:

```powershell
@{
    Key              = 'IPv4Address'
    Label            = 'IPv4 address'
    Section          = 'Storage & network'
    Visible          = $true
    IncludeInSummary = $true
}
```

See [Customization](docs/CUSTOMIZATION.md) for all supported options.

## Runtime overrides

The main launcher accepts temporary overrides without changing the PSD1 file:

```powershell
.\SystemSupportInfo.ps1 `
    -WindowTitle 'Contoso IT Support' `
    -LogoPath 'assets\company-logo.png' `
    -ServiceDeskUrl 'https://support.contoso.com' `
    -ServiceDeskButtonText 'Open IT Service Desk'
```

Use configuration-file values for anything that must be embedded in the EXE.

## Repository structure

| Path | Purpose |
| --- | --- |
| `Launch-SystemSupportInfo.cmd` | One-click PowerShell launcher with a hidden console |
| `SystemSupportInfo.ps1` | Main launcher for script and compiled modes |
| `config/SystemSupportInfo.config.psd1` | Branding, text, layout, fields, URL, and build metadata |
| `src/SystemSupportInfo.Core.psm1` | Windows system-information collection |
| `src/SystemSupportInfo.UI.psm1` | Configurable WPF interface and clipboard workflow |
| `assets/` | Optional PNG/JPG/BMP/ICO branding files |
| `examples/` | Double-click and runtime-override examples |
| `build/Test-Project.ps1` | PowerShell/configuration validation |
| `build/Build-Exe.ps1` | Single-file EXE build |
| `build/New-ReleaseArchive.ps1` | Clean source/release ZIP build |
| `dist/` | Generated artifacts; ignored by Git |

## Validation

Run the included project checks before committing:

```powershell
.\build\Test-Project.ps1
```

To also collect and verify the data shape on the current device:

```powershell
.\build\Test-Project.ps1 -IncludeDataCollection
```

`Build-Exe.ps1` runs the standard validation automatically unless `-SkipTests`
is explicitly used.

## Build and deployment guidance

- [Standalone PowerShell usage](docs/STANDALONE-USAGE.md)
- [Customization reference](docs/CUSTOMIZATION.md)
- [Building and signing the EXE](docs/BUILDING-THE-EXE.md)

## Security notes

- The utility reads local system information and copies only when the user
  clicks a copy button.
- Do not place passwords, API keys, or tokens in the source or configuration.
- A PS2EXE file is packaging, not source-code encryption. The PS2EXE project
  explicitly documents that its embedded PowerShell can be extracted.
- Sign production PowerShell and EXE artifacts with your organization's trusted
  code-signing certificate when possible.

## License

No license has been selected automatically. Add the license approved by your
organization before publishing this project publicly.
