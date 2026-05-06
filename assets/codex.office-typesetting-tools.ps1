if ((Get-Variable -Name CodexOfficeTypesettingToolsLoaded -Scope Global -ErrorAction SilentlyContinue) -and $global:CodexOfficeTypesettingToolsLoaded) {
    return
}

$global:CodexOfficeTypesettingToolsLoaded = $true
$global:OfficeTypesettingToolsReady = $false

function Resolve-CodexOfficeToolPath {
    [CmdletBinding()]
    param(
        [string[]]$CommandNames = @(),
        [string[]]$CandidatePaths = @()
    )

    foreach ($commandName in $CommandNames) {
        if ([string]::IsNullOrWhiteSpace($commandName)) {
            continue
        }

        $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            if ($command.PSObject.Properties['Path'] -and -not [string]::IsNullOrWhiteSpace($command.Path)) {
                return $command.Path
            }

            if ($command.PSObject.Properties['Source'] -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
                return $command.Source
            }

            return $command.Name
        }
    }

    foreach ($candidatePath in $CandidatePaths) {
        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            continue
        }

        $expandedPath = [Environment]::ExpandEnvironmentVariables($candidatePath)
        if (Test-Path -LiteralPath $expandedPath) {
            return $expandedPath
        }
    }

    return $null
}

function New-CodexOfficeToolDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$VariableName,

        [string[]]$CommandNames = @(),

        [string[]]$CandidatePaths = @(),

        [string]$Description,

        [string]$Category = 'OfficeTypesetting'
    )

    return [ordered]@{
        Name = $Name
        VariableName = $VariableName
        CommandNames = $CommandNames
        CandidatePaths = $CandidatePaths
        Description = $Description
        Category = $Category
    }
}

