# Custom post-enrollment content

`PostEnroll.Custom.ps1` is the supported extension point for organization-specific first-login
work. The installer copies this entire directory into the durable runtime beneath `ProgramData`.

Guidelines:

- Assume the script runs as `NT AUTHORITY\SYSTEM`, not as the signed-in user.
- Use the supplied `InteractiveUser` and `InteractiveUserSid` parameters when a step needs to know
  who signed in.
- Keep each action idempotent and use terminating errors for failures that should trigger another
  attempt at the next logon.
- Put installers and supporting files in `Payloads`.
- Treat the staged `Runtime` tree as read-only. Write generated files to the product's `State` or
  `Logs` directory so runtime-integrity detection remains valid. Payload files are checked for
  presence and length; scripts and configuration are SHA-256 checked.
- Do not store passwords, API tokens, certificates with private keys, or other secrets here.
- A SYSTEM task cannot directly display ordinary desktop UI. If your existing workflow uses a
  separately licensed UI bridge, add and call it here; it is intentionally not bundled.

The default custom hook is a safe no-op, so the repository runs without any private payloads.
