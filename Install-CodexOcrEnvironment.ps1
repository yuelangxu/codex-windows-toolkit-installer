[CmdletBinding()]
param(
    [string]$ToolkitRoot,
    [switch]$IncludeLlavaModel,
    [switch]$SkipLlavaModel,
    [switch]$AutoApprove
)

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'common.ps1')

$context = Get-ToolkitContext -ToolkitRoot $ToolkitRoot

function Invoke-VenvPip {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [string]$IndexUrl
    )

    $commandArguments = New-Object System.Collections.Generic.List[string]
    [void]$commandArguments.Add('-m')
    [void]$commandArguments.Add('pip')
    foreach ($argument in $Arguments) {
        [void]$commandArguments.Add($argument)
    }
    if (-not [string]::IsNullOrWhiteSpace($IndexUrl)) {
        [void]$commandArguments.Add('--index-url')
        [void]$commandArguments.Add($IndexUrl)
    }

    & $context.ToolkitVenvPython @commandArguments
    if ($LASTEXITCODE -ne 0) {
        throw "pip failed for arguments: $([string]::Join(' ', $Arguments))"
    }
}

function Test-VenvImport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Module
    )

    $torchLib = $context.ToolkitTorchLib
    $pythonSnippet = @"
import importlib
import os
torch_lib = r'$torchLib'
if os.path.isdir(torch_lib):
    os.environ['PATH'] = torch_lib + os.pathsep + os.environ.get('PATH', '')
importlib.import_module('$Module')
"@

    & $context.ToolkitVenvPython -c $pythonSnippet 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Write-OcrHealthMarker {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Healthy,

        [string[]]$Modules = @()
    )

    Ensure-Directory -Path $context.ToolkitConfig
    $payload = [pscustomobject]@{
        Status = if ($Healthy) { 'Healthy' } else { 'Unhealthy' }
        UpdatedAt = (Get-Date).ToString('o')
        Modules = $Modules
    } | ConvertTo-Json -Depth 5

    Set-Content -LiteralPath $context.ToolkitOcrHealthPath -Value $payload -Encoding UTF8
}

function Patch-NougatCompatibility {
    $rasterizePath = Join-Path $context.ToolkitVenv 'Lib\site-packages\nougat\dataset\rasterize.py'
    $modelPath = Join-Path $context.ToolkitVenv 'Lib\site-packages\nougat\model.py'

    if (Test-Path -LiteralPath $rasterizePath) {
        $content = Get-Content -LiteralPath $rasterizePath -Raw
        if ($content -notmatch 'hasattr\(pdf, "render"\)') {
            $content = $content.Replace(@"
        renderer = pdf.render(
            pypdfium2.PdfBitmap.to_pil,
            page_indices=pages,
            scale=dpi / 72,
        )
"@, @"
        if hasattr(pdf, "render"):
            renderer = pdf.render(
                pypdfium2.PdfBitmap.to_pil,
                page_indices=pages,
                scale=dpi / 72,
            )
        else:
            renderer = []
            for page_index in pages:
                page = pdf[page_index]
                bitmap = page.render(scale=dpi / 72)
                renderer.append(bitmap.to_pil())
"@)
            Set-Content -LiteralPath $rasterizePath -Value $content -Encoding UTF8
        }
    }

    if (Test-Path -LiteralPath $modelPath) {
        $content = Get-Content -LiteralPath $modelPath -Raw
        if ($content -notmatch 'cache_position=None') {
            $content = $content.Replace(@"
    def prepare_inputs_for_inference(
        self,
        input_ids: torch.Tensor,
        encoder_outputs: torch.Tensor,
        past=None,
        past_key_values=None,
        use_cache: bool = None,
        attention_mask: torch.Tensor = None,
    ):
"@, @"
    def prepare_inputs_for_inference(
        self,
        input_ids: torch.Tensor,
        encoder_outputs: torch.Tensor,
        past=None,
        past_key_values=None,
        use_cache: bool = None,
        attention_mask: torch.Tensor = None,
        cache_position=None,
        **kwargs,
    ):
"@)
            Set-Content -LiteralPath $modelPath -Value $content -Encoding UTF8
        }
    }
}

function Get-GhostscriptInstallerUrl {
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/ArtifexSoftware/ghostpdl-downloads/releases/latest'
        $asset = @($release.assets | Where-Object { $_.name -match '^gs\d+w64\.exe$' } | Select-Object -First 1)
        if ($asset.Count -gt 0) {
            return $asset[0].browser_download_url
        }
    } catch {
        Write-Warning "Unable to resolve the latest Ghostscript installer automatically: $($_.Exception.Message)"
    }

    return $null
}

function Add-GhostscriptBinToCurrentSession {
    $gsRoot = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'gs'
    if (-not (Test-Path -LiteralPath $gsRoot)) {
        return
    }

    $candidate = Get-ChildItem -LiteralPath $gsRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -eq $candidate) {
        return
    }

    $binPath = Join-Path $candidate.FullName 'bin'
    if (-not (Test-Path -LiteralPath $binPath)) {
        return
    }

    $entries = if ([string]::IsNullOrWhiteSpace($env:Path)) { @() } else { $env:Path -split ';' }
    if ($entries -notcontains $binPath) {
        $env:Path = "$binPath;$env:Path"
    }
}

