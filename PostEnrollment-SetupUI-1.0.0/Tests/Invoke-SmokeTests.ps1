#Requires -Version 5.1
<# Run on Windows with: powershell.exe -NoProfile -STA -File .\Tests\Invoke-SmokeTests.ps1
   Tests only use temporary files and a WPF window loaded in memory, not displayed.
   They do not install apps, edit HKLM, or invoke ServiceUI. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Core/Setup.Common.ps1')
$script:checks = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++
    Write-Host "PASS: $Message"
}

foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1') {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    Assert-True (@($errors).Count -eq 0) ("PowerShell parse: " + $file.Name)
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'Config') -Filter '*.json') {
    $cfg = Read-SetupConfiguration $file.FullName $root
    Assert-True ($cfg.SchemaVersion -eq 1) ("Configuration: " + $file.Name)
}
$stepA = [pscustomobject]@{ Definition = [pscustomobject]@{ Id='a'; Required=$true; DependsOn=@() }; Status='Complete' }
$stepB = [pscustomobject]@{ Definition = [pscustomobject]@{ Id='b'; Required=$true; DependsOn=@('a') }; Status='Failed' }
Assert-True ((Get-SetupOutcome @($stepA,$stepB)) -eq 'Failed') 'Required failure gives Failed'
$stepB.Definition.Required = $false
Assert-True ((Get-SetupOutcome @($stepA,$stepB)) -eq 'Warning') 'Optional failure gives Warning'
$stepB.Status = 'Complete'
Assert-True ((Get-SetupOutcome @($stepA,$stepB)) -eq 'Success') 'Successful steps give Success'
Assert-True ($null -eq (Get-SetupDependencyBlock $stepB @($stepA,$stepB))) 'Successful dependency allows a step'
$stepA.Status = 'Failed'
Assert-True ($null -ne (Get-SetupDependencyBlock $stepB @($stepA,$stepB))) 'Failed dependency blocks a step'
$rejected = $false
try { $null = Resolve-SetupContentPath $root '../outside.ps1' } catch { $rejected = $true }
Assert-True $rejected 'Package-relative paths cannot traverse out of the package'

if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Re-run this test with powershell.exe -STA.' }
    Add-Type -AssemblyName @('PresentationFramework','PresentationCore','WindowsBase')
    if (-not ('DeviceSetupUI.StepViewModel' -as [type])) { Add-Type -Path (Join-Path $root 'UI/StepViewModel.cs') }
    [xml]$xml = Get-Content -LiteralPath (Join-Path $root 'UI/MainWindow.xaml') -Raw
    $reader = New-Object Xml.XmlNodeReader($xml)
    try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
    Assert-True ($null -ne $window.FindName('StepList')) 'WPF XAML loads and StepList resolves'
    $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[DeviceSetupUI.StepViewModel]'
    1..10 | ForEach-Object {
        $vm = New-Object DeviceSetupUI.StepViewModel
        $vm.Number = [string]$_; $vm.Title = "Test step $_"; $vm.Description = 'Layout check'; $vm.Animated = $true
        $items.Add($vm)
    }
    $window.FindName('StepList').ItemsSource = $items
    $items[0].Status = 'Running'; $items[0].Percent = 50
    $items[1].Status = 'Failed'; $items[1].Error = 'Test error'
    $items[2].Status = 'Complete'; $items[3].Status = 'Skipped'
    $window.Measure((New-Object Windows.Size(900,820)))
    $window.Arrange((New-Object Windows.Rect(0,0,900,820)))
    $window.UpdateLayout()
    Assert-True ($items[1].HasError -and $items[0].HasPercent) 'Step model exposes error/progress state'
    $window.Close()

    $temp = Join-Path ([IO.Path]::GetTempPath()) ('SetupUISmoke-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($temp) | Out-Null
    try {
        foreach ($test in @(
            @{Name='success'; Code=0; Body='Write-SetupProgress -Message "Test progress" -Percent 50; Write-Output "Done"'},
            @{Name='failure'; Code=1; Body='throw "Intentional smoke-test failure"'},
            @{Name='nativeexit'; Code=3010; Body='exit 3010'},
            @{Name='helperreboot'; Code=3010; Body='$null = Invoke-SetupProcess -FilePath $env:ComSpec -Arguments "/c exit 3010"'}
        )) {
            $file = Join-Path $temp ($test.Name + '.ps1')
            [IO.File]::WriteAllText($file, $test.Body)
            $request = [ordered]@{
                PackageRoot=$root; StepId=$test.Name; RunDirectory=$temp; ScriptPath=$file; Parameters=@{}
                LogPath=(Join-Path $temp ($test.Name+'.log')); ProgressPath=(Join-Path $temp ($test.Name+'.progress.json'))
                ResultPath=(Join-Path $temp ($test.Name+'.result.json'))
            }
            $requestFile = Join-Path $temp ($test.Name+'.request.json')
            Write-SetupJson $requestFile $request
            $argsText = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -RequestPath "{1}"' -f (Join-Path $root 'Core/Invoke-SetupStep.ps1'),$requestFile
            $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argsText -Wait -PassThru
            Assert-True ($process.ExitCode -eq $test.Code) ("Worker exit code: " + $test.Name)
            if ($test.Name -eq 'success') {
                $progress = Get-Content -LiteralPath $request.ProgressPath -Raw | ConvertFrom-Json
                Assert-True ($progress.Percent -eq 50) 'Worker publishes progress updates'
            }
            if ($test.Name -eq 'failure') {
                $result = Get-Content -LiteralPath $request.ResultPath -Raw | ConvertFrom-Json
                Assert-True ($result.Error -like '*Intentional smoke-test failure*') 'Worker captures failure details'
            }
        }
    }
    finally { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host "All $script:checks checks passed. ServiceUI/session/DPI checks are still manual; see Docs/TESTING.md."
