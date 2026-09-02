#requires -Version 5.1

<#
    SystemSupportInfo.Configuration.psm1

    Loads the application's PSD1 configuration without requiring module
    auto-loading in hosted PowerShell runspaces such as a compiled PS2EXE app.
#>

function Import-SystemSupportConfigurationWithParser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath
    )

    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $LiteralPath,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if (@($parseErrors).Count -gt 0) {
        $messages = @(
            $parseErrors | ForEach-Object {
                'Line {0}, column {1}: {2}' -f `
                    $_.Extent.StartLineNumber,
                    $_.Extent.StartColumnNumber,
                    $_.Message
            }
        )

        throw "The configuration contains invalid PowerShell syntax:`n$($messages -join "`n")"
    }

    $statements = @($scriptAst.EndBlock.Statements)
    if ($statements.Count -ne 1 -or $statements[0] -isnot [System.Management.Automation.Language.PipelineAst]) {
        throw 'The configuration must contain exactly one top-level hashtable.'
    }

    $pipelineElements = @($statements[0].PipelineElements)
    if ($pipelineElements.Count -ne 1 -or $pipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst]) {
        throw 'The configuration must contain exactly one top-level hashtable.'
    }

    $expressionAst = $pipelineElements[0].Expression
    if ($expressionAst -isnot [System.Management.Automation.Language.HashtableAst]) {
        throw 'The configuration must contain exactly one top-level hashtable.'
    }

    try {
        $configuration = $expressionAst.SafeGetValue()
    }
    catch {
        throw "The configuration contains an expression that cannot be loaded safely. Use literal PSD1 values only. $($_.Exception.Message)"
    }

    if ($configuration -isnot [hashtable]) {
        throw 'The configuration did not produce a hashtable.'
    }

    return $configuration
}

function Import-SystemSupportConfiguration {
    <#
    .SYNOPSIS
        Safely imports a SystemSupportInfo PSD1 configuration.

    .DESCRIPTION
        Uses Import-PowerShellDataFile when it is available. If a hosted
        runspace does not expose that cmdlet, safely evaluates the single
        hashtable expression through PowerShell's abstract syntax tree.

    .PARAMETER LiteralPath
        Path to the PSD1 configuration file.

    .PARAMETER UseParserFallback
        Uses the built-in parser directly. Intended for validation and
        troubleshooting of hosted PowerShell environments.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LiteralPath,

        [Parameter()]
        [switch]$UseParserFallback
    )

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $LiteralPath -ErrorAction Stop).Path
    }
    catch {
        throw "Configuration file not found: $LiteralPath"
    }

    if (-not $UseParserFallback) {
        $dataFileCommand = Get-Command `
            -Name Import-PowerShellDataFile `
            -CommandType Cmdlet, Function `
            -ErrorAction SilentlyContinue

        if (-not $dataFileCommand) {
            try {
                Import-Module -Name Microsoft.PowerShell.Utility -ErrorAction Stop
                $dataFileCommand = Get-Command `
                    -Name Import-PowerShellDataFile `
                    -CommandType Cmdlet, Function `
                    -ErrorAction SilentlyContinue
            }
            catch {
                # Hosted runspaces do not always expose every inbox command.
                # The parser fallback below has no module auto-load dependency.
            }
        }

        if ($dataFileCommand) {
            try {
                return & $dataFileCommand -LiteralPath $resolvedPath -ErrorAction Stop
            }
            catch {
                throw "The configuration could not be loaded from '$resolvedPath'. $($_.Exception.Message)"
            }
        }
    }

    return Import-SystemSupportConfigurationWithParser -LiteralPath $resolvedPath
}

Export-ModuleMember -Function Import-SystemSupportConfiguration
