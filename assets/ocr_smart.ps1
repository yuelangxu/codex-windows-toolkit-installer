param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [ValidateSet('auto', 'document', 'screenshot', 'handwriting', 'understand')]
    [string]$Mode = 'auto',

    [string]$Lang = 'en',

    [string]$Question,

    [switch]$Cpu
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ocr_common.ps1')

$resolvedInputPath = Resolve-CodexLiteralPath -Path $InputPath
$extension = [IO.Path]::GetExtension($resolvedInputPath).ToLowerInvariant()

if ($extension -eq '.pdf') {
    $pdfMode = if ($Mode -eq 'document' -or $Mode -eq 'screenshot' -or $Mode -eq 'handwriting') { 'auto' } else { $Mode }
    $result = Invoke-CodexPdfSmart -InputPath $resolvedInputPath -Mode $pdfMode -Question $Question -Cpu:$Cpu
    if ($null -ne $result) {
        Write-Output $result
    }
    exit 0
}

$engine = Select-CodexFirstAvailableCommand -Candidates (Get-CodexImageEnginePreference -InputPath $resolvedInputPath -Mode $Mode -Lang $Lang -Question $Question)
Write-Host "[ocr-smart] engine=$engine | mode=$Mode | lang=$Lang" -ForegroundColor DarkGray
Invoke-CodexImageEngine -Engine $engine -InputPath $resolvedInputPath -Lang $Lang -Question $Question -Cpu:$Cpu
