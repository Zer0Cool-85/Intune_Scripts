# Changelog

## 1.1.0

- Added `LegacySsidAction`: retain listed profiles with automatic connection disabled, or remove them.
- Default to `DisableAutoConnect` with explicit switching off; always reapply automatic connection on the preferred profile.
- Removed changes to autoSwitch on unrelated profiles. Only fully listed profiles can be modified.
- Prevented explicit switches from unlisted, mixed, per-user, or unidentifiable active profiles, including a fresh check immediately before connecting.
- Added scope and disable-mode regression coverage and upgrade guidance for the previous schema.

## 1.0.0

- Configurable SYSTEM scheduled task for recurring office Wi-Fi preference and legacy cleanup.
- Exact SSID matching through the native Windows WLAN API, independent of localized command output.
- Successful-connection gate, active-connection protection, explicit-switch cooldown, and audit mode.
- Installer, uninstall, generated Intune detection, packaging helper, documentation, and offline tests.
