# Intune policy examples

These files are references for settings that are more maintainable as Intune configuration than
as build-dependent default-profile modifications.

## Start pins

Use `StartPins.json` with the Windows Start **Configure Start Pins** policy. Exporting a layout from
a reference device running the same Windows release is preferable to manually maintaining a large
JSON payload.

## Taskbar

The XML under `Assets/TaskbarLayoutModification.xml` contains an Explorer and Edge example. Deploy
it using the Windows Start/Taskbar policy when you want centrally managed pins. Leave the local
`TaskbarLayout` option disabled in Config.xml when policy owns the setting.

## Settings that should usually be Intune-owned

- Windows LAPS automatic account management
- Windows Spotlight and consumer experiences
- Widgets
- Lock screen and wallpaper when licensing and timing meet your requirements
- Windows edition/subscription activation
- Browser enterprise policies

Do not configure the same setting in Config.xml and Intune. Pick one owner to avoid policy conflicts
and confusing remediation behavior.