function Ensure-Ghostscript {
    if (Test-CommandAvailable -Name 'gswin64c') {
        return
    }

    Add-GhostscriptBinToCurrentSession
    if (Test-CommandAvailable -Name 'gswin64c') {
        return
    }

    Write-Section 'Ghostscript'
    Write-Note 'Ghostscript is required for ocrmypdf and some PDF repair flows.'
    Write-Note 'The current official Windows installer still needs an interactive step.'

    $shouldLaunch = $AutoApprove.IsPresent
    if (-not $shouldLaunch) {
        $answer = Read-Host 'Ghostscript is missing. Launch the official installer now? [Y/N]'
        $shouldLaunch = $answer -match '^(y|yes)$'
    }

    if (-not $shouldLaunch) {
        Write-Warning 'Ghostscript remains missing. PDF conversion and ocrmypdf may fail until you install it.'
        return
    }

    $downloadUrl = Get-GhostscriptInstallerUrl
    if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
        Write-Warning 'Could not resolve a Ghostscript download URL automatically. Open the official download page and install it manually.'
        Start-Process 'https://ghostscript.com/releases/gsdnld.html'
        return
    }

    $installerPath = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetFileName($downloadUrl))
    if (-not (Test-Path -LiteralPath $installerPath)) {
        Write-Note "Downloading Ghostscript installer to $installerPath"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
    }

    Write-Note 'Launching Ghostscript installer. Complete the installer, then return to this window.'
    Start-Process -FilePath $installerPath -Wait
    Add-GhostscriptBinToCurrentSession

    if (-not (Test-CommandAvailable -Name 'gswin64c')) {
        Write-Warning 'Ghostscript was launched, but gswin64c is still not visible in this session. Open a new PowerShell after install if needed.'
    }
}

function Ensure-LlavaModel {
    if (-not (Test-CommandAvailable -Name 'ollama')) {
        Write-Warning 'Ollama is not available, so the llava model cannot be pulled yet.'
        return
    }

    if (Get-OllamaModelInstalled -Model 'llava') {
        Write-Note 'The llava model is already present.'
        return
    }

    if ($SkipLlavaModel) {
        Write-Note 'Skipping llava model download because -SkipLlavaModel was supplied.'
        return
    }

    $shouldPull = $IncludeLlavaModel.IsPresent
    if (-not $shouldPull) {
        if ($AutoApprove) {
            Write-Note 'Skipping llava model download by default in unattended mode. Rerun with -IncludeLlavaModel to pull it.'
            return
        }

        $answer = Read-Host 'Pull the llava model now? This download is roughly 4.7 GB. [Y/N]'
        $shouldPull = $answer -match '^(y|yes)$'
    }

    if (-not $shouldPull) {
        Write-Note 'Skipping llava model download for now.'
        return
    }

    Write-Section 'Pulling Ollama model llava'
    & ollama pull llava
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to pull the llava model with ollama.'
    }
}

