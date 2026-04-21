Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:InstallerRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:AssetsRoot = Join-Path $script:InstallerRoot 'assets'
$script:Manifest = Import-PowerShellDataFile -Path (Join-Path $script:InstallerRoot 'toolkit.manifest.psd1')

function Get-DocumentsRoot {
    return [Environment]::GetFolderPath('MyDocuments')
}

function Get-ToolkitContext {
    param(
        [string]$ToolkitRoot
    )

    $documentsRoot = Get-DocumentsRoot
    $powerShellRoot = Join-Path $documentsRoot 'PowerShell'

    if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
        $ToolkitRoot = Join-Path $powerShellRoot $script:Manifest.ToolkitRootName
    }

    return [pscustomobject]@{
        ToolkitRoot = $ToolkitRoot
        ToolkitBin = (Join-Path $ToolkitRoot 'bin')
        ToolkitScripts = (Join-Path $ToolkitRoot 'scripts')
        ToolkitDocs = (Join-Path $ToolkitRoot 'docs')
        ToolkitExamples = (Join-Path $ToolkitRoot 'examples')
        ToolkitConfig = (Join-Path $ToolkitRoot 'config')
        ToolkitPrivateConfig = (Join-Path (Join-Path $ToolkitRoot 'config') 'private')
        ToolkitBackups = (Join-Path $ToolkitRoot 'backups')
        ToolkitVenv = (Join-Path $ToolkitRoot 'venvs\ocr311')
        ToolkitVenvPython = (Join-Path (Join-Path $ToolkitRoot 'venvs\ocr311') 'Scripts\python.exe')
        ToolkitTorchLib = (Join-Path (Join-Path (Join-Path $ToolkitRoot 'venvs\ocr311') 'Lib\site-packages\torch') 'lib')
        ToolkitOcrHealthPath = (Join-Path (Join-Path $ToolkitRoot 'config') 'ocr-health.json')
        DocumentsRoot = $documentsRoot
        PowerShellRoot = $powerShellRoot
        PowerShellScriptsRoot = (Join-Path $powerShellRoot 'Scripts')
        SharedProfileDestination = (Join-Path $powerShellRoot 'profile.shared.ps1')
        ToolkitGuidePath = (Join-Path (Join-Path $ToolkitRoot 'docs') 'Codex-OCR-Toolkit.md')
        ToolkitNetworkGuidePath = (Join-Path (Join-Path $ToolkitRoot 'docs') 'Codex-Network-Toolkit.md')
        ToolkitShadowsocksGuidePath = (Join-Path (Join-Path $ToolkitRoot 'docs') 'Codex-Shadowsocks-Toolkit.md')
        ToolkitWebAuthGuidePath = (Join-Path (Join-Path $ToolkitRoot 'docs') 'Codex-Web-Auth-Toolkit.md')
        ToolkitShadowsocksActiveSecretPath = (Join-Path (Join-Path (Join-Path $ToolkitRoot 'config') 'private') 'shadowsocks.active.json')
        ToolkitBrowserExtensionStarterPath = (Join-Path (Join-Path $ToolkitRoot 'examples') 'browser-extension-starter')
        StarshipConfigDestination = (Join-Path (Join-Path $ToolkitRoot 'config') 'starship.toml')
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-PreferredInstallScope {
    param(
        [string]$InstallScope = 'Auto'
    )

    switch ($InstallScope.ToLowerInvariant()) {
        'user' { return 'user' }
        'machine' {
            if (-not (Test-IsAdministrator)) {
                Write-Warning 'Machine scope requested without elevation. Falling back to user scope.'
                return 'user'
            }

            return 'machine'
        }
        default {
            if (Test-IsAdministrator) { return 'machine' }
            return 'user'
        }
    }
}

function Test-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne (Find-CommandPath -Name $Name)
}

