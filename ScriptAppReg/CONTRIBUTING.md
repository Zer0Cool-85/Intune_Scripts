# Contributing

Contributions are welcome through issues and pull requests.

Before submitting a change:

1. Update documentation when behavior or configuration changes.
2. Run the repository validation:

   ```powershell
   .\tests\Test-Repository.ps1
   ```

3. Do not commit generated `build` content, `.intunewin` packages, or `IntuneWinAppUtil.exe`.
4. Avoid writing secrets, tenant identifiers, or organization-specific production paths into the example configuration.

The generated scripts must remain compatible with Windows PowerShell 5.1 unless a documented breaking change is intentionally introduced.
