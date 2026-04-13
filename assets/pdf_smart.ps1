param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [ValidateSet('auto', 'searchable', 'academic', 'understand')]
    [string]$Mode = 'auto',

    [string]$OutPath,

    [string]$Question,

    [switch]$Cpu
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ocr_common.ps1')

$result = Invoke-CodexPdfSmart -InputPath $InputPath -Mode $Mode -OutPath $OutPath -Question $Question -Cpu:$Cpu
if ($null -ne $result) {
    Write-Output $result
}
