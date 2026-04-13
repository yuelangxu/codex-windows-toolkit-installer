function Set-CodexHelperAlias {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AliasName,

        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Remove-Item -Path "Alias:$AliasName" -Force -ErrorAction SilentlyContinue
    Set-Alias -Name $AliasName -Value $TargetName -Scope Global -Option AllScope -Force
}

function Backup-CodexArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$LiteralPath,

        [string]$BackupRoot
    )

    $existing = @($LiteralPath | Where-Object { Test-Path -LiteralPath $_ })
    if ($existing.Count -eq 0) {
        Write-Host "No existing paths to back up." -ForegroundColor Yellow
        return
    }

    if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
        $first = Get-Item -LiteralPath $existing[0] -ErrorAction Stop
        $baseDir = if ($first.PSIsContainer) { $first.Parent.FullName } else { $first.DirectoryName }
        $BackupRoot = Join-Path $baseDir ".codex-backups"
    }

    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $snapshotDir = Join-Path $BackupRoot $stamp
    New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null

    foreach ($path in $existing) {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        $dest = Join-Path $snapshotDir $item.Name
        Copy-Item -LiteralPath $item.FullName -Destination $dest -Recurse -Force
    }

    Get-ChildItem -LiteralPath $snapshotDir | Select-Object Name, Length, LastWriteTime
}

function Split-CodexDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [Parameter(Position = 1)]
        [string]$OutputDir,

        [int]$MaxChars = 14000,

        [string]$HeadingRegex = '^# '
    )

    $inputFile = Get-Item -LiteralPath $InputPath -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Join-Path $inputFile.DirectoryName ($inputFile.BaseName + "_chunks")
    }

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $text = Get-Content -LiteralPath $inputFile.FullName -Raw -Encoding UTF8
    $lines = $text -split "`r?`n"

    $sections = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder

    foreach ($line in $lines) {
        if ($line -match $HeadingRegex -and $current.Length -gt 0) {
            $sections.Add($current.ToString().TrimEnd())
            $current.Clear() | Out-Null
        }
        [void]$current.AppendLine($line)
    }

    if ($current.Length -gt 0) {
        $sections.Add($current.ToString().TrimEnd())
    }

    $chunks = New-Object System.Collections.Generic.List[string]
    $buffer = New-Object System.Text.StringBuilder

    foreach ($section in $sections) {
        if (($buffer.Length + $section.Length + 2) -gt $MaxChars -and $buffer.Length -gt 0) {
            $chunks.Add($buffer.ToString().TrimEnd())
            $buffer.Clear() | Out-Null
        }

        if ($section.Length -gt $MaxChars) {
            $sectionLines = $section -split "`r?`n"
            $local = New-Object System.Text.StringBuilder
            foreach ($sectionLine in $sectionLines) {
                if (($local.Length + $sectionLine.Length + 2) -gt $MaxChars -and $local.Length -gt 0) {
                    $chunks.Add($local.ToString().TrimEnd())
                    $local.Clear() | Out-Null
                }
                [void]$local.AppendLine($sectionLine)
            }
            if ($local.Length -gt 0) {
                $chunks.Add($local.ToString().TrimEnd())
            }
            continue
        }

        if ($buffer.Length -gt 0) {
            [void]$buffer.AppendLine()
        }
        [void]$buffer.Append($section)
    }

    if ($buffer.Length -gt 0) {
        $chunks.Add($buffer.ToString().TrimEnd())
    }

    $index = 1
    foreach ($chunk in $chunks) {
        $name = "{0:D2}_{1}.md" -f $index, $inputFile.BaseName
        $path = Join-Path $OutputDir $name
        Set-Content -LiteralPath $path -Value $chunk -Encoding UTF8
        $index++
    }

    Get-ChildItem -LiteralPath $OutputDir | Select-Object Name, Length
}

function Find-CodexMathMarkup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Input file not found: $InputPath"
    }

    $patterns = @(
        @{
            Name = "Inline code span contains LaTeX-like content"
            Regex = '`[^`]*\\[A-Za-z]+[^`]*`'
        },
        @{
            Name = "Line contains LaTeX command outside obvious math delimiters"
            Regex = '\\(hat|frac|tilde|Delta|mu|ell|nabla|mathbf|mathrm|psi|phi|sum|int|left|right)\b'
        }
    )

    $lineNumber = 0
    $lines = Get-Content -LiteralPath $InputPath -Encoding UTF8

    $displayFenceCount = @($lines | Where-Object { $_.Trim() -eq '$$' }).Count
    $results = New-Object System.Collections.Generic.List[object]

    if ($displayFenceCount % 2 -ne 0) {
        [void]$results.Add([pscustomobject]@{
            LineNumber = 0
            Issue = "Odd number of standalone $$ display-math fences"
            Text = "File-level warning: Math block fences may be unbalanced."
        })
    }

    foreach ($line in $lines) {
        $lineNumber++
        if ($line.Trim().StartsWith('```')) {
            continue
        }

        foreach ($pattern in $patterns) {
            if ($line -notmatch $pattern.Regex) {
                continue
            }
            if ($pattern.Name -eq "Line contains LaTeX command outside obvious math delimiters" -and (
                $line -match '\$' -or $line -match '\\\(' -or $line -match '\\\['
            )) {
                continue
            }
            [void]$results.Add([pscustomobject]@{
                LineNumber = $lineNumber
                Issue = $pattern.Name
                Text = $line.Trim()
            })
        }

        $dollarPairsRemoved = [regex]::Replace($line, '\$\$', '')
        $singleDollarCount = ([regex]::Matches($dollarPairsRemoved, '(?<!\\)\$')).Count
        if ($singleDollarCount % 2 -ne 0) {
            [void]$results.Add([pscustomobject]@{
                LineNumber = $lineNumber
                Issue = "Odd number of unescaped inline-dollar delimiters"
                Text = $line.Trim()
            })
        }

        $hasLeft = $line -match '\\left\b'
        $hasRight = $line -match '\\right\b'
        if ($hasLeft -xor $hasRight) {
            [void]$results.Add([pscustomobject]@{
                LineNumber = $lineNumber
                Issue = "Possible unmatched \\left or \\right"
                Text = $line.Trim()
            })
        }
    }

    if ($results.Count -eq 0) {
        Write-Host "No suspicious math-markup lines found." -ForegroundColor Green
        return
    }

    $results
}