function Get-CodexOfficeToolDefinitions {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = ${env:ProgramFiles(x86)}
    $appData = [Environment]::GetFolderPath('ApplicationData')
    $officeTypesettingRoot = Join-Path $localAppData 'Programs\OfficeTypesettingTools'
    $desktopRoot = [Environment]::GetFolderPath('Desktop')

    return @(
        (New-CodexOfficeToolDefinition -Name 'Typst' -VariableName 'TypstExe' -CommandNames @('typst') -CandidatePaths @(
            (Join-Path $localAppData 'Microsoft\WinGet\Links\typst.exe'),
            (Join-Path $localAppData 'Microsoft\WinGet\Packages\Typst.Typst_Microsoft.Winget.Source_8wekyb3d8bbwe\typst-x86_64-pc-windows-msvc\typst.exe')
        ) -Description 'compile Typst lesson, handout, and exam PDFs')
        (New-CodexOfficeToolDefinition -Name 'Marp' -VariableName 'MarpCmd' -CommandNames @('marp.cmd', 'marp') -CandidatePaths @(
            (Join-Path $appData 'npm\marp.cmd')
        ) -Description 'convert Markdown lessons to HTML, PDF, and PPTX')
        (New-CodexOfficeToolDefinition -Name 'Chromium' -VariableName 'ChromiumExe' -CommandNames @('chrome', 'chromium') -CandidatePaths @(
            (Join-Path $localAppData 'Chromium\Application\chrome.exe'),
            (Join-Path $programFiles 'Chromium\Application\chrome.exe'),
            (Join-Path $programFilesX86 'Chromium\Application\chrome.exe')
        ) -Description 'stable local browser renderer for Marp')
        (New-CodexOfficeToolDefinition -Name 'XeLaTeX' -VariableName 'XeLaTeXExe' -CommandNames @('xelatex') -CandidatePaths @(
            (Join-Path $localAppData 'Programs\MiKTeX\miktex\bin\x64\xelatex.exe'),
            (Join-Path $programFiles 'MiKTeX\miktex\bin\x64\xelatex.exe'),
            'C:\texlive\2026\bin\windows\xelatex.exe'
        ) -Description 'compile Chinese LaTeX documents')
        (New-CodexOfficeToolDefinition -Name 'pdfLaTeX' -VariableName 'PdfLaTeXExe' -CommandNames @('pdflatex') -CandidatePaths @(
            (Join-Path $localAppData 'Programs\MiKTeX\miktex\bin\x64\pdflatex.exe'),
            (Join-Path $programFiles 'MiKTeX\miktex\bin\x64\pdflatex.exe'),
            'C:\texlive\2026\bin\windows\pdflatex.exe'
        ) -Description 'compile LaTeX documents')
        (New-CodexOfficeToolDefinition -Name 'latexmk' -VariableName 'LatexMkExe' -CommandNames @('latexmk') -CandidatePaths @(
            (Join-Path $localAppData 'Programs\MiKTeX\miktex\bin\x64\latexmk.exe'),
            (Join-Path $programFiles 'MiKTeX\miktex\bin\x64\latexmk.exe'),
            'C:\texlive\2026\bin\windows\latexmk.exe'
        ) -Description 'build LaTeX projects with dependency reruns')
        (New-CodexOfficeToolDefinition -Name 'dvisvgm' -VariableName 'DvisvgmExe' -CommandNames @('dvisvgm') -CandidatePaths @(
            (Join-Path $localAppData 'Programs\MiKTeX\miktex\bin\x64\dvisvgm.exe'),
            (Join-Path $programFiles 'MiKTeX\miktex\bin\x64\dvisvgm.exe'),
            'C:\texlive\2026\bin\windows\dvisvgm.exe'
        ) -Description 'convert TeX output to SVG')
        (New-CodexOfficeToolDefinition -Name 'MiKTeX Package Manager' -VariableName 'MiKTeXPackageManagerExe' -CommandNames @('mpm') -CandidatePaths @(
            (Join-Path $localAppData 'Programs\MiKTeX\miktex\bin\x64\mpm.exe'),
            (Join-Path $programFiles 'MiKTeX\miktex\bin\x64\mpm.exe')
        ) -Description 'manage MiKTeX packages')
        (New-CodexOfficeToolDefinition -Name 'Pandoc' -VariableName 'PandocExe' -CommandNames @('pandoc') -CandidatePaths @(
            (Join-Path $programFiles 'Pandoc\pandoc.exe')
        ) -Description 'convert Markdown, DOCX, HTML, PDF-adjacent formats')
        (New-CodexOfficeToolDefinition -Name 'Ghostscript' -VariableName 'GhostscriptExe' -CommandNames @('gswin64c', 'gswin32c') -CandidatePaths @(
            (Join-Path $programFiles 'gs\gs10.07.0\bin\gswin64c.exe'),
            (Join-Path $programFiles 'gs\gs10.06.0\bin\gswin64c.exe')
        ) -Description 'PostScript and PDF backend used by TeX/image tools')
        (New-CodexOfficeToolDefinition -Name 'ImageMagick' -VariableName 'ImageMagickExe' -CommandNames @('magick') -CandidatePaths @(
            (Join-Path $localAppData 'Microsoft\WindowsApps\magick.exe')
        ) -Description 'convert images for worksheets and slides')
        (New-CodexOfficeToolDefinition -Name 'LibreOffice' -VariableName 'LibreOfficeExe' -CommandNames @('soffice') -CandidatePaths @(
            (Join-Path $programFiles 'LibreOffice\program\soffice.exe'),
            (Join-Path $programFilesX86 'LibreOffice\program\soffice.exe')
        ) -Description 'LibreOffice command line and Impress/Writer host')
        (New-CodexOfficeToolDefinition -Name 'LibreOffice unopkg' -VariableName 'LibreOfficeUnopkgExe' -CommandNames @('unopkg') -CandidatePaths @(
            (Join-Path $programFiles 'LibreOffice\program\unopkg.com'),
            (Join-Path $programFiles 'LibreOffice\program\unopkg.exe'),
            (Join-Path $programFilesX86 'LibreOffice\program\unopkg.com'),
            (Join-Path $programFilesX86 'LibreOffice\program\unopkg.exe')
        ) -Description 'install LibreOffice extensions')
        (New-CodexOfficeToolDefinition -Name 'Inkscape' -VariableName 'InkscapeExe' -CommandNames @('inkscape') -CandidatePaths @(
            (Join-Path $programFiles 'Inkscape\bin\inkscape.exe'),
            (Join-Path $programFiles 'Inkscape\inkscape.exe')
        ) -Description 'edit SVG and vector assets')
        (New-CodexOfficeToolDefinition -Name 'draw.io' -VariableName 'DrawIoExe' -CommandNames @('draw.io', 'drawio') -CandidatePaths @(
            (Join-Path $localAppData 'Programs\draw.io\draw.io.exe'),
            (Join-Path $programFiles 'draw.io\draw.io.exe')
        ) -Description 'create diagrams and knowledge maps')
        (New-CodexOfficeToolDefinition -Name 'SumatraPDF' -VariableName 'SumatraPdfExe' -CommandNames @('SumatraPDF') -CandidatePaths @(
            (Join-Path $localAppData 'SumatraPDF\SumatraPDF.exe'),
            (Join-Path $programFiles 'SumatraPDF\SumatraPDF.exe')
        ) -Description 'fast PDF preview')
        (New-CodexOfficeToolDefinition -Name 'Scribus' -VariableName 'ScribusExe' -CommandNames @('scribus') -CandidatePaths @(
            (Join-Path $programFiles 'Scribus 1.6.6\Scribus.exe'),
            (Join-Path $programFiles 'Scribus 1.6.5\Scribus.exe')
        ) -Description 'desktop publishing for print handouts')
        (New-CodexOfficeToolDefinition -Name 'IguanaTex PPAM' -VariableName 'IguanaTexAddIn' -CandidatePaths @(
            (Join-Path $appData 'Microsoft\AddIns\IguanaTex_v1_62_1.ppam'),
            (Join-Path $officeTypesettingRoot 'downloads\IguanaTex_v1_62_1.ppam'),
            (Join-Path $desktopRoot 'OfficeTypesettingTools\downloads\IguanaTex_v1_62_1.ppam')
        ) -Description 'PowerPoint LaTeX add-in package')
        (New-CodexOfficeToolDefinition -Name 'TexMaths OXT' -VariableName 'TexMathsOxt' -CandidatePaths @(
            (Join-Path $officeTypesettingRoot 'downloads\TexMaths-0.52.6.oxt'),
            (Join-Path $desktopRoot 'OfficeTypesettingTools\downloads\TexMaths-0.52.6.oxt')
        ) -Description 'LibreOffice LaTeX equation extension package')
        (New-CodexOfficeToolDefinition -Name 'OfficeTypesettingTools root' -VariableName 'OfficeTypesettingToolsRoot' -CandidatePaths @(
            $officeTypesettingRoot,
            (Join-Path $desktopRoot 'OfficeTypesettingTools')
        ) -Description 'local examples and generated sample decks')
    )
}