function Find-CommandPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        if (-not [string]::IsNullOrWhiteSpace($command.Path)) {
            return $command.Path
        }

        if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
            return $command.Source
        }

        return $command.Name
    }

    $linkRoots = @(
        (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Microsoft\WinGet\Links')
    )

    $candidateNames = New-Object System.Collections.Generic.List[string]
    [void]$candidateNames.Add($Name)
    foreach ($extension in @('.exe', '.cmd', '.bat', '.ps1')) {
        if (-not $Name.EndsWith($extension, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$candidateNames.Add($Name + $extension)
        }
    }

    foreach ($root in $linkRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($candidateName in $candidateNames) {
            $candidatePath = Join-Path $root $candidateName
            if (Test-Path -LiteralPath $candidatePath) {
                return $candidatePath
            }
        }
    }

    return $null
}

function Get-ToolkitPythonImportState {
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    if (-not (Test-Path -LiteralPath $Context.ToolkitVenvPython)) {
        return @{
            Installed = $false
            Detail = 'OCR venv missing'
        }
    }

    $torchLib = $Context.ToolkitTorchLib.Replace("'", "''")
    $pythonCode = @"
import importlib
import os
torch_lib = r'$torchLib'
if os.path.isdir(torch_lib):
    os.environ['PATH'] = torch_lib + os.pathsep + os.environ.get('PATH', '')
importlib.import_module('$ModuleName')
"@

    & $Context.ToolkitVenvPython -c $pythonCode 2>$null
    return @{
        Installed = ($LASTEXITCODE -eq 0)
        Detail = $ModuleName
    }
}

function Test-ToolkitOcrHealthy {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    return (Test-ToolkitOcrHealthyQuick -Context $Context)
}

function Test-ToolkitOcrHealthyQuick {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    if (-not (Test-Path -LiteralPath $Context.ToolkitVenvPython)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Context.ToolkitGuidePath)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Context.ToolkitOcrHealthPath)) {
        return $false
    }

    try {
        $health = Get-Content -LiteralPath $Context.ToolkitOcrHealthPath -Raw | ConvertFrom-Json
        return ($health.Status -eq 'Healthy')
    } catch {
        return $false
    }
}

function Test-ToolkitOcrHealthyDeep {
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    if (-not (Test-Path -LiteralPath $Context.ToolkitVenvPython)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Context.ToolkitGuidePath)) {
        return $false
    }

    foreach ($module in $script:Manifest.PythonModules) {
        $state = Get-ToolkitPythonImportState -Context $Context -ModuleName $module.ImportName
        if (-not $state.Installed) {
            return $false
        }
    }

    return $true
}

function Get-ToolkitInventoryCommandNames {
    $commandNames = New-Object System.Collections.Generic.List[string]

    foreach ($package in @($script:Manifest.WingetPackages + $script:Manifest.OptionalWingetPackages)) {
        foreach ($commandName in $package.Commands) {
            if (-not [string]::IsNullOrWhiteSpace($commandName)) {
                [void]$commandNames.Add($commandName)
            }
        }
    }

    foreach ($name in @(
        'codehint', 'whichall', 'refresh-path', 'mkcd', 'll', 'la', 'lt', 'z', 'lg', 'j', 'bench',
        'json', 'yaml', 'grepcode', 'proxy-profile-set', 'proxy-profile-show', 'proxy-profile-clear',
        'remote-client-init', 'remote-server-bundle', 'remote-health', 'ss-source-show', 'ss-secret-discover',
        'ss-secret-import', 'ss-secret-clear', 'ss-profile-new', 'ss-client-fetch', 'ss-client-open', 'ss-client-info', 'ss-client-sync',
        'ss-server-bundle', 'ocr-smart', 'pdf-smart', 'translate-smart', 'doc-pipeline',
        'doc-scan', 'doc-batch', 'doc-config', 'doc-help', 'ocr-models', 'auth-browser', 'auth-links',
        'auth-spec', 'auth-save', 'auth-html', 'auth-batch', 'auth-dump', 'auth-chatgpt-browser', 'auth-chatgpt-dump',
        'auth-chatgpt-export', 'auth-chatgpt-study-dump', 'auth-chatgpt-list', 'auth-chatgpt-open',
        'auth-chatgpt-save', 'auth-chatgpt-ask', 'auth-chatgpt-delete', 'auth-extension-install', 'auth-extension-list',
        'auth-extension-enable', 'auth-extension-disable', 'auth-extension-open', 'auth-extension-click',
        'auth-extension-remove', 'auth-help', 'easyocr-read',
        'paddleocr-read', 'donut-ocr', 'llava', 'nougat', 'ocrmypdf'
    )) {
        [void]$commandNames.Add($name)
    }

    return @($commandNames | Select-Object -Unique)
}

function Find-Python311 {
    $candidates = @(
        (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\Python\Python311\python.exe'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Python311\python.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    if (Test-CommandAvailable -Name 'py') {
        try {
            $result = & py -3.11 -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($result)) {
                return $result.Trim()
            }
        } catch {
        }
    }

    return $null
}

