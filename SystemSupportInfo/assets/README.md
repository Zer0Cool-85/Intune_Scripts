# Branding assets

Place optional branding files in this directory and reference them from
`config/SystemSupportInfo.config.psd1`.

Recommended examples:

```powershell
Branding = @{
    LogoPath = 'assets\company-logo.png'
    # Other branding values...
}

Build = @{
    IconPath = 'assets\app.ico'
    # Other build values...
}
```

- The in-window logo can be PNG, JPG, BMP, or ICO.
- The Windows executable icon must be an ICO file.
- Use project-relative paths so `Build-Exe.ps1` can make a portable EXE.
- The logo is optional; the built-in information badge is used when omitted.

