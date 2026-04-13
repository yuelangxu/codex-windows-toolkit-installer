param(
    [switch]$Markdown,

    [switch]$Guide,

    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ocr_common.ps1')

if ($Markdown -or $Guide) {
    $content = Get-CodexOcrReferenceMarkdown
    if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
        $parent = Split-Path -Parent $OutFile
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -LiteralPath $OutFile -Value $content -Encoding UTF8
        Write-Output $OutFile
        exit 0
    }

    Write-Output $content
    exit 0
}

$inventory = Get-CodexOcrInventory | Select-Object Command, Model, CachePath, Size, Notes
$table = $inventory | Format-Table -AutoSize | Out-String -Width 220
Write-Output $table.TrimEnd()
