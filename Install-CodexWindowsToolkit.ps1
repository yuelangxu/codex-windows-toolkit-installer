[CmdletBinding()]
param(
    [string]$ToolkitRoot,
    [string]$InstallScope = 'Auto',
    [switch]$AuditOnly,
    [switch]$AutoApprove,
    [switch]$IncludeLlavaModel,
    [switch]$SkipLlavaModel,
    [switch]$IncludeOptionalPackages,
    [switch]$IncludeProfileIntegration,
    [switch]$DisableProfileIntegration,
    [switch]$ForceOcrRepair
)

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'common.ps1')

$context = Get-ToolkitContext -ToolkitRoot $ToolkitRoot
$useProfileIntegration = $true
if ($DisableProfileIntegration) {
    $useProfileIntegration = $false
} elseif ($PSBoundParameters.ContainsKey('IncludeProfileIntegration')) {
    $useProfileIntegration = $IncludeProfileIntegration.IsPresent
}

Write-Section $script:Manifest.ToolkitName
Write-Note ("Toolkit root: {0}" -f $context.ToolkitRoot)
Write-Note ("Install scope preference: {0}" -f $InstallScope)
Write-Note ("PowerShell profile integration: {0}" -f $(if ($useProfileIntegration) { 'enabled (default)' } else { 'disabled' }))
Write-Note ("Recommended extra CLI tools: {0}" -f $(if ($IncludeOptionalPackages) { 'enabled' } else { 'disabled' }))

$auditScript = Join-Path $script:InstallerRoot 'Audit-CodexWindowsToolkit.ps1'
$wingetScript = Join-Path $script:InstallerRoot 'Install-CodexWingetPackages.ps1'
$moduleScript = Join-Path $script:InstallerRoot 'Install-CodexPowerShellModules.ps1'
$profilesScript = Join-Path $script:InstallerRoot 'Install-CodexProfilesAndWrappers.ps1'
$ocrScript = Join-Path $script:InstallerRoot 'Install-CodexOcrEnvironment.ps1'

& $auditScript -ToolkitRoot $context.ToolkitRoot -IncludeProfileIntegration:$useProfileIntegration

if ($AuditOnly) {
    Write-Note 'Audit-only mode requested; stopping here.'
    return
}

$shouldProceed = $AutoApprove.IsPresent
if (-not $shouldProceed) {
    Write-Host ''
    $answer = Read-Host 'Proceed with Codex Windows Toolkit installation and shell enhancement? [Y/N]'
    $shouldProceed = $answer -match '^(y|yes)$'
}

if (-not $shouldProceed) {
    Write-Warning 'Installation cancelled.'
    return
}

& $wingetScript -InstallScope $InstallScope -IncludeOptionalPackages:$IncludeOptionalPackages
& $moduleScript
& $profilesScript -ToolkitRoot $context.ToolkitRoot -IncludeProfileIntegration:$useProfileIntegration

$ocrArguments = @{
    ToolkitRoot = $context.ToolkitRoot
}
if ($AutoApprove) { $ocrArguments.AutoApprove = $true }
if ($IncludeLlavaModel) { $ocrArguments.IncludeLlavaModel = $true }
if ($SkipLlavaModel) { $ocrArguments.SkipLlavaModel = $true }
$ocrHealthy = Test-ToolkitOcrHealthy -Context $context
$shouldRunOcr = $ForceOcrRepair -or (-not $ocrHealthy) -or $IncludeLlavaModel

if ($shouldRunOcr) {
    & $ocrScript @ocrArguments
} else {
    Write-Note 'OCR environment already looks healthy; skipping heavy OCR reinstall.'
}

Write-Section 'Final audit'
& $auditScript -ToolkitRoot $context.ToolkitRoot -IncludeProfileIntegration:$useProfileIntegration

Write-Host ''
Write-Host 'Codex Windows Toolkit installation completed.' -ForegroundColor Green
Write-Host 'Open a new PowerShell or pwsh window to load the refreshed PATH, profile enhancements, and command hints.' -ForegroundColor DarkGray