function Register-CodexOfficeTypesettingTools {
    [CmdletBinding()]
    param()

    $toolRows = New-Object System.Collections.Generic.List[object]
    $toolMap = [ordered]@{}
    $pathMap = [ordered]@{}

    foreach ($definition in Get-CodexOfficeToolDefinitions) {
        $path = Resolve-CodexOfficeToolPath -CommandNames $definition.CommandNames -CandidatePaths $definition.CandidatePaths
        Set-Variable -Name $definition.VariableName -Value $path -Scope Global -Option AllScope -Force

        $row = [pscustomobject]@{
            Name = $definition.Name
            Variable = '$global:' + $definition.VariableName
            Status = if ([string]::IsNullOrWhiteSpace($path)) { 'Missing' } else { 'Available' }
            Path = if ([string]::IsNullOrWhiteSpace($path)) { '' } else { $path }
            Description = $definition.Description
            Category = $definition.Category
        }

        [void]$toolRows.Add($row)
        $toolMap[$definition.Name] = $row
        $pathMap[$definition.VariableName] = $path
    }

    $global:OfficeTypesettingTools = $toolMap
    $global:OfficeTypesettingToolPaths = $pathMap
    $global:OfficeToolsRoot = $global:OfficeTypesettingToolsRoot
    $global:OfficeTypesettingToolsReady = $true
    $env:CODEX_OFFICE_TYPESETTING_TOOLS = [string]::Join(';', @($toolRows | Where-Object Status -eq 'Available' | ForEach-Object { $_.Name }))

    return $toolRows
}

