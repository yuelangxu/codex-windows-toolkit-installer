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

function Copy-ManagedDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Ensure-Directory -Path $DestinationPath
    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path

    foreach ($item in Get-ChildItem -LiteralPath $resolvedSource -Recurse -File -Force) {
        $relativePath = $item.FullName.Substring($resolvedSource.Length).TrimStart('\')
        $destinationFile = Join-Path $DestinationPath $relativePath
        $content = Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop
        Write-ManagedFile -Path $destinationFile -Content $content
    }
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

function Install-WebAuthPythonDependencies {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $pythonPath = Find-ToolkitAutomationPython
    if ([string]::IsNullOrWhiteSpace($pythonPath)) {
        Write-Warning 'Skipping proactive web-auth Python dependency install because no suitable Python interpreter was found.'
        return
    }

    $missingPackages = New-Object System.Collections.Generic.List[string]
    foreach ($module in $script:Manifest.WebAuthPythonModules) {
        $state = Get-GlobalPythonImportState -ModuleName $module.ImportName -PythonPath $pythonPath
        if (-not $state.Installed) {
            [void]$missingPackages.Add($module.Package)
        }
    }

    if ($missingPackages.Count -eq 0) {
        Write-Note ("Web-auth Python dependencies already look healthy ({0})." -f $pythonPath)
        return
    }

    $packageList = [string]::Join(', ', $missingPackages.ToArray())
    Write-Host ("Installing web-auth Python dependencies via {0}: {1}" -f $pythonPath, $packageList) -ForegroundColor Yellow
    $pipArguments = @('install', '--user', '--no-warn-script-location') + @($missingPackages.ToArray())
    Invoke-ToolkitPipInstall -PythonPath $pythonPath -Arguments $pipArguments -IndexUrl 'https://pypi.org/simple' -RetryCount 3 -RetryDelaySeconds 10
}

function Invoke-ShadowsocksPrivateBootstrap {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $networkToolsPath = Join-Path $Context.PowerShellRoot 'codex.network-tools.ps1'
    if (-not (Test-Path -LiteralPath $networkToolsPath)) {
        return
    }

    try {
        . $networkToolsPath
        $importResult = ss-secret-import -Quiet -FetchWindowsClient -ExpandWindowsClient
        if ($null -eq $importResult) {
            return
        }

        if ($importResult.PSObject.Properties['Imported'] -and $importResult.Imported) {
            Write-Note ("Imported local-only Shadowsocks secret into toolkit state ({0})." -f $importResult.ActiveSecretPath)
            if ($importResult.PSObject.Properties['WindowsClientPath'] -and -not [string]::IsNullOrWhiteSpace($importResult.WindowsClientPath)) {
                Write-Note ("Official Windows Shadowsocks client prepared at {0}." -f $importResult.WindowsClientPath)
            }
            return
        }

        Write-Note 'No local Shadowsocks private config source was detected. Public repo contents remain secret-free.'
    } catch {
        Write-Warning ("Shadowsocks private bootstrap skipped: {0}" -f $_.Exception.Message)
    }
}

Write-Section 'Deploying toolkit assets'
Ensure-Directory -Path $context.ToolkitRoot
Ensure-Directory -Path $context.ToolkitBackups
Ensure-Directory -Path $context.ToolkitScripts
Ensure-Directory -Path $context.ToolkitBin
Ensure-Directory -Path $context.ToolkitDocs
Ensure-Directory -Path $context.ToolkitExamples
Ensure-Directory -Path $context.ToolkitConfig
Ensure-Directory -Path $context.ToolkitPrivateConfig
Ensure-UserPathEntry -Entry $context.ToolkitBin

foreach ($assetName in @('easyocr_read.py', 'paddleocr_read.py', 'donut_ocr.py', 'ocr_common.ps1', 'ocr_smart.ps1', 'pdf_smart.ps1', 'ocr_models.ps1')) {
    Copy-Item -LiteralPath (Join-Path $script:AssetsRoot $assetName) -Destination (Join-Path $context.ToolkitScripts $assetName) -Force
}

$webAuthGuideContent = Get-Content -LiteralPath (Join-Path $script:AssetsRoot 'Codex-Web-Auth-Toolkit.md') -Raw
Write-ManagedFile -Path $context.ToolkitWebAuthGuidePath -Content $webAuthGuideContent

$phoneGuideContent = Get-Content -LiteralPath (Join-Path $script:AssetsRoot 'Codex-Phone-Toolkit.md') -Raw
Write-ManagedFile -Path $context.ToolkitPhoneGuidePath -Content $phoneGuideContent

$networkGuideContent = Get-Content -LiteralPath (Join-Path $script:AssetsRoot 'Codex-Network-Toolkit.md') -Raw
Write-ManagedFile -Path $context.ToolkitNetworkGuidePath -Content $networkGuideContent

$shadowsocksGuideContent = Get-Content -LiteralPath (Join-Path $script:AssetsRoot 'Codex-Shadowsocks-Toolkit.md') -Raw
Write-ManagedFile -Path $context.ToolkitShadowsocksGuidePath -Content $shadowsocksGuideContent

Copy-ManagedDirectory -SourcePath (Join-Path $script:AssetsRoot 'browser-extension-starter') -DestinationPath $context.ToolkitBrowserExtensionStarterPath
Copy-ManagedDirectory -SourcePath (Join-Path $script:AssetsRoot 'android-apk-tools') -DestinationPath $context.ToolkitAndroidApkToolsPath
Copy-ManagedDirectory -SourcePath (Join-Path $script:AssetsRoot 'termux-bootstrap') -DestinationPath $context.ToolkitTermuxBootstrapPath

$starshipConfig = Get-Content -LiteralPath (Join-Path $script:AssetsRoot 'starship.toml') -Raw
Write-ManagedFile -Path $context.StarshipConfigDestination -Content $starshipConfig

if ($IncludeProfileIntegration) {
    Ensure-Directory -Path $context.PowerShellRoot
    Ensure-Directory -Path $context.PowerShellScriptsRoot

    foreach ($profileAsset in @('codex.phone-tools.ps1', 'codex.document-tools.ps1', 'codex.ocr-translate-tools.ps1', 'codex.web-auth-tools.ps1', 'codex.network-tools.ps1')) {
        $profileContent = Get-Content -LiteralPath (Join-Path $script:AssetsRoot $profileAsset) -Raw
        Write-ManagedFile -Path (Join-Path $context.PowerShellRoot $profileAsset) -Content $profileContent
    }

    $authScriptContent = Get-Content -LiteralPath (Join-Path $script:AssetsRoot 'codex_auth_web.py') -Raw
    Write-ManagedFile -Path (Join-Path $context.PowerShellScriptsRoot 'codex_auth_web.py') -Content $authScriptContent

    Install-WebAuthPythonDependencies -Context $context

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

    Invoke-ShadowsocksPrivateBootstrap -Context $context
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
    Write-Host 'Assets, wrapper commands, shared profile, phone toolkit, network/web-auth guides, extension starter project, and shell prompt config have been deployed.' -ForegroundColor Green
} else {
    Write-Host 'Assets, wrapper commands, phone toolkit, network/web-auth guides, extension starter project, and shell prompt config have been deployed. Shared profile integration was skipped.' -ForegroundColor Green
}
