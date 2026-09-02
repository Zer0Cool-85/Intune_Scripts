# Customization reference

Most customization is performed in:

```text
config\SystemSupportInfo.config.psd1
```

The file is a PowerShell data file and is loaded with
`Import-PowerShellDataFile`. Keep it limited to literal data values.

## Application settings

| Setting | Purpose | Default |
| --- | --- | --- |
| `WindowTitle` | Window and header title | `Device Support Information` |
| `Subtitle` | Short header explanation | `Copy the details...` |
| `Width` / `Height` | Initial window dimensions | `760` / `720` |
| `MinWidth` / `MinHeight` | Minimum resizable dimensions | `680` / `600` |
| `Columns` | Number of field cards per row; valid values 1–3 | `2` |
| `Resizable` | Enables resize and header double-click maximize | `$true` |
| `ShowPrivacyNotice` | Shows the no-automatic-submission banner | `$true` |

## Service-desk button

```powershell
ServiceDesk = @{
    Enabled    = $true
    Url        = 'https://support.contoso.com/portal'
    ButtonText = 'Open IT Service Desk'
}
```

- Leave `Url` empty to hide the button.
- Only absolute HTTP and HTTPS URLs are accepted.
- The URL opens in the current user's default browser.

## Branding

`Branding` controls the optional logo and all major interface colors. Colors
can use WPF hex notation such as `#5BA63C` or a recognized WPF color name.

| Setting | Purpose |
| --- | --- |
| `LogoPath` | PNG, JPG, BMP, or ICO displayed in the header |
| `FallbackMark` | Text displayed when no valid logo is available |
| `AccentColor` | Main button and fallback-badge color |
| `AccentHoverColor` | Main button hover color |
| `WindowColor` | Main application background |
| `HeaderColor` | Header and footer background |
| `CardColor` | Field-card background |
| `CardBorderColor` | Card and window border color |
| `PrimaryTextColor` | Primary field and title text |
| `SecondaryTextColor` | Labels, subtitles, and inactive icons |
| `SecondaryButtonColor` | Refresh/service-desk button background |
| `SecondaryButtonHoverColor` | Secondary button hover background |
| `InfoPanelColor` | Privacy-notice background |
| `InfoPanelBorderColor` | Privacy-notice border |
| `InfoPanelTextColor` | Privacy-notice text and icon |
| `SuccessTextColor` | Copy/refresh success status |
| `ErrorTextColor` | Clipboard, URL, and refresh error status |

Use a project-relative logo path for portable builds:

```powershell
LogoPath = 'assets\company-logo.png'
```

## User-facing text

The `Text` section contains button labels, status messages, the privacy notice,
the unavailable-value placeholder, and the date format. These can be adjusted
for terminology or localization without changing source code.

`DateFormat` uses standard .NET date/time format strings. The default is:

```powershell
DateFormat = 'MMM d, yyyy h:mm tt'
```

## Ticket summary

```powershell
Summary = @{
    Heading            = 'DEVICE SUPPORT INFORMATION'
    IncludeCollectedAt = $true
    CollectedLabel     = 'Collected'
}
```

The copied summary follows the configured field and section order.

## Fields

Each entry in the `Fields` array creates a card:

```powershell
@{
    Key              = 'SerialNumber'
    Label            = 'Serial / service tag'
    SummaryLabel     = 'Serial number'
    Section          = 'Device'
    Visible          = $true
    IncludeInSummary = $true
}
```

| Property | Required | Behavior |
| --- | --- | --- |
| `Key` | Yes | Property returned by `Get-SystemSupportData` |
| `Label` | Yes | UI card label and default summary label |
| `SummaryLabel` | No | Different label used only in copied text |
| `Section` | Yes | Groups cards and summary lines |
| `Visible` | No | `$false` removes the card; default is visible |
| `IncludeInSummary` | No | `$false` omits it from Copy ticket summary |

Move entries to change their order. Keep entries for the same section together.

### Supported field keys

| Key | Value |
| --- | --- |
| `DeviceName` | Windows computer name |
| `SignedInUser` | Interactive user detected by Windows |
| `Hardware` | Manufacturer and model |
| `SerialNumber` | BIOS serial/service tag |
| `InstalledMemory` | Total physical memory |
| `JoinStatus` | Entra, hybrid, AD domain, registered, or workgroup state |
| `WindowsEdition` | Windows caption/edition |
| `WindowsVersion` | Feature version such as 24H2 |
| `OSBuild` | Build and UBR |
| `Architecture` | OS architecture |
| `LastRestart` | Last boot time |
| `Uptime` | Friendly uptime duration |
| `SystemDrive` | Free and total C: capacity |
| `ActiveConnection` | Active network interface names |
| `IPv4Address` | Active non-loopback IPv4 addresses |
| `CollectedAt` | Last refresh timestamp |

## Adding a new collected value

1. Add the new property to the ordered `$data` object in
   `src/SystemSupportInfo.Core.psm1`.
2. Populate it in an independent `try`/`catch` block so one failure does not
   prevent the rest of the window from loading.
3. Add its key to `$supportedFieldKeys` in `build/Test-Project.ps1`.
4. Add a matching entry to the configuration's `Fields` array.
5. Run `build/Test-Project.ps1 -IncludeDataCollection`.

The UI module does not need to be edited for a normal new field.

## EXE metadata

The `Build` section controls the output filename and Windows Explorer details:

```powershell
Build = @{
    OutputFileName = 'ContosoSupportInfo.exe'
    ProductName    = 'Contoso Support Information'
    Description    = 'Displays support-ready Windows device information.'
    Company        = 'Contoso'
    Copyright      = 'Copyright (c) 2026 Contoso'
    Version        = '1.0.0.0'
    IconPath       = 'assets\app.ico'
}
```

`Version` must use four numeric components. `IconPath` must point to an ICO file.

