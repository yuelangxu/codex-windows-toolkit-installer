[CmdletBinding()]
param(
    [string]$ToolkitRoot,
    [string]$InstallScope = 'Auto',
    [switch]$CoreOnly,
    [switch]$IncludeLlavaModel,
    [switch]$AutoApprove,
    [switch]$KeepOllamaStartupShortcut
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
Write-Note ("Web automation layer: ChatGPT control + browser-extension automation + shared helper script")
Write-Note ("Phone debugging layer: adb + scrcpy + diagnostics + storage scan + UI dump + Shizuku + APK staging")
Write-Note ("Remote/network layer: SSH baseline + proxy profile + Shadowsocks helpers + local-only private import")
Write-Note ("Ollama startup policy: {0}" -f $(if ($KeepOllamaStartupShortcut) { 'leave any Windows Startup shortcut untouched' } else { 'demand-start only; disable Windows Startup shortcut if present' }))
Write-Note ('Private secrets policy: installer only imports from local env vars, private files, or existing local client configs; it never writes your secrets into the public repo.')
Write-Note ("Phone toolkit guide path: {0}" -f $context.ToolkitPhoneGuidePath)
Write-Note ("Network guide path: {0}" -f $context.ToolkitNetworkGuidePath)
Write-Note ("Shadowsocks guide path: {0}" -f $context.ToolkitShadowsocksGuidePath)
Write-Note ("Web-auth guide path: {0}" -f $context.ToolkitWebAuthGuidePath)
Write-Note ("Browser extension starter project path: {0}" -f $context.ToolkitBrowserExtensionStarterPath)

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

Write-Host ''
Write-Host 'The refreshed installer now also deploys remote/network helpers, local-only Shadowsocks secret import, Android phone-debugging helpers, ChatGPT automation helpers, browser-extension automation helpers, a web-auth guide, and starter example projects.' -ForegroundColor DarkGray

$includeOptionalPackages = -not $CoreOnly

if (-not $AutoApprove) {
    Write-Host ''
    Write-Host 'Actions:' -ForegroundColor Cyan
    Write-Host '  Y = install/repair baseline toolkit, phone/web automation tooling, and recommended extras'
    Write-Host '  C = install/repair baseline toolkit plus phone/web automation tooling only'
    Write-Host '  L = baseline + phone/web automation tooling + extras + pull llava model'
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
    -IncludeLlavaModel:$IncludeLlavaModel `
    -KeepOllamaStartupShortcut:$KeepOllamaStartupShortcut

Write-Section 'Post-Install Tool Summary'
& $inventoryScript -ToolkitRoot $context.ToolkitRoot -SummaryOnly

Write-Section 'Post-Install Audit'
& $auditScript -ToolkitRoot $context.ToolkitRoot -IncludeProfileIntegration