function Initialize-CodexOfficeTypesettingToolVariables {
    [CmdletBinding()]
    param()

    $toolMap = [ordered]@{}
    $pathMap = [ordered]@{}

    foreach ($definition in Get-CodexOfficeToolDefinitions) {
        $existingVariable = Get-Variable -Name $definition.VariableName -Scope Global -ErrorAction SilentlyContinue
        if ($null -eq $existingVariable) {
            $path = $null
        } else {
            $path = $existingVariable.Value
        }

        if ([string]::IsNullOrWhiteSpace($path)) {
            foreach ($candidatePath in $definition.CandidatePaths) {
                if ([string]::IsNullOrWhiteSpace($candidatePath)) {
                    continue
                }

                $expandedPath = [Environment]::ExpandEnvironmentVariables($candidatePath)
                if (Test-Path -LiteralPath $expandedPath) {
                    $path = $expandedPath
                    break
                }
            }
        }

        Set-Variable -Name $definition.VariableName -Value $path -Scope Global -Option AllScope -Force

        $row = [pscustomobject]@{
            Name = $definition.Name
            Variable = '$global:' + $definition.VariableName
            Status = if ([string]::IsNullOrWhiteSpace($path)) { 'Unknown' } else { 'Available' }
            Path = if ([string]::IsNullOrWhiteSpace($path)) { '' } else { $path }
            Description = $definition.Description
            Category = $definition.Category
        }

        $toolMap[$definition.Name] = $row
        $pathMap[$definition.VariableName] = $path
    }

    $global:OfficeTypesettingTools = $toolMap
    $global:OfficeTypesettingToolPaths = $pathMap
    $global:OfficeToolsRoot = $global:OfficeTypesettingToolsRoot
    $global:OfficeTypesettingToolsReady = $false
    $env:CODEX_OFFICE_TYPESETTING_TOOLS = 'lazy'
}

function Get-CodexOfficeTypesettingTool {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Name = @()
    )

    if (-not $global:OfficeTypesettingToolsReady) {
        Register-CodexOfficeTypesettingTools | Out-Null
    }

    $rows = @($global:OfficeTypesettingTools.Values)
    if ($Name.Count -eq 0) {
        return $rows
    }

    foreach ($query in $Name) {
        $rows | Where-Object {
            $_.Name -like "*$query*" -or $_.Variable -like "*$query*" -or $_.Path -like "*$query*"
        }
    }
}

function Show-CodexOfficeTypesettingTools {
    [CmdletBinding()]
    param(
        [switch]$MissingOnly
    )

    $rows = Register-CodexOfficeTypesettingTools
    if ($MissingOnly) {
        $rows = @($rows | Where-Object Status -eq 'Missing')
    }

    $rows | Sort-Object Category, Name | Format-Table Name, Status, Variable, Path -AutoSize
}

function Invoke-CodexTypstCompile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [Parameter(Position = 1)]
        [string]$OutputPath
    )

    Register-CodexOfficeTypesettingTools | Out-Null
    if ([string]::IsNullOrWhiteSpace($global:TypstExe)) {
        throw 'Typst was not found. Run the toolkit installer with -IncludeOfficeTypesettingTools.'
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = [IO.Path]::ChangeExtension($InputPath, '.pdf')
    }

    & $global:TypstExe compile $InputPath $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Typst failed while compiling $InputPath."
    }
}

function Invoke-CodexXeLaTeX {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [string]$OutputDirectory
    )

    Register-CodexOfficeTypesettingTools | Out-Null
    if ([string]::IsNullOrWhiteSpace($global:XeLaTeXExe)) {
        throw 'XeLaTeX was not found. Run the toolkit installer with -IncludeOfficeTypesettingTools.'
    }

    $arguments = @('-interaction=nonstopmode', '-halt-on-error')
    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $arguments += @('-output-directory', $OutputDirectory)
    }
    $arguments += $InputPath

    & $global:XeLaTeXExe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "XeLaTeX failed while compiling $InputPath."
    }
}

