[CmdletBinding()]
param(
    [string]$ToolkitRoot,
    [switch]$IncludeProfileIntegration,
    [switch]$DeepValidation
)

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'common.ps1')

$context = Get-ToolkitContext -ToolkitRoot $ToolkitRoot

function Get-Audit {
    $audit = New-Object System.Collections.Generic.List[object]

    foreach ($package in $script:Manifest.WingetPackages) {
        $state = Get-PackageState -Package $package
        [void]$audit.Add([pscustomobject]@{
            Component = $package.DisplayName
            Category = $package.Category
            Status = if ($state.Installed) { 'Installed' } else { 'Missing' }
            Detail = $state.Detail
        })
    }

    foreach ($package in $script:Manifest.OptionalWingetPackages) {
        $state = Get-PackageState -Package $package
        [void]$audit.Add([pscustomobject]@{
            Component = "Optional tool: $($package.DisplayName)"
            Category = $package.Category
            Status = if ($state.Installed) { 'Installed' } else { 'Missing' }
            Detail = $state.Detail
        })
    }

    foreach ($module in $script:Manifest.PowerShellModules) {
        $state = Get-PowerShellModuleState -Module $module
        [void]$audit.Add([pscustomobject]@{
            Component = "PowerShell module: $($module.DisplayName)"
            Category = $module.Category
            Status = if ($state.Installed) { 'Installed' } else { 'Missing' }
            Detail = $state.Detail
        })
    }

    foreach ($download in $script:Manifest.InteractiveOnlyDownloads) {
        $installed = $true
        foreach ($command in $download.Commands) {
            if (-not (Test-CommandAvailable -Name $command)) {
                $installed = $false
            }
        }

        [void]$audit.Add([pscustomobject]@{
            Component = $download.Name
            Category = 'Interactive'
            Status = if ($installed) { 'Installed' } else { 'Missing' }
            Detail = if ($installed) { [string]::Join(', ', $download.Commands) } else { $download.Notes }
        })
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathEntries = if ([string]::IsNullOrWhiteSpace($userPath)) { @() } else { $userPath -split ';' }
    [void]$audit.Add([pscustomobject]@{
        Component = 'Toolkit bin in user PATH'
        Category = 'Toolkit'
        Status = if ($pathEntries -contains $context.ToolkitBin) { 'Installed' } else { 'Missing' }
        Detail = $context.ToolkitBin
    })

    [void]$audit.Add([pscustomobject]@{
        Component = 'Starship config'
        Category = 'Toolkit'
        Status = if (Test-Path -LiteralPath $context.StarshipConfigDestination) { 'Installed' } else { 'Missing' }
        Detail = $context.StarshipConfigDestination
    })

    if ($IncludeProfileIntegration) {
        [void]$audit.Add([pscustomobject]@{
            Component = 'Shared PowerShell profile'
            Category = 'Toolkit'
            Status = if (Test-Path -LiteralPath $context.SharedProfileDestination) { 'Installed' } else { 'Missing' }
            Detail = $context.SharedProfileDestination
        })

        $profileStubs = @(
            (Join-Path $context.DocumentsRoot 'PowerShell\profile.ps1'),
            (Join-Path $context.DocumentsRoot 'PowerShell\Microsoft.PowerShell_profile.ps1'),
            (Join-Path $context.DocumentsRoot 'WindowsPowerShell\profile.ps1'),
            (Join-Path $context.DocumentsRoot 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
        )
        $missingStubs = @($profileStubs | Where-Object { -not (Test-Path -LiteralPath $_) })
        [void]$audit.Add([pscustomobject]@{
            Component = 'PowerShell profile entry points'
            Category = 'Toolkit'
            Status = if ($missingStubs.Count -eq 0) { 'Installed' } else { 'Missing' }
            Detail = if ($missingStubs.Count -eq 0) { 'All entry stubs present' } else { 'Missing: ' + [string]::Join(', ', $missingStubs) }
        })

        $helperProfiles = @(
            (Join-Path $context.PowerShellRoot 'codex.document-tools.ps1'),
            (Join-Path $context.PowerShellRoot 'codex.ocr-translate-tools.ps1'),
            (Join-Path $context.PowerShellRoot 'codex.web-auth-tools.ps1')
        )
        $missingHelperProfiles = @($helperProfiles | Where-Object { -not (Test-Path -LiteralPath $_) })
        [void]$audit.Add([pscustomobject]@{
            Component = 'PowerShell helper profiles'
            Category = 'Toolkit'
            Status = if ($missingHelperProfiles.Count -eq 0) { 'Installed' } else { 'Missing' }
            Detail = if ($missingHelperProfiles.Count -eq 0) { $context.PowerShellRoot } else { 'Missing: ' + [string]::Join(', ', $missingHelperProfiles) }
        })

        [void]$audit.Add([pscustomobject]@{
            Component = 'Web auth helper script'
            Category = 'Toolkit'
            Status = if (Test-Path -LiteralPath (Join-Path $context.PowerShellScriptsRoot 'codex_auth_web.py')) { 'Installed' } else { 'Missing' }
            Detail = (Join-Path $context.PowerShellScriptsRoot 'codex_auth_web.py')
        })
    } else {
        [void]$audit.Add([pscustomobject]@{
            Component = 'PowerShell profile integration'
            Category = 'Optional'
            Status = 'NotManaged'
            Detail = 'Shared profile integration was intentionally skipped.'
        })
    }

    $scripts = @('easyocr_read.py', 'paddleocr_read.py', 'donut_ocr.py', 'ocr_common.ps1', 'ocr_smart.ps1', 'pdf_smart.ps1', 'ocr_models.ps1')
    $missingScripts = @($scripts | Where-Object { -not (Test-Path -LiteralPath (Join-Path $context.ToolkitScripts $_)) })
    [void]$audit.Add([pscustomobject]@{
        Component = 'Toolkit support scripts'
        Category = 'Toolkit'
        Status = if ($missingScripts.Count -eq 0) { 'Installed' } else { 'Missing' }
        Detail = if ($missingScripts.Count -eq 0) { $context.ToolkitScripts } else { 'Missing: ' + [string]::Join(', ', $missingScripts) }
    })

    $wrappers = @('easyocr-read.cmd', 'paddleocr-read.cmd', 'donut-ocr.cmd', 'llava.cmd', 'ocr-smart.cmd', 'pdf-smart.cmd', 'ocr-models.cmd')
    $missingWrappers = @($wrappers | Where-Object { -not (Test-Path -LiteralPath (Join-Path $context.ToolkitBin $_)) })
    [void]$audit.Add([pscustomobject]@{
        Component = 'Toolkit wrapper commands'
        Category = 'Toolkit'
        Status = if ($missingWrappers.Count -eq 0) { 'Installed' } else { 'Missing' }
        Detail = if ($missingWrappers.Count -eq 0) { $context.ToolkitBin } else { 'Missing: ' + [string]::Join(', ', $missingWrappers) }
    })

    $venvExists = Test-Path -LiteralPath $context.ToolkitVenvPython
    [void]$audit.Add([pscustomobject]@{
        Component = 'OCR Python 3.11 venv'
        Category = 'Toolkit'
        Status = if ($venvExists) { 'Installed' } else { 'Missing' }
        Detail = $context.ToolkitVenvPython
    })

    [void]$audit.Add([pscustomobject]@{
        Component = 'OCR toolkit guide'
        Category = 'Toolkit'
        Status = if (Test-Path -LiteralPath $context.ToolkitGuidePath) { 'Installed' } else { 'Missing' }
        Detail = $context.ToolkitGuidePath
    })

    foreach ($module in $script:Manifest.PythonModules) {
        if ($DeepValidation) {
            $state = Get-ToolkitPythonImportState -Context $context -ModuleName $module.ImportName
        } else {
            $state = if ($venvExists) {
                & $context.ToolkitVenvPython -c "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('$($module.ImportName)') else 1)" 2>$null
                @{
                    Installed = ($LASTEXITCODE -eq 0)
                    Detail = $module.ImportName
                }
            } else {
                @{
                    Installed = $false
                    Detail = 'OCR venv missing'
                }
            }
        }

        [void]$audit.Add([pscustomobject]@{
            Component = "Python module: $($module.Package)"
            Category = 'Python'
            Status = if ($state.Installed) { 'Installed' } else { 'Missing' }
            Detail = $state.Detail
        })
    }

    foreach ($model in $script:Manifest.OllamaModels) {
        [void]$audit.Add([pscustomobject]@{
            Component = "Ollama model: $model"
            Category = 'AI'
            Status = if (Get-OllamaModelInstalled -Model $model) { 'Installed' } else { 'Missing' }
            Detail = if (Test-CommandAvailable -Name 'ollama') { 'ollama list' } else { 'Ollama is not installed' }
        })
    }

    return $audit
}

$audit = Get-Audit
Write-Section 'Environment Audit'
$audit | Sort-Object Category, Component | Format-Table -AutoSize

$missing = @($audit | Where-Object { $_.Status -eq 'Missing' })
Write-Host ''
if ($missing.Count -eq 0) {
    Write-Host 'No missing target components were detected.' -ForegroundColor Green
} else {
    Write-Host ("Missing or repair-needed components: {0}" -f $missing.Count) -ForegroundColor Yellow
    $missing | Sort-Object Category, Component | Format-Table -AutoSize
}
