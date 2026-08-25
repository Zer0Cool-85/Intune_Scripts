# Changelog

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
