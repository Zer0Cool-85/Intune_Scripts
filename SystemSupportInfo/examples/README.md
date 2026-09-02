# Examples

## `Launch-Standalone.cmd`

Double-click this file to launch the PowerShell version with Windows PowerShell
5.1, STA mode, a hidden console host, no profile, and a process-only
execution-policy override.

## `Launch-Branded.ps1`

Shows how to override the window title and service-desk settings at launch
without changing the main configuration file. Replace the example URL before
production use.

Runtime overrides are useful for testing. Use
`config/SystemSupportInfo.config.psd1` for settings that should be embedded into
the EXE.