function Invoke-CodexPythonBuilder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ScriptPath,

        [string[]]$ExpectedOutputs = @(),

        [string[]]$BackupPaths = @(),

        [string]$BackupRoot,

        [switch]$OpenHtml,

        [string[]]$HtmlPath = @()
    )

    $script = Get-Item -LiteralPath $ScriptPath -ErrorAction Stop

    if ($BackupPaths.Count -gt 0) {
        Backup-CodexArtifact -LiteralPath $BackupPaths -BackupRoot $BackupRoot | Out-Host
    }

    python $script.FullName

    if ($LASTEXITCODE -ne 0) {
        throw "Python builder failed with exit code $LASTEXITCODE"
    }

    $verified = @()
    if ($ExpectedOutputs.Count -gt 0) {
        foreach ($output in $ExpectedOutputs) {
            if (-not (Test-Path -LiteralPath $output)) {
                throw "Expected output missing: $output"
            }
            $verified += $output
        }

        Get-Item -LiteralPath $ExpectedOutputs | Select-Object Name, Length, LastWriteTime | Out-Host
    }

    if ($OpenHtml) {
        $htmlTargets = @()
        if ($HtmlPath.Count -gt 0) {
            $htmlTargets = @($HtmlPath | Where-Object { Test-Path -LiteralPath $_ })
        } elseif ($verified.Count -gt 0) {
            $htmlTargets = @($verified | Where-Object { $_ -match '\.html?$' -and (Test-Path -LiteralPath $_) })
        }

        foreach ($html in $htmlTargets) {
            Invoke-Item -LiteralPath $html
        }
    }

    Write-Host "Builder completed successfully." -ForegroundColor Green
}

function Invoke-CodexBuildCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ScriptPath,

        [string]$SourcePath,

        [string[]]$ExpectedOutputs = @(),

        [switch]$RunMathLint,

        [switch]$Backup,

        [string]$BackupRoot,

        [switch]$OpenHtml,

        [string[]]$HtmlPath = @()
    )

    if ($RunMathLint -and -not [string]::IsNullOrWhiteSpace($SourcePath)) {
        $lintResults = Find-CodexMathMarkup -InputPath $SourcePath
        if ($lintResults) {
            $lintResults | Format-Table -Wrap -AutoSize | Out-Host
        }
    }

    $backupPaths = @()
    if ($Backup) {
        if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
            $backupPaths += $SourcePath
        }
        if ($ExpectedOutputs.Count -gt 0) {
            $backupPaths += $ExpectedOutputs
        }
    }

    Invoke-CodexPythonBuilder -ScriptPath $ScriptPath `
        -ExpectedOutputs $ExpectedOutputs `
        -BackupPaths $backupPaths `
        -BackupRoot $BackupRoot `
        -OpenHtml:$OpenHtml `
        -HtmlPath $HtmlPath
}

function Remove-CodexArtifacts {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(ParameterSetName = 'Literal', Mandatory = $true)]
        [string[]]$LiteralPath,

        [Parameter(ParameterSetName = 'Pattern', Mandatory = $true)]
        [string]$Pattern,

        [string]$Root = (Get-Location).Path
    )

    $targets = @()

    if ($PSCmdlet.ParameterSetName -eq 'Literal') {
        $targets = $LiteralPath | Where-Object { Test-Path -LiteralPath $_ }
    } else {
        $targets = Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -like $Pattern } | Select-Object -ExpandProperty FullName
    }

    foreach ($target in $targets) {
        if ($PSCmdlet.ShouldProcess($target, 'Remove artifact')) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
}

Set-CodexHelperAlias -AliasName 'split-doc' -TargetName 'Split-CodexDocument'
Set-CodexHelperAlias -AliasName 'mathlint' -TargetName 'Find-CodexMathMarkup'
Set-CodexHelperAlias -AliasName 'pybuild' -TargetName 'Invoke-CodexPythonBuilder'
Set-CodexHelperAlias -AliasName 'build-doc' -TargetName 'Invoke-CodexBuildCycle'
Set-CodexHelperAlias -AliasName 'backup-path' -TargetName 'Backup-CodexArtifact'
Set-CodexHelperAlias -AliasName 'clean-artifacts' -TargetName 'Remove-CodexArtifacts'