function Invoke-CodexMarpDeck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$OutputPath,

        [ValidateSet('pptx', 'pdf', 'html', 'pptx-editable')]
        [string]$Format = 'pptx'
    )

    Register-CodexOfficeTypesettingTools | Out-Null
    if ([string]::IsNullOrWhiteSpace($global:MarpCmd)) {
        throw 'Marp CLI was not found. Run npm install -g @marp-team/marp-cli or the toolkit installer with -IncludeOfficeTypesettingTools.'
    }

    $arguments = @($InputPath, '-o', $OutputPath)
    switch ($Format) {
        'pptx' { $arguments += '--pptx' }
        'pdf' { $arguments += '--pdf' }
        'pptx-editable' { $arguments += '--pptx-editable' }
        default { }
    }

    if ($Format -in @('pptx', 'pdf', 'pptx-editable') -and -not [string]::IsNullOrWhiteSpace($global:ChromiumExe)) {
        $arguments += @('--browser', 'chrome', '--browser-path', $global:ChromiumExe, '--browser-timeout', '60')
    }

    & $global:MarpCmd @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Marp failed while converting $InputPath."
    }
}

function Invoke-CodexOfficeTypesettingSamples {
    [CmdletBinding()]
    param()

    Register-CodexOfficeTypesettingTools | Out-Null
    $root = $global:OfficeTypesettingToolsRoot
    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
        throw 'OfficeTypesettingTools root was not found. Run the toolkit installer with -IncludeOfficeTypesettingTools.'
    }

    Push-Location $root
    try {
        $typstSample = Join-Path $root 'templates\typst-exam.typ'
        if (Test-Path -LiteralPath $typstSample) {
            Invoke-CodexTypstCompile -InputPath $typstSample -OutputPath (Join-Path $root 'templates\typst-exam.pdf')
        }

        $marpSample = Join-Path $root 'templates\marp-lesson.md'
        if (Test-Path -LiteralPath $marpSample) {
            Invoke-CodexMarpDeck -InputPath $marpSample -OutputPath (Join-Path $root 'templates\marp-lesson.pptx') -Format pptx
            Invoke-CodexMarpDeck -InputPath $marpSample -OutputPath (Join-Path $root 'templates\marp-lesson.pdf') -Format pdf
        }

        $pptxSample = Join-Path $root 'tools\generate-editable-pptx.js'
        if (Test-Path -LiteralPath $pptxSample) {
            if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
                throw 'node was not found, so the editable PPTX sample cannot run.'
            }

            & node $pptxSample
            if ($LASTEXITCODE -ne 0) {
                throw 'Editable PPTX sample generation failed.'
            }
        }
    } finally {
        Pop-Location
    }
}

Initialize-CodexOfficeTypesettingToolVariables

Set-Alias -Name office-tools -Value Show-CodexOfficeTypesettingTools -Scope Global -Option AllScope -Force
Set-Alias -Name office-tool-paths -Value Get-CodexOfficeTypesettingTool -Scope Global -Option AllScope -Force
Set-Alias -Name office-samples -Value Invoke-CodexOfficeTypesettingSamples -Scope Global -Option AllScope -Force
Set-Alias -Name typst-pdf -Value Invoke-CodexTypstCompile -Scope Global -Option AllScope -Force
Set-Alias -Name tex-xe -Value Invoke-CodexXeLaTeX -Scope Global -Option AllScope -Force
Set-Alias -Name marp-deck -Value Invoke-CodexMarpDeck -Scope Global -Option AllScope -Force

function marp-pptx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [Parameter(Position = 1)]
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = [IO.Path]::ChangeExtension($InputPath, '.pptx')
    }

    Invoke-CodexMarpDeck -InputPath $InputPath -OutputPath $OutputPath -Format pptx
}

function marp-pdf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [Parameter(Position = 1)]
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = [IO.Path]::ChangeExtension($InputPath, '.pdf')
    }

    Invoke-CodexMarpDeck -InputPath $InputPath -OutputPath $OutputPath -Format pdf
}

function marp-pptx-editable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [Parameter(Position = 1)]
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
        $directory = [IO.Path]::GetDirectoryName($InputPath)
        $OutputPath = Join-Path $directory ($baseName + '-editable.pptx')
    }

    Invoke-CodexMarpDeck -InputPath $InputPath -OutputPath $OutputPath -Format pptx-editable
}