function Find-ToolkitAutomationPython {
    $python311 = Find-Python311
    if (-not [string]::IsNullOrWhiteSpace($python311)) {
        return $python311
    }

    $python = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $python) {
        if (-not [string]::IsNullOrWhiteSpace($python.Source)) {
            return $python.Source
        }

        if (-not [string]::IsNullOrWhiteSpace($python.Path)) {
            return $python.Path
        }

        return 'python'
    }

    return $null
}

function Get-GlobalPythonImportState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,

        [string]$PythonPath
    )

    if ([string]::IsNullOrWhiteSpace($PythonPath)) {
        $PythonPath = Find-ToolkitAutomationPython
    }

    if ([string]::IsNullOrWhiteSpace($PythonPath)) {
        return @{
            Installed = $false
            Detail = 'No suitable global Python interpreter was found'
        }
    }

    & $PythonPath -c "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('$ModuleName') else 1)" 2>$null
    return @{
        Installed = ($LASTEXITCODE -eq 0)
        Detail = if ($LASTEXITCODE -eq 0) {
            $PythonPath
        } else {
            "Missing import on $PythonPath"
        }
    }
}

function Get-PackageState {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Package
    )

    if ($Package.Id -eq 'Python.Python.3.11') {
        $python311 = Find-Python311
        return @{
            Installed = ($null -ne $python311)
            Detail = if ($python311) { $python311 } else { 'Python 3.11 executable not found' }
        }
    }

    if ($Package.Id -eq 'Microsoft.PowerToys') {
        $settingsPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Microsoft\PowerToys\AdvancedPaste\settings.json'
        return @{
            Installed = (Test-Path -LiteralPath $settingsPath)
            Detail = $settingsPath
        }
    }

    if (-not $Package.ContainsKey('Commands') -or $Package.Commands.Count -eq 0) {
        return @{
            Installed = $false
            Detail = 'No command-based detection configured'
        }
    }

    $resolvedCommands = @{}
    foreach ($commandName in $Package.Commands) {
        $resolvedCommands[$commandName] = Find-CommandPath -Name $commandName
    }

    $missing = @($resolvedCommands.GetEnumerator() | Where-Object { [string]::IsNullOrWhiteSpace($_.Value) } | ForEach-Object { $_.Key })
    if ($missing.Count -gt 0 -and $Package.ContainsKey('Id') -and (Find-CommandPath -Name 'winget')) {
        $wingetList = & winget list --exact --id $Package.Id --source winget 2>$null
        if ($LASTEXITCODE -eq 0 -and ($wingetList | Out-String) -match [regex]::Escape($Package.Id)) {
            return @{
                Installed = $true
                Detail = "winget:$($Package.Id)"
            }
        }
    }

    return @{
        Installed = ($missing.Count -eq 0)
        Detail = if ($missing.Count -eq 0) {
            [string]::Join(', ', @($resolvedCommands.Values))
        } else {
            'Missing: ' + [string]::Join(', ', $missing)
        }
    }
}

function Get-PowerShellModuleState {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Module
    )

    $installedModule = Get-Module -ListAvailable -Name $Module.Name -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -eq $installedModule) {
        $documentsRoot = Get-DocumentsRoot
        $moduleRoots = @(
            (Join-Path $documentsRoot 'WindowsPowerShell\Modules'),
            (Join-Path $documentsRoot 'PowerShell\Modules')
        )

        foreach ($moduleRoot in $moduleRoots) {
            $moduleBase = Join-Path $moduleRoot $Module.Name
            if (-not (Test-Path -LiteralPath $moduleBase)) {
                continue
            }

            $versionDirectory = Get-ChildItem -LiteralPath $moduleBase -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                Select-Object -First 1

            return @{
                Installed = $true
                Detail = if ($null -ne $versionDirectory) {
                    '{0} {1}' -f $Module.Name, $versionDirectory.Name
                } else {
                    $moduleBase
                }
            }
        }
    }

    return @{
        Installed = ($null -ne $installedModule)
        Detail = if ($null -ne $installedModule) {
            '{0} {1}' -f $installedModule.Name, $installedModule.Version
        } else {
            'Not installed'
        }
    }
}

function Get-OllamaModelInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Model
    )

    if (-not (Test-CommandAvailable -Name 'ollama')) {
        return $false
    }

    $listOutput = & ollama list 2>$null
    return ($LASTEXITCODE -eq 0 -and $listOutput -match ("(^|\s){0}:latest(\s|$)" -f [regex]::Escape($Model)))
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ''
    Write-Host "== $Message ==" -ForegroundColor Cyan
}

function Write-Note {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host $Message -ForegroundColor DarkGray
}
