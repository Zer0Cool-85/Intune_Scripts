BeforeAll {
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $projectRoot 'Modules\EnterpriseAutopilotBranding.psm1') -Force
    $script:Config = Import-EabConfiguration -Path (Join-Path $projectRoot 'Config.xml')
}

Describe 'Configuration' {
    It 'uses schema version 2' {
        [string]$Config.SchemaVersion | Should -Be '2'
    }

    It 'contains a valid package version' {
        { [version]$Config.PackageVersion } | Should -Not -Throw
    }

    It 'uses a valid debloat mode' {
        [string]$Config.Debloat.Mode | Should -BeIn @('Audit', 'Enforce')
    }

    It 'does not use a dangerously broad enabled removal pattern' {
        $patterns = @()
        $patterns += @($Config.Debloat.AppxPackages.Package | Where-Object { Get-EabBoolean -Value $_.Enabled -Default $true } | ForEach-Object NamePattern)
        $patterns += @($Config.Debloat.ClassicApplications.Application | Where-Object { Get-EabBoolean -Value $_.Enabled -Default $true } | ForEach-Object DisplayNamePattern)
        foreach ($pattern in $patterns) {
            ($pattern -replace '[\*\?\[\]]', '').Length | Should -BeGreaterOrEqual 4
        }
    }

    It 'contains unique, versioned enabled onboarding steps' {
        $steps = @($Config.PostEnroll.Steps.Step | Where-Object { Get-EabBoolean -Value $_.Enabled -Default $true })
        $steps.Count | Should -BeGreaterThan 0
        @($steps | ForEach-Object Id | Select-Object -Unique).Count | Should -Be $steps.Count
        foreach ($step in $steps) {
            { [version]$step.Version } | Should -Not -Throw
        }
    }

    It 'pins the production PSAppDeployToolkit release' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $projectRoot 'Onboarding\PSAppDeployToolkit\PSAppDeployToolkit.psd1')
        [version]$manifest.ModuleVersion | Should -Be ([version]'4.1.8')
    }
}

Describe 'Dell safeguards' {
    BeforeAll {
        $script:PreservePatterns = @($Config.Debloat.PreserveClassicApplications.Application | Where-Object {
            Get-EabBoolean -Value $_.Enabled -Default $true
        } | ForEach-Object DisplayNamePattern)
        $script:RemovalPatterns = @($Config.Debloat.ClassicApplications.Application | Where-Object {
            Get-EabBoolean -Value $_.Enabled -Default $true
        } | ForEach-Object DisplayNamePattern)
    }

    It 'preserves <Name>' -TestCases @(
        @{ Name = 'Dell Command | Update' },
        @{ Name = 'Dell Command | Update for Windows Universal' },
        @{ Name = 'Dell Command Update' },
        @{ Name = 'Dell Trusted Device' },
        @{ Name = 'Dell Core Services' },
        @{ Name = 'Dell TechHub' },
        @{ Name = 'Dell Client Device Manager' },
        @{ Name = 'Dell Peripheral Manager' },
        @{ Name = 'Dell Display Manager' }
    ) {
        param($Name)
        @($PreservePatterns | Where-Object { $Name -like $_ }).Count | Should -BeGreaterThan 0
    }

    It 'does not select Dell Command Update for removal without a preservation match' -TestCases @(
        @{ Name = 'Dell Command | Update' },
        @{ Name = 'Dell Command | Update for Windows Universal' },
        @{ Name = 'Dell Command Update' }
    ) {
        param($Name)
        $selectedForRemoval = @($RemovalPatterns | Where-Object { $Name -like $_ }).Count -gt 0
        $selectedForPreservation = @($PreservePatterns | Where-Object { $Name -like $_ }).Count -gt 0
        ($selectedForRemoval -and -not $selectedForPreservation) | Should -BeFalse
    }
}

Describe 'Project assets' {
    It 'contains every enabled branding asset' {
        { Test-EabConfiguredAssets -Config $Config -SourceRoot $projectRoot } | Should -Not -Throw
    }
}

Describe 'Runtime integrity manifest' {
    It 'detects changed and additional runtime files' {
        $runtime = Join-Path $TestDrive 'Runtime'
        $nested = Join-Path $runtime 'Modules'
        New-Item -Path $nested -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $runtime 'Config.xml') -Value '<test />' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $nested 'Module.psm1') -Value '# test' -Encoding UTF8

        $manifest = @(Get-EabRuntimeManifest -RuntimeRoot $runtime)
        Test-EabRuntimeManifest -RuntimeRoot $runtime -Manifest $manifest | Should -BeTrue

        Add-Content -LiteralPath (Join-Path $nested 'Module.psm1') -Value '# changed' -Encoding UTF8
        Test-EabRuntimeManifest -RuntimeRoot $runtime -Manifest $manifest | Should -BeFalse

        Set-Content -LiteralPath (Join-Path $nested 'Module.psm1') -Value '# test' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $runtime 'Extra.txt') -Value 'extra' -Encoding UTF8
        Test-EabRuntimeManifest -RuntimeRoot $runtime -Manifest $manifest | Should -BeFalse
    }
}
