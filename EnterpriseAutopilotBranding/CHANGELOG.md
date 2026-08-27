# Changelog

## 4.1.0 — 2026-08-27

- Replaced the ServiceUI-dependent first-login model with the native SYSTEM-to-user UI architecture
  in PSAppDeployToolkit 4.1.8.
- Added a Fluent step counter, full pending/running/completed/warning list, percentage progress,
  completion dialog, conditional restart choice, and retry dialog.
- Added XML-manifest onboarding handlers for debloat, PowerShell, file detection, and installed-app
  detection.
- Added independent step IDs and versions plus immediate Device and per-user SID state, allowing
  interrupted runs to resume at the first incomplete critical step.
- Added eligible-user exclusions and safe defaults for `defaultuser0`, Administrator, `WINADMIN`,
  and `WDAGUtilityAccount` in self-deploying Autopilot workflows.
- Added a named mutex, per-step timeouts, honest exit handling, and a default policy that retains
  the task after repeated failure.
- Added an optional, disabled AWS VPN wrapper for organizations that require exact first-login
  sequencing while preserving the recommendation to manage ordinary apps independently in Intune.
- Removed local user-derived computer renaming from onboarding; naming should be deterministic in
  the device phase or occur after server-side primary-user reconciliation.
- Added PSADT attribution, pinned-version validation, documentation, and tests.

## 4.0.0 — 2026-08-25

- Replaced the monolithic upstream-derived execution chain with a modular, idempotent installer.
- Added per-step criticality, accurate exit codes, and success state written only after completion.
- Added human-readable and JSON Lines logging.
- Added versioned installation state and a custom Intune detection script.
- Added a config-driven Appx and classic-application debloat engine.
- Added Dell-specific removal rules with explicit protection for Dell Command Update and enterprise,
  security, shared Core Services/TechHub, display, power, peripheral, dock, and instrumentation
  utilities.
- Added Audit and Enforce debloat modes.
- Added a delayed, retry-aware SYSTEM task for the first interactive sign-in.
- Added an organization-owned post-enrollment extension point and payload directory.
- Removed install-time internet, PSGallery, WinGet repair, Edge download, IP geolocation, shared local
  administrator password, Office removal, GVLK, and UE-V dependencies.
- Added build automation, source packaging, validation, Pester tests, and GitHub Actions validation.
