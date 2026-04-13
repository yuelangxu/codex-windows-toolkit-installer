[CmdletBinding()]
param(
    [string]$ToolkitRoot,
    [switch]$SummaryOnly,
    [switch]$Markdown,
    [string]$OutFile
)

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'common.ps1')

$context = Get-ToolkitContext -ToolkitRoot $ToolkitRoot

if (Test-Path -LiteralPath $context.SharedProfileDestination) {
    . $context.SharedProfileDestination
}

$groups = @(
    @{
        Title = 'Toolkit Helpers'
        Names = @('codehint', 'toolkit-inventory', 'whichall', 'refresh-path', 'mkcd', 'll', 'la', 'lt', 'z', 'lg', 'j', 'bench', 'json', 'yaml', 'grepcode')
    }
    @{
        Title = 'Core CLI'
        Names = @('git', 'gh', 'rg', 'fd', 'fzf', 'jq', 'yq', 'uv', 'pnpm', 'bat', 'delta', 'eza', 'zoxide', 'starship', 'lazygit', 'just', 'hyperfine', '7z', 'sd', 'xh', 'mise', 'dust', 'procs')
    }
    @{
        Title = 'Docs / OCR'
        Names = @('ocr-smart', 'pdf-smart', 'translate-smart', 'doc-pipeline', 'doc-scan', 'doc-batch', 'doc-config', 'doc-help', 'ocr-models', 'easyocr-read', 'paddleocr-read', 'donut-ocr', 'nougat', 'ocrmypdf', 'pdftotext', 'pdftoppm', 'mutool', 'tesseract')
    }
    @{
        Title = 'Web Auth'
        Names = @('auth-browser', 'auth-links', 'auth-spec', 'auth-save', 'auth-html', 'auth-batch', 'auth-dump', 'auth-chatgpt-dump', 'auth-chatgpt-export', 'auth-chatgpt-study-dump', 'auth-chatgpt-list', 'auth-chatgpt-open', 'auth-chatgpt-save', 'auth-chatgpt-ask', 'auth-chatgpt-delete', 'auth-help')
    }
)

$inventory = foreach ($group in $groups) {
    foreach ($name in $group.Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        [pscustomobject]@{
            Group = $group.Title
            Name = $name
            Status = if ($null -eq $command) { 'Missing' } else { 'Available' }
            CommandType = if ($null -eq $command) { '' } else { $command.CommandType }
            Target = if ($null -eq $command) { '' } else {
                if ($command.PSObject.Properties['Path'] -and $command.Path) { $command.Path }
                elseif ($command.PSObject.Properties['Source'] -and $command.Source) { $command.Source }
                elseif ($command.PSObject.Properties['Definition'] -and $command.Definition) { $command.Definition }
                else { $command.Name }
            }
        }
    }
}

if ($SummaryOnly) {
    $inventory |
        Group-Object Group |
        ForEach-Object {
            [pscustomobject]@{
                Group = $_.Name
                Available = @($_.Group | Where-Object Status -eq 'Available').Count
                Missing = @($_.Group | Where-Object Status -eq 'Missing').Count
            }
        } | Format-Table -AutoSize
    return
}

if ($Markdown) {
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("# Codex Toolkit Inventory")
    [void]$lines.Add('')
    foreach ($group in $groups) {
        [void]$lines.Add("## $($group.Title)")
        [void]$lines.Add('')
        [void]$lines.Add('| Name | Status | Type | Target |')
        [void]$lines.Add('|---|---|---|---|')
        foreach ($row in @($inventory | Where-Object Group -eq $group.Title)) {
            [void]$lines.Add("| $($row.Name) | $($row.Status) | $($row.CommandType) | $($row.Target.Replace('|', '\|')) |")
        }
        [void]$lines.Add('')
    }

    $content = [string]::Join([Environment]::NewLine, $lines.ToArray())
    if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
        Set-Content -LiteralPath $OutFile -Value $content -Encoding UTF8
        Write-Host $OutFile
        return
    }

    $content
    return
}

foreach ($group in $groups) {
    Write-Host ''
    Write-Host ("[{0}]" -f $group.Title) -ForegroundColor Yellow
    $inventory | Where-Object Group -eq $group.Title | Format-Table Name, Status, CommandType, Target -AutoSize
}
