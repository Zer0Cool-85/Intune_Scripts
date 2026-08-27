# Custom post-enrollment content

The `<PostEnroll><Steps>` manifest in `Config.xml` is the supported extension point for
organization-specific first-login work. The installer copies this entire directory into the
durable runtime beneath `ProgramData`.

Guidelines:

- `Scope="Device"` PowerShell steps run as `NT AUTHORITY\SYSTEM`.
- `Scope="User"` PowerShell steps run as the eligible signed-in user through PSADT 4.1.8. They do
  not receive elevation and should only change that user's profile or application data.
- Step scripts receive `ConfigurationPath`, `LogDirectory`, `StateDirectory`, `InteractiveUser`,
  and `InteractiveUserSid` parameters.
- Keep each action idempotent and use terminating errors for failures that should trigger another
  attempt at the next logon.
- Put installers and supporting files in `Payloads`. Large payload bytes are presence/length
  checked rather than SHA-256 checked during recurring Intune detection.
- Treat the staged `Runtime` tree as read-only. Write generated files to the product's `State` or
  `Logs` directory so runtime-integrity detection remains valid. Payload files are checked for
  presence and length; scripts and configuration are SHA-256 checked.
- Do not store passwords, API tokens, certificates with private keys, or other secrets here.
- Increment the individual step `Version` whenever its code, arguments, detection, or payload
  changes. Completed versions are skipped during retry.
- Keep ordinary applications as separately detected Intune Win32 apps when exact first-login
  sequencing is unnecessary. The included AWS example supports an embedded package only for the
  cases where the onboarding controller must own the timing.

`Steps\Install-AwsVpn.ps1` expects an existing PSADT package at
`Payloads\AWSVPN_PSADT\Invoke-AppDeployToolkit.exe`. Its manifest step is disabled by default, so
the repository runs without private installers.
