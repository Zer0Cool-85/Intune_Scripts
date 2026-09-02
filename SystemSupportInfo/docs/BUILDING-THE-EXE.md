# Building the Windows EXE

The included build creates a GUI executable with no PowerShell console window.
It embeds the launcher configuration, all source modules, and the optional
in-window logo. Only the resulting EXE needs to be distributed.

## Why PS2EXE

The project uses [MScholtes/PS2EXE](https://github.com/MScholtes/PS2EXE), which
supports:

- Windows GUI mode with `-noConsole`
- STA mode required by WPF
- DPI-aware GUI output
- x64 or x86 targets
- Windows Explorer metadata and ICO resources
- embedded files extracted automatically at startup

Version 1.0.18 or later is required by the build script. The latest package is
available from the
[PowerShell Gallery](https://www.powershellgallery.com/packages/ps2exe/).

## One-command build

Open Windows PowerShell 5.1 in the repository root. Administrative rights are
not required when installing the dependency for `CurrentUser`:

```powershell
.\build\Build-Exe.ps1 -InstallPS2EXE
```

The script will:

1. Parse-check all PS1, PSM1, and PSD1 files.
2. Validate the selected configuration and field keys.
3. Install or load PS2EXE 1.0.18+.
4. Embed the modules, configuration, and optional logo.
5. Compile a no-console, STA, DPI-aware x64 application.
6. Apply the configured product metadata.

Default output:

```text
dist\SystemSupportInfo.exe
```

## Custom output and configuration

```powershell
.\build\Build-Exe.ps1 `
    -ConfigurationPath '.\config\SystemSupportInfo.config.psd1' `
    -OutputPath '.\dist\ContosoSupportInfo.exe'
```

The selected configuration is embedded as the EXE's default configuration.

## Add an executable icon

Add an ICO file under `assets` and either configure:

```powershell
Build = @{
    IconPath = 'assets\app.ico'
    # Other build values...
}
```

or override it at build time:

```powershell
.\build\Build-Exe.ps1 -IconPath '.\assets\app.ico'
```

The in-window logo and executable icon are separate settings. The window logo
can be PNG/JPG/BMP/ICO; the EXE resource must be ICO.

## Architecture

The default target is x64:

```powershell
.\build\Build-Exe.ps1 -Architecture x64
```

Other supported values:

```powershell
-Architecture x86
-Architecture AnyCPU
```

For a modern Windows 10/11 device fleet, x64 is the recommended default.

## Embedded runtime files

PS2EXE expands the embedded files beneath:

```text
%TEMP%\SystemSupportInfo\1.0.2\
```

The EXE then imports the same modular files used by source mode. These small
runtime files can remain in the user's temp directory and are overwritten on a
later launch/build version as necessary.

This behavior follows PS2EXE's documented `-embedFiles` model. A failure to
write into the current user's temp directory prevents the EXE from starting.

## Passing runtime overrides to a compiled EXE

Normally, build the desired values into the configuration. For testing, PS2EXE
reserves its own command-line arguments and uses `-end` before script arguments:

```powershell
.\SystemSupportInfo.exe -end `
    -WindowTitle "Temporary support title" `
    -ServiceDeskUrl "https://support.contoso.com"
```

PS2EXE documents that compiled executable arguments arrive as strings. All
launcher override parameters in this project are intentionally string-based.

## Code signing

PS2EXE does not sign the output. In a production environment, sign the EXE with
an organization-trusted code-signing certificate after every build:

```powershell
$certificate = Get-Item 'Cert:\CurrentUser\My\YOUR_CERTIFICATE_THUMBPRINT'

Set-AuthenticodeSignature `
    -FilePath '.\dist\SystemSupportInfo.exe' `
    -Certificate $certificate `
    -TimestampServer 'https://YOUR-APPROVED-TIMESTAMP-SERVICE'
```

Use only your organization's approved timestamp service and certificate
workflow. Verify the finished signature:

```powershell
Get-AuthenticodeSignature '.\dist\SystemSupportInfo.exe' | Format-List
```

Signing improves publisher identity and deployment trust. It does not encrypt
the source. See Microsoft's
[`Set-AuthenticodeSignature`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-authenticodesignature)
and
[`Get-AuthenticodeSignature`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature)
documentation for the supported parameters and signature status values.

## Source-code and secret warning

PS2EXE explicitly documents that the PowerShell source stored in an executable
can be extracted using its reserved `-extract` argument. Never embed passwords,
API keys, tokens, or other secrets in the script or configuration.

## Troubleshooting

### PS2EXE is missing or too old

```powershell
Install-Module ps2exe -MinimumVersion 1.0.18 -Scope CurrentUser -Force
```

Then rebuild, or let the build script install it with `-InstallPS2EXE`.

### `Import-PowerShellDataFile` is not recognized

Use release 1.0.1 or later and rebuild the EXE. The updated launcher embeds a
configuration module that explicitly loads `Microsoft.PowerShell.Utility` and
uses a safe parser fallback when a hosted runspace still does not expose the
cmdlet. Microsoft documents the command and its safe PSD1 behavior in
[`Import-PowerShellDataFile`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-powershelldatafile?view=powershell-5.1).

Confirm that the build host is Windows PowerShell 5.1:

```powershell
$PSVersionTable.PSVersion
Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue
```

Replace the entire older project folder before building; copying only the main
launcher will omit the new module from the EXE.

### Configured logo not found

Use a project-relative path such as:

```powershell
LogoPath = 'assets\company-logo.png'
```

Absolute logo paths are rejected for portable EXE builds because they would not
exist on another computer.

### The build works but the EXE is blocked

Verify the file hash and Authenticode signature, review Defender or other EDR
events, and use your organization's normal allowlisting/reputation process.
Unsigned newly generated executables start without publisher reputation.
Microsoft explains how file hashes and publisher identity affect warnings in
[SmartScreen reputation for Windows app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).

### The application shows no window

Run the modular source and project checks first:

```powershell
.\build\Test-Project.ps1 -IncludeDataCollection
.\SystemSupportInfo.ps1
```

If source mode succeeds, rebuild the EXE without `-SkipTests` and inspect the
current user's `%TEMP%\SystemSupportInfo` directory for extracted files.
