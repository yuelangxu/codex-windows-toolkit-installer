[CmdletBinding()]
param(
    [string]$ToolkitRoot,
    [switch]$IncludeProfileIntegration
)

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'common.ps1')

$context = Get-ToolkitContext -ToolkitRoot $ToolkitRoot

function Write-ManagedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-Directory -Path $parent
    }

    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
        if ($existing -ne $Content) {
            Ensure-Directory -Path $context.ToolkitBackups
            $leaf = Split-Path -Leaf $Path
            $backup = Join-Path $context.ToolkitBackups ("{0}.{1}.bak" -f $leaf, (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Copy-Item -LiteralPath $Path -Destination $backup -Force
        }
    }

    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Ensure-UserPathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Entry
    )

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = if ([string]::IsNullOrWhiteSpace($userPath)) { @() } else { $userPath -split ';' }
    if ($entries -notcontains $Entry) {
        $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $Entry } else { $userPath.TrimEnd(';') + ';' + $Entry }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    }

    if (($env:Path -split ';') -notcontains $Entry) {
        $env:Path = "$Entry;$env:Path"
    }
}

Write-Section 'Deploying toolkit assets'
Ensure-Directory -Path $context.ToolkitRoot
Ensure-Directory -Path $context.ToolkitBackups
Ensure-Directory -Path $context.ToolkitScripts
Ensure-Directory -Path $context.ToolkitBin
Ensure-Directory -Path $context.ToolkitConfig
Ensure-UserPathEntry -Entry $context.ToolkitBin

foreach ($assetName in @('easyocr_read.py', 'paddleocr_read.py', 'donut_ocr.py', 'ocr_common.ps1', 'ocr_smart.ps1', 'pdf_smart.ps1', 'ocr_models.ps1')) {
    Copy-Item -LiteralPath (Join-Path $script:AssetsRoot $assetName) -Destination (Join-Path $context.ToolkitScripts $assetName) -Force
}

$starshipConfig = Get-Content -LiteralPath (Join-Path $script:AssetsRoot 'starship.toml') -Raw
Write-ManagedFile -Path $context.StarshipConfigDestination -Content $starshipConfig

if ($IncludeProfileIntegration) {
    Ensure-Directory -Path $context.PowerShellRoot
    Ensure-Directory -Path $context.PowerShellScriptsRoot

    foreach ($profileAsset in @('codex.document-tools.ps1', 'codex.ocr-translate-tools.ps1', 'codex.web-auth-tools.ps1')) {
        $profileContent = Get-Content -LiteralPath (Join-Path $script:AssetsRoot $profileAsset) -Raw
        Write-ManagedFile -Path (Join-Path $context.PowerShellRoot $profileAsset) -Content $profileContent
    }

    $authScriptContent = Get-Content -LiteralPath (Join-Path $script:AssetsRoot 'codex_auth_web.py') -Raw
    Write-ManagedFile -Path (Join-Path $context.PowerShellScriptsRoot 'codex_auth_web.py') -Content $authScriptContent

    $sharedContent = Get-Content -LiteralPath (Join-Path $script:AssetsRoot 'profile.shared.ps1') -Raw
    Write-ManagedFile -Path $context.SharedProfileDestination -Content $sharedContent

    $sharedProfileLiteral = $context.SharedProfileDestination.Replace("'", "''")
    $stubContent = @"
`$sharedProfile = '$sharedProfileLiteral'
if (Test-Path -LiteralPath `$sharedProfile) {
    . `$sharedProfile
}
"@

    foreach ($stubPath in @(
        (Join-Path $context.DocumentsRoot 'PowerShell\profile.ps1'),
        (Join-Path $context.DocumentsRoot 'PowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $context.DocumentsRoot 'WindowsPowerShell\profile.ps1'),
        (Join-Path $context.DocumentsRoot 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    )) {
        Write-ManagedFile -Path $stubPath -Content $stubContent
    }
}

$wrapperMap = @{
    'easyocr-read.cmd' = @"
@echo off
set "PYTHONIOENCODING=utf-8"
set "NO_ALBUMENTATIONS_UPDATE=1"
set "PATH=$($context.ToolkitTorchLib);%PATH%"
"$($context.ToolkitVenvPython)" "$($context.ToolkitScripts)\easyocr_read.py" %*
"@
    'paddleocr-read.cmd' = @"
@echo off
set "PYTHONIOENCODING=utf-8"
set "PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True"
set "PATH=$($context.ToolkitTorchLib);%PATH%"
"$($context.ToolkitVenvPython)" "$($context.ToolkitScripts)\paddleocr_read.py" %*
"@
    'donut-ocr.cmd' = @"
@echo off
set "PYTHONIOENCODING=utf-8"
set "PATH=$($context.ToolkitTorchLib);%PATH%"
"$($context.ToolkitVenvPython)" "$($context.ToolkitScripts)\donut_ocr.py" %*
"@
    'llava.cmd' = @"
@echo off
setlocal EnableDelayedExpansion
set "args="
:parse
if "%~1"=="" goto run
if /I "%~1"=="--cpu" (
    set "OLLAMA_NUM_GPU=0"
) else (
    set "args=!args! "%~1""
)
shift
goto parse
:run
call ollama run llava !args!
"@
    'ocr-smart.cmd' = @"
@echo off
powershell -NoLogo -ExecutionPolicy Bypass -File "$($context.ToolkitScripts)\ocr_smart.ps1" %*
"@
    'pdf-smart.cmd' = @"
@echo off
powershell -NoLogo -ExecutionPolicy Bypass -File "$($context.ToolkitScripts)\pdf_smart.ps1" %*
"@
    'ocr-models.cmd' = @"
@echo off
powershell -NoLogo -ExecutionPolicy Bypass -File "$($context.ToolkitScripts)\ocr_models.ps1" %*
"@
}

foreach ($entry in $wrapperMap.GetEnumerator()) {
    Write-ManagedFile -Path (Join-Path $context.ToolkitBin $entry.Key) -Content $entry.Value
}

if ($IncludeProfileIntegration) {
    Write-Host 'Assets, wrapper commands, shared profile, and shell prompt config have been deployed.' -ForegroundColor Green
} else {
    Write-Host 'Assets, wrapper commands, and shell prompt config have been deployed. Shared profile integration was skipped.' -ForegroundColor Green
}
