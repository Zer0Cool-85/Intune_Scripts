# Testing and troubleshooting

## What has and has not been tested

The authoring environment is Linux. Validation here covers PowerShell source syntax with a tree-sitter parser, JSON/schema consistency, package paths/dependencies, XAML XML/resource/name references, documentation links, and the HTML design reference. These are useful static checks, not a substitute for the Windows WPF runtime.

**Not executed here:** Windows PowerShell 5.1, WPF XAML loading/rendering, the C# model under .NET Framework, ServiceUI session injection, SYSTEM execution, installer process termination, and actual application installs. No production-readiness or successful deployment claim is implied.

## Windows smoke tests

From the extracted folder:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Tests\Invoke-SmokeTests.ps1
```

The script parses the PowerShell files with Microsoft's actual PowerShell parser, loads all supplied configurations, exercises outcome/dependency logic, compiles the C# view model, loads/measures the WPF layout with ten step models, and runs temporary worker fixtures for success, failure, explicit 3010, helper-based 3010, and progress updates. It does not display the main window, install an app, touch HKLM, or call ServiceUI. Its temporary files are removed afterward.

## Visual pilot

1. Run `Run-Demo.cmd` as a regular user.
2. Confirm the window fits the display and remains responsive throughout the demo.
3. Confirm step 3 shows a failure and step 4 is skipped due to the dependency.
4. Expand the error; verify the message is legible and selectable.
5. Choose Retry unfinished. Only failed/skipped steps should run; all steps should then finish.
6. Confirm Done closes the window. During active work, Close/Alt+F4 should leave the workflow running; minimize should work.
7. Run the Dark-Demo and All10-Demo configurations shown in README.md.
8. Test at your normal laptop resolution, 100/125/150/200% scaling, and your normal docked monitor setup. The step list should scroll, and the footer must remain reachable.
9. Add your actual logo/banner and inspect cropping, long welcome text, and long step labels.

## SYSTEM/ServiceUI pilot

1. Work on a disposable/test device with your normal application-control policies.
2. Put a harmless real action in one step, such as verifying an existing file. Disable the other steps. Keep RequireSystemForLive true.
3. Stage the full package in a protected local folder and use your existing SYSTEM + ServiceUI first-desktop trigger.
4. Confirm the expected logged-on session sees the UI and the step transcript reports the expected identity.
5. Verify success, a deliberate throw, a declared dependency failure, and an optional failure.
6. Run the package again. Matching successful steps should be skipped; if all work is complete, no window should appear.
7. Change the test step's contents and rerun. Its fingerprint should change and the step should run again.
8. Test a short time limit with a harmless sleeping step. The worker should be terminated, remaining steps skipped, and in-window retry hidden.
9. Test reboot-required behavior using a harmless `exit 3010` step. Confirm no reboot is initiated and the caller receives 3010 after Done.
10. Test an interrupted run/logoff and a second simultaneous launch. Confirm retry/resume behavior and the 1618 duplicate-instance result.

Only then add the real application/configuration work and validate each action's detection and idempotence. Custom actions can impose limitations that the UI cannot infer.

## Troubleshooting

| Symptom | Check |
|---|---|
| No window when launched by Intune | Confirm the call occurs after desktop readiness; confirm ServiceUI/session target and use your existing known-good launcher. A direct SYSTEM launch without ServiceUI is not interactive. |
| Live run says SYSTEM is required | ServiceUI does not elevate an ordinary user. Invoke from your existing SYSTEM task/deployment. |
| Powershell host/STA error | Use 64-bit Windows PowerShell 5.1 with -STA. Use Sysnative from a 32-bit caller. |
| Window closes immediately / hidden startup failure | Run Validate-Config.cmd, then launch the PS1 from a visible PowerShell console. Check JSON paths, image existence, runtime version, and application-control policy. |
| A supplied step fails instantly | Placeholder scripts deliberately throw until you replace their code. |
| Script works interactively but fails here | Check SYSTEM's profile, working directory, network identity, permissions, mapped drives, and bitness. Use local files and explicit paths. |
| State did not rerun a completed step | Match SetupId/SetupVersion; inspect the completion record. For intentional full retest use -ResetState; for a new revision bump SetupVersion. |
| Changed installer file did not rerun a step | External payload/helper contents are not fingerprinted. Bump SetupVersion or change the step/parameters; keep real detection in your script. |
| UI reports success after an EXE failed | Check that every native result is tested; prefer Invoke-SetupProcess. Outputting false/error text is not a failure signal. |
| Step remains running after its installer seems done | Ensure your script returns and all waited-for child processes exit. Inspect the transcript and installer process tree. |
| Timeout still leaves installer activity | Some installs continue inside a Windows service. Inspect/recover that operation before restarting the workflow. |
| Progress jumps or shows 100% with a failure | Overall progress counts finished steps, including failed/skipped work. Status color and text indicate the outcome. |
| Retry button is missing | AllowRetry must be true; a timeout/controller error intentionally disables retry. |
| Dark content, light title bar | The content theme is custom WPF; the native title bar is left to Windows. |
| Completion state is unreadable | Inspect/archive the state file explicitly. The framework stops rather than silently repeating production actions. |

## Sources used for platform behavior

- [Microsoft: WPF threading model](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model)
- [Microsoft: WPF animation overview](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/graphics-multimedia/animation-overview)
- [Microsoft: Start-Process, Windows PowerShell 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-5.1)
- [Microsoft: Start-Transcript, Windows PowerShell 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.host/start-transcript?view=powershell-5.1)
- [Microsoft: automatic variables and LASTEXITCODE](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables?view=powershell-5.1)

The window, configuration format, step runner, and documentation in this package are a custom implementation, not a Microsoft or PSADT product.
