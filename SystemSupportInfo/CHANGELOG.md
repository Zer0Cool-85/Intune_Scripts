# Changelog

All notable changes to this project will be documented here.

## 1.0.2 - 2026-09-02

- Fixed blank fields caused by WPF closures losing access to module-scoped
  collection and clipboard commands.
- Added Windows PowerShell 5.1 and PowerShell 7 source-mode compatibility.
- Added automatic STA relaunch and an optional PowerShell 7 one-click launcher.
- Ensured every displayed field has a non-empty fallback value.
- Added refresh-error details and a local diagnostic log under the user's temp
  directory.
- Expanded data-collection validation to reject and display empty values.

## 1.0.1 - 2026-09-02

- Added a safe PSD1 compatibility loader for hosts where
  `Import-PowerShellDataFile` is not exposed.
- Explicitly attempts to load `Microsoft.PowerShell.Utility` before using the
  parser fallback.
- Added parser-fallback validation and embedded the new configuration module in
  compiled EXEs.
- Improved troubleshooting guidance for PowerShell host/version issues.

## 1.0.0 - 2026-09-01

- Added configuration-driven WPF field cards and ticket summaries.
- Split Windows data collection and interface behavior into separate modules.
- Added optional logo, custom theme colors, and user-facing text settings.
- Added optional configurable service-desk button.
- Added standalone CMD and PowerShell launch examples.
- Added project validation and PS2EXE 1.0.18+ build automation.
- Added clean release-archive generation and repository documentation.
