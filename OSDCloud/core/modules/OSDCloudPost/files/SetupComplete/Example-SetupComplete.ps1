<#
.SYNOPSIS
    Demonstrates package-relative supporting content

.DESCRIPTION
    Reads the supplied JSON beside this script and writes diagnostic output.
    Does not install software, prompt, or restart Windows.

.PARAMETER Message
    Optional message included in script output.

.EXAMPLE
    PS> .\Example-SetupComplete.ps1

    Reads and displays the example content.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    System.String. Example content and package paths.

.NOTES
    Author:  David Segura
    Company: Recast Software
    Version: 1.0.0
    Date:    2026-11-04
#>
[CmdletBinding()]
param ([string]$Message = 'SetupComplete example')
$Error.Clear()
$ErrorActionPreference = 'Stop'
Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start"
$content = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Example-Content.json') -Raw | ConvertFrom-Json
Write-Output "$Message`: $($content.Message)"
Write-Output "ScriptRoot=$PSScriptRoot"
Write-Output "WorkingDirectory=$((Get-Location).Path)"
