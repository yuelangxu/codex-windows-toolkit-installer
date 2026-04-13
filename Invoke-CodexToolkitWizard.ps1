[CmdletBinding()]
param(
    [string]$ToolkitRoot,
    [string]$InstallScope = 'Auto',
    [switch]$CoreOnly,
    [switch]$IncludeLlavaModel,
    [switch]$AutoApprove
)

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'common.ps1')

$context = Get-ToolkitContext -ToolkitRoot $ToolkitRoot
$auditScript = Join-Path $script:InstallerRoot 'Audit-CodexWindowsToolkit.ps1'
$inventoryScript = Join-Path $script:InstallerRoot 'Show-CodexToolkitInventory.ps1'
$installerScript = Join-Path $script:InstallerRoot 'Install-CodexWindowsToolkit.ps1'

Write-Section 'Codex Toolkit Wizard'
Write-Note ("User profile: {0}" -f $env:USERNAME)
Write-Note ("Documents root: {0}" -f $context.DocumentsRoot)
Write-Note ("PowerShell root: {0}" -f $context.PowerShellRoot)
Write-Note ("Toolkit root: {0}" -f $context.ToolkitRoot)
Write-Note ("Cloud-backed documents: {0}" -f $(if ($context.DocumentsRoot -match '\\OneDrive\\') { 'yes (OneDrive detected)' } else { 'no (local Documents detected)' }))
Write-Note ("Heavy OCR rebuild needed: {0}" -f $(if (Test-ToolkitOcrHealthyQuick -Context $context) { 'no, current OCR stack looks healthy' } else { 'yes, OCR stack needs repair/build' }))

Write-Section 'Current Tool Summary'
& $inventoryScript -ToolkitRoot $context.ToolkitRoot -SummaryOnly

Write-Section 'Current Audit'
& $auditScript -ToolkitRoot $context.ToolkitRoot -IncludeProfileIntegration

$optionalStates = foreach ($package in $script:Manifest.OptionalWingetPackages) {
    $state = Get-PackageState -Package $package
    [pscustomobject]@{
        Tool = $package.DisplayName
        Status = if ($state.Installed) { 'Installed' } else { 'Missing' }
        Detail = $state.Detail
    }
}

$missingOptional = @($optionalStates | Where-Object Status -eq 'Missing')
Write-Host ''
if ($missingOptional.Count -gt 0) {
    Write-Host 'Recommended extras that can still be installed:' -ForegroundColor Yellow
    $missingOptional | Format-Table -AutoSize
} else {
    Write-Host 'Recommended extra CLI tools are already present.' -ForegroundColor Green
}

$includeOptionalPackages = -not $CoreOnly

if (-not $AutoApprove) {
    Write-Host ''
    Write-Host 'Actions:' -ForegroundColor Cyan
    Write-Host '  Y = install/repair baseline toolkit and recommended extras'
    Write-Host '  C = install/repair baseline toolkit only'
    Write-Host '  L = baseline + extras + pull llava model'
    Write-Host '  N = cancel'
    $answer = (Read-Host 'Choose Y, C, L, or N').Trim()

    switch -Regex ($answer) {
        '^(y)$' {
            $includeOptionalPackages = $true
        }
        '^(c)$' {
            $includeOptionalPackages = $false
        }
        '^(l)$' {
            $includeOptionalPackages = $true
            $IncludeLlavaModel = $true
        }
        default {
            Write-Warning 'Wizard cancelled.'
            return
        }
    }
}

& $installerScript `
    -ToolkitRoot $context.ToolkitRoot `
    -InstallScope $InstallScope `
    -AutoApprove `
    -IncludeProfileIntegration `
    -IncludeOptionalPackages:$includeOptionalPackages `
    -IncludeLlavaModel:$IncludeLlavaModel

Write-Section 'Post-Install Tool Summary'
& $inventoryScript -ToolkitRoot $context.ToolkitRoot -SummaryOnly

Write-Section 'Post-Install Audit'
& $auditScript -ToolkitRoot $context.ToolkitRoot -IncludeProfileIntegration
