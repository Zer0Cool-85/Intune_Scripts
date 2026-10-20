# Windows PowerShell 5.1 compatible. No UI is loaded by this file.
Set-StrictMode -Version 2.0

function Get-SetupHash {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Resolve-SetupContentPath {
    param([string]$Root, [string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $null }
    if ([IO.Path]::IsPathRooted($RelativePath)) {
        throw "Use a package-relative path, not an absolute path: $RelativePath"
    }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $path = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
    if (-not $path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must remain inside the package: $RelativePath"
    }
    return $path
}

function Assert-SetupProperties {
    param($Object, [string[]]$Names, [string]$Location)
    if ($null -eq $Object) { throw "Missing object: $Location" }
    foreach ($name in $Names) {
        if ($null -eq $Object.PSObject.Properties[$name]) { throw "Missing setting: $Location.$name" }
    }
}

function Read-SetupConfiguration {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$PackageRoot)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Configuration not found: $Path" }
    $cfg = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    Assert-SetupProperties $cfg @('SchemaVersion','SetupId','SetupVersion','Branding','Appearance','Text','Behavior','Steps') 'Config'
    if ($cfg.SchemaVersion -ne 1) { throw 'SchemaVersion must be 1.' }
    if ($cfg.SetupId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') { throw 'SetupId must be 1-80 letters, digits, periods, underscores, or hyphens.' }
    if ($cfg.SetupVersion -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$') { throw 'SetupVersion must be a safe 1-40 character version string.' }
    Assert-SetupProperties $cfg.Branding @('CompanyName','WindowTitle','Heading','Message','LogoPath','BannerPath','BannerHeight','LogoMaxWidth','LogoMaxHeight') 'Branding'
    Assert-SetupProperties $cfg.Appearance @('Theme','AccentColor','SuccessColor','FailureColor','WarningColor','WindowWidth','WindowHeight','Topmost','ReduceMotion','ShowElapsedTime','ShowStepNumbers','FontFamily') 'Appearance'
    Assert-SetupProperties $cfg.Text @('RunningHeading','RunningMessage','SuccessHeading','SuccessMessage','WarningHeading','WarningMessage','FailureHeading','FailureMessage','Footer','Support','RetryButton','CloseButton','CopyButton','DetailsLabel') 'Text'
    Assert-SetupProperties $cfg.Behavior @('RequireSystemForLive','ResumeCompletedSteps','StopOnRequiredFailure','AllowRetry','AutoCloseSuccessSeconds','PollIntervalMilliseconds','StateDirectory') 'Behavior'
    if ($cfg.Appearance.Theme -notin @('Light','Dark')) { throw 'Appearance.Theme must be Light or Dark.' }
    foreach ($color in @('AccentColor','SuccessColor','FailureColor','WarningColor')) {
        if ($cfg.Appearance.$color -notmatch '^#[0-9a-fA-F]{6}$') { throw "Appearance.$color must be #RRGGBB." }
    }
    foreach ($pair in @(@($cfg.Appearance,'Topmost'),@($cfg.Appearance,'ReduceMotion'),@($cfg.Appearance,'ShowElapsedTime'),@($cfg.Appearance,'ShowStepNumbers'),@($cfg.Behavior,'RequireSystemForLive'),@($cfg.Behavior,'ResumeCompletedSteps'),@($cfg.Behavior,'StopOnRequiredFailure'),@($cfg.Behavior,'AllowRetry'))) {
        if ($pair[0].($pair[1]) -isnot [bool]) { throw "$($pair[1]) must be a JSON boolean." }
    }
    foreach ($range in @(
        @('WindowWidth',$cfg.Appearance.WindowWidth,640,1600),
        @('WindowHeight',$cfg.Appearance.WindowHeight,520,1200),
        @('BannerHeight',$cfg.Branding.BannerHeight,40,240),
        @('LogoMaxWidth',$cfg.Branding.LogoMaxWidth,24,400),
        @('LogoMaxHeight',$cfg.Branding.LogoMaxHeight,24,120),
        @('PollIntervalMilliseconds',$cfg.Behavior.PollIntervalMilliseconds,200,2000),
        @('AutoCloseSuccessSeconds',$cfg.Behavior.AutoCloseSuccessSeconds,0,3600)
    )) {
        if ($range[1] -is [string] -or $range[1] -is [bool] -or $range[1] -isnot [ValueType] -or $range[1] -lt $range[2] -or $range[1] -gt $range[3]) {
            throw "$($range[0]) must be a number between $($range[2]) and $($range[3])."
        }
    }
    foreach ($field in @('LogoPath','BannerPath')) {
        $p = Resolve-SetupContentPath $PackageRoot $cfg.Branding.$field
        if ($p) {
            if ([IO.Path]::GetExtension($p) -notin @('.png','.jpg','.jpeg','.bmp')) { throw "$field supports PNG, JPG, or BMP." }
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Branding image not found: $p" }
        }
    }
    if (@($cfg.Steps).Count -lt 1 -or @($cfg.Steps).Count -gt 10) { throw 'Configure between 1 and 10 steps total.' }
    $ids = @{}
    $enabledBefore = @{}
    $enabledCount = 0
    foreach ($step in $cfg.Steps) {
        Assert-SetupProperties $step @('Id','Enabled','Title','Description','Script','Parameters','TimeoutSeconds','SuccessExitCodes','RebootExitCodes','Required','DependsOn','DemoSeconds','DemoFailFirstAttempt') 'Steps[]'
        if ($step.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$') { throw "Invalid step Id: $($step.Id)" }
        if ($ids.ContainsKey($step.Id)) { throw "Duplicate step Id: $($step.Id)" }
        $ids[$step.Id] = $true
        foreach ($flag in @('Enabled','Required','DemoFailFirstAttempt')) {
            if ($step.$flag -isnot [bool]) { throw "Step $($step.Id): $flag must be a JSON boolean." }
        }
        if ([string]::IsNullOrWhiteSpace($step.Title)) { throw "Step $($step.Id) requires a Title." }
        if ($step.Parameters -isnot [pscustomobject]) { throw "Step $($step.Id): Parameters must be a JSON object." }
        if ($step.TimeoutSeconds -is [string] -or $step.TimeoutSeconds -is [bool] -or $step.TimeoutSeconds -lt 1 -or $step.TimeoutSeconds -gt 86400) { throw "Step $($step.Id): TimeoutSeconds must be 1-86400." }
        if ($step.DemoSeconds -is [string] -or $step.DemoSeconds -is [bool] -or $step.DemoSeconds -lt 1 -or $step.DemoSeconds -gt 60) { throw "Step $($step.Id): DemoSeconds must be 1-60." }
        if (@($step.SuccessExitCodes).Count -lt 1) { throw "Step $($step.Id): SuccessExitCodes cannot be empty." }
        foreach ($code in @($step.SuccessExitCodes) + @($step.RebootExitCodes)) {
            if ($code -isnot [int] -and $code -isnot [long]) { throw "Step $($step.Id): exit codes must be integers." }
        }
        foreach ($code in $step.RebootExitCodes) {
            if ($code -notin $step.SuccessExitCodes) { throw "Step $($step.Id): every RebootExitCode must also be a SuccessExitCode." }
        }
        $scriptPath = Resolve-SetupContentPath $PackageRoot $step.Script
        if (-not $scriptPath -or [IO.Path]::GetExtension($scriptPath) -ne '.ps1') { throw "Step $($step.Id) requires a relative .ps1 Script path." }
        if ($step.Enabled) {
            $enabledCount++
            if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Step script not found: $scriptPath" }
            foreach ($dependency in @($step.DependsOn)) {
                if (-not $enabledBefore.ContainsKey([string]$dependency)) { throw "Step $($step.Id): dependency '$dependency' must be an earlier enabled step." }
            }
            $enabledBefore[$step.Id] = $true
        }
    }
    if ($enabledCount -eq 0) { throw 'Enable at least one step.' }
    return $cfg
}

function Write-SetupJson {
    param([string]$Path, $Value)
    $json = $Value | ConvertTo-Json -Depth 20
    $temp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
    try {
        for ($attempt = 0; $attempt -lt 8; $attempt++) {
            try {
                if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, $null) }
                else { [IO.File]::Move($temp, $Path) }
                break
            }
            catch [IO.IOException] {
                if ($attempt -eq 7) { throw }
                # A reader can briefly hold a handle without delete sharing.
                Start-Sleep -Milliseconds 25
            }
        }
    }
    finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Get-SetupStepFingerprint {
    param($Step, [string]$PackageRoot)
    $path = Resolve-SetupContentPath $PackageRoot $Step.Script
    $execution = [ordered]@{
        Script = $Step.Script
        ScriptHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Parameters = $Step.Parameters
        SuccessExitCodes = $Step.SuccessExitCodes
        RebootExitCodes = $Step.RebootExitCodes
        DependsOn = $Step.DependsOn
    }
    return Get-SetupHash ($execution | ConvertTo-Json -Depth 15 -Compress)
}

function Get-SetupOutcome {
    param([object[]]$Items)
    $incompleteRequired = @($Items | Where-Object { $_.Definition.Required -and $_.Status -notin @('Complete','AlreadyComplete') })
    $issues = @($Items | Where-Object { $_.Status -in @('Failed','Skipped') })
    if ($incompleteRequired.Count -gt 0) { return 'Failed' }
    if ($issues.Count -gt 0) { return 'Warning' }
    return 'Success'
}

function Get-SetupDependencyBlock {
    param($Item, [object[]]$Items)
    foreach ($id in @($Item.Definition.DependsOn)) {
        $dependency = @($Items | Where-Object { $_.Definition.Id -eq $id })
        if ($dependency.Count -ne 1 -or $dependency[0].Status -notin @('Complete','AlreadyComplete')) {
            return "Waiting for successful completion of: $id"
        }
    }
    return $null
}