Write-Section 'Creating OCR Python 3.11 environment'
Ensure-Directory -Path $context.ToolkitDocs
Ensure-Directory -Path (Split-Path -Parent $context.ToolkitVenv)

Ensure-Ghostscript

$python311 = Find-Python311
if ([string]::IsNullOrWhiteSpace($python311)) {
    throw 'Python 3.11 was not found. Install Python 3.11 first, then rerun the toolkit installer.'
}

Write-Note "Using Python 3.11 at $python311"
if (-not (Test-Path -LiteralPath $context.ToolkitVenvPython)) {
    Write-Note "Creating isolated OCR environment at $($context.ToolkitVenv)"
    & $python311 -m venv $context.ToolkitVenv
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to create the OCR Python virtual environment.'
    }
}

foreach ($step in @(
    @{ Arguments = @('install', '--upgrade', 'pip', 'setuptools', 'wheel') }
    @{ Arguments = @('install', '--force-reinstall', 'numpy==1.26.4', 'protobuf==3.20.2', 'fsspec==2026.2.0') }
    @{ Arguments = @('install', '--force-reinstall', 'opencv-python==4.10.0.84', 'opencv-contrib-python==4.10.0.84', 'opencv-python-headless==4.10.0.84') }
    @{ Arguments = @('install', 'paddlepaddle==2.6.2', 'paddleocr==2.7.3') }
    @{ Arguments = @('install', '--force-reinstall', 'torch==2.4.1', 'torchvision==0.19.1'); IndexUrl = 'https://download.pytorch.org/whl/cpu' }
    @{ Arguments = @('install', '--force-reinstall', '--no-deps', 'numpy==1.26.4', 'fsspec==2026.2.0') }
    @{ Arguments = @('install', 'transformers==4.38.2', 'tokenizers==0.15.2', 'sentencepiece', 'ocrmypdf', 'easyocr') }
    @{ Arguments = @('install', '--force-reinstall', '--no-deps', 'numpy==1.26.4', 'fsspec==2026.2.0', 'albumentations==1.3.1') }
    @{ Arguments = @('install', 'qudida', 'timm==0.5.4', 'orjson', 'lightning', 'nltk', 'python-Levenshtein', 'sconf', 'pypdf>=3.1.0', 'datasets>=2.21.0') }
    @{ Arguments = @('install', '--force-reinstall', '--no-deps', 'numpy==1.26.4', 'fsspec==2026.2.0') }
    @{ Arguments = @('install', '--no-deps', 'nougat-ocr') }
)) {
    $arguments = [string[]]$step.Arguments
    Write-Note ("pip {0}" -f ([string]::Join(' ', $arguments)))
    Invoke-VenvPip -Arguments $arguments -IndexUrl $step.IndexUrl
}

Patch-NougatCompatibility

$expectedImports = @('torch', 'easyocr', 'paddleocr', 'ocrmypdf', 'transformers', 'nougat')
$failedImports = @($expectedImports | Where-Object { -not (Test-VenvImport -Module $_) })
if ($failedImports.Count -gt 0) {
    Write-OcrHealthMarker -Healthy $false -Modules $expectedImports
    throw "OCR environment validation failed for: $([string]::Join(', ', $failedImports))"
}

Write-OcrHealthMarker -Healthy $true -Modules $expectedImports

$ocrModelsScript = Join-Path $context.ToolkitScripts 'ocr_models.ps1'
if (Test-Path -LiteralPath $ocrModelsScript) {
    Write-Note "Writing OCR toolkit guide to $($context.ToolkitGuidePath)"
    & powershell -NoLogo -ExecutionPolicy Bypass -File $ocrModelsScript -Markdown -OutFile $context.ToolkitGuidePath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to generate the OCR toolkit guide.'
    }
}

Ensure-LlavaModel

Write-Host 'OCR environment is ready.' -ForegroundColor Green
