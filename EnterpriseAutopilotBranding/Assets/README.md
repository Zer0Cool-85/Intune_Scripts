# Branding assets

Replace these sample files before production deployment:

- `CompanyWallpaper.jpg`: recommended 1920×1080 or larger, 16:9.
- `CompanyLockScreen.jpg`: recommended 1920×1080 or larger, with important content away from the
  lower-left status area.
- `CompanyLogo.bmp`: Windows OEM information logo. A square image around 120×120 works well.
- `Company.theme`: update its display name and any changed wallpaper destination.

`TaskbarLayoutModification.xml` is supplied as an optional example and is disabled in Config.xml.
For current Windows 11 releases, prefer the supported Intune policy examples in `PolicyExamples`.

`Start2.bin` and `settings.dat` are intentionally absent. The optional legacy layout feature fails
preflight when enabled without them and rejects OS builds outside its configured test range.
