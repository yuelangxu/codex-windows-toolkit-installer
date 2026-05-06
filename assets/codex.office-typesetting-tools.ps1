${existingCodexOfficeTypesettingToolsLoaded} = Get-Variable -Name CodexOfficeTypesettingToolsLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -ne ${existingCodexOfficeTypesettingToolsLoaded} -and ${existingCodexOfficeTypesettingToolsLoaded}.Value) {
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
        if ($expandedPath.IndexOfAny(@('*', '?')) -ge 0) {
            $match = Get-ChildItem -Path $expandedPath -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $match) {
                return $match.FullName
            }
        } elseif (Test-Path -LiteralPath $expandedPath) {
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
        (New-CodexOfficeToolDefinition -Name 'BrightSlide PPAM' -VariableName 'BrightSlideAddIn' -CandidatePaths @(
            (Join-Path $appData 'Microsoft\AddIns\BrightCarbon\BrightSlide\BrightSlide.ppam'),
            (Join-Path $appData 'Microsoft\AddIns\BrightCarbon\BrightSlide\BrightSlide Helper.ppam')
        ) -Description 'free PowerPoint productivity add-in for alignment, sizing, and layout polish')
        (New-CodexOfficeToolDefinition -Name 'Instrumenta PPAM' -VariableName 'InstrumentaAddIn' -CandidatePaths @(
            (Join-Path $appData 'Microsoft\AddIns\InstrumentaPowerpointToolbar.ppam')
        ) -Description 'open-source PowerPoint toolbar for consulting-style layout and shape work')
        (New-CodexOfficeToolDefinition -Name 'THOR PPAM' -VariableName 'ThorAddIn' -CandidatePaths @(
            (Join-Path $appData 'Microsoft\AddIns\PPTools\THOR\THOR.PPAM')
        ) -Description 'free PowerPoint layout normalizer for size, position, and formatting consistency')
        (New-CodexOfficeToolDefinition -Name 'PowerUpKit PPAM' -VariableName 'PowerUpKitAddIn' -CandidatePaths @(
            (Join-Path $appData 'Microsoft\AddIns\PowerUpKit*.ppam')
        ) -Description 'free PowerPoint add-in with reusable favorites and 100+ shape utilities')
        (New-CodexOfficeToolDefinition -Name 'TexMaths OXT' -VariableName 'TexMathsOxt' -CandidatePaths @(
            (Join-Path $officeTypesettingRoot 'downloads\TexMaths.oxt'),
            (Join-Path $officeTypesettingRoot 'downloads\TexMaths-0.52.6.oxt'),
            (Join-Path $desktopRoot 'OfficeTypesettingTools\downloads\TexMaths.oxt'),
            (Join-Path $desktopRoot 'OfficeTypesettingTools\downloads\TexMaths-0.52.6.oxt'),
            (Join-Path $appData 'LibreOffice\4\user\uno_packages\cache\uno_packages\*\TexMaths.oxt'),
            (Join-Path $appData 'LibreOffice\4\user\extensions\tmp\extensions\*\TexMaths.oxt')
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
                if ($expandedPath.IndexOfAny(@('*', '?')) -ge 0) {
                    $match = Get-ChildItem -Path $expandedPath -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($null -ne $match) {
                        $path = $match.FullName
                        break
                    }
                } elseif (Test-Path -LiteralPath $expandedPath) {
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

function Resolve-CodexOfficeProjectPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }

    return [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Ensure-CodexDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-CodexTextFileIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $parent = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            Ensure-CodexDirectory -Path $parent
        }

        Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    }
}

function Get-CodexOfficeTypesettingRootPath {
    $root = $global:OfficeTypesettingToolsRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\OfficeTypesettingTools'
    }

    Ensure-CodexDirectory -Path $root
    return $root
}

function Ensure-CodexOfficeTypesettingScaffolds {
    $root = Get-CodexOfficeTypesettingRootPath
    $templatesRoot = Join-Path $root 'templates'
    $coursepackTemplateRoot = Join-Path $templatesRoot 'coursepack'

    Ensure-CodexDirectory -Path $templatesRoot
    Ensure-CodexDirectory -Path $coursepackTemplateRoot
    Ensure-CodexDirectory -Path (Join-Path $root 'examples')

    Write-CodexTextFileIfMissing -Path (Join-Path $templatesRoot 'typst-exam.typ') -Content @'
#set page(width: 210mm, height: 297mm, margin: (x: 18mm, y: 16mm))
#set text(font: "Times New Roman", size: 11pt)
#set heading(numbering: "1.")

= Quantum Physics Sample Handout

== Learning goals

- Explain the physical meaning of tunneling and barrier penetration.
- Connect lecture notes, problem sheets, and exam-style questions.
- Leave space for worked examples and annotations.

== Core result

$ T approx exp(-2 kappa a) $

== Prompted exercises

1. Sketch how the wavefunction amplitude changes across the barrier.
2. Compare how $T$ changes with barrier height versus width.
3. Add one common exam pitfall below this section.
'@

    Write-CodexTextFileIfMissing -Path (Join-Path $templatesRoot 'marp-lesson.md') -Content @'
---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  section {
    font-family: "Aptos", "Segoe UI", sans-serif;
    color: #10253F;
    background: linear-gradient(135deg, #F7FBFF 0%, #E7F0FA 100%);
  }
  h1, h2 { color: #10253F; }
  footer { color: #4A6B8A; }
---

# Quantum Tunneling

## Lecture roadmap

- Barrier penetration intuition
- Wavefunction matching
- Exponential sensitivity

---

## Why students lose marks

- Forgetting the physical meaning of the decay constant
- Mixing up amplitude and probability
- Ignoring how width changes the exponent
'@

    Write-CodexTextFileIfMissing -Path (Join-Path $coursepackTemplateRoot 'coursepack.json') -Content @'
{
  "title": "Quantum Tunneling",
  "subtitle": "Lecture + Handout Pack",
  "author": "Codex Toolkit",
  "slug": "quantum-tunneling",
  "themeColor": "#143B6B"
}
'@

    Write-CodexTextFileIfMissing -Path (Join-Path $coursepackTemplateRoot 'slides.md') -Content @'
---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  section {
    font-family: "Aptos", "Segoe UI", sans-serif;
    color: #10253F;
    background: linear-gradient(135deg, #F7FBFF 0%, #E7F0FA 100%);
  }
  h1, h2 { color: #10253F; }
  strong { color: #143B6B; }
---

# Quantum Tunneling

### Lecture + revision pack

---

## Key message

**Tunneling probability is exponentially sensitive** to barrier width and height.

---

## Build prompts

- Replace this slide with your real lecture outline.
- Add figures or screenshots into `assets\`.
- Keep each slide tied to one exam-facing idea.
'@

    Write-CodexTextFileIfMissing -Path (Join-Path $coursepackTemplateRoot 'handout.typ') -Content @'
#set page(width: 210mm, height: 297mm, margin: (x: 18mm, y: 16mm))
#set text(font: "Times New Roman", size: 11pt)
#set heading(numbering: "1.")

= Quantum Tunneling

== Summary

This handout is the printable companion to the slide deck.

== Main equation

$ T approx exp(-2 kappa a) $

== Checklist

- State what each symbol means.
- Explain why the exponent changes with width.
- Link the formula back to the physical picture.
'@

    Write-CodexTextFileIfMissing -Path (Join-Path $coursepackTemplateRoot 'README.md') -Content @'
# Coursepack Template

```powershell
coursepack-init .\my-lesson -Title "Quantum Tunneling" -Subtitle "Week 5" -Author "Your Name"
coursepack-build .\my-lesson
```

Outputs:

- `output\<slug>.pptx`
- `output\<slug>-editable.pptx`
- `output\<slug>-slides.pdf`
- `output\<slug>-handout.pdf`
'@
}

function Invoke-CodexOfficeTypesettingSamples {
    [CmdletBinding()]
    param()

    Register-CodexOfficeTypesettingTools | Out-Null
    Ensure-CodexOfficeTypesettingScaffolds
    $root = Get-CodexOfficeTypesettingRootPath
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

        $coursepackSampleRoot = Join-Path $root 'templates\coursepack'
        if (Test-Path -LiteralPath $coursepackSampleRoot) {
            Invoke-CodexCoursePackBuild -Path $coursepackSampleRoot | Out-Null
        }
    } finally {
        Pop-Location
    }
}

function Initialize-CodexCoursePackProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [string]$Title = 'Course Pack',

        [string]$Subtitle = 'Lecture + handout',

        [string]$Author = $env:USERNAME,

        [string]$Slug
    )

    Ensure-CodexOfficeTypesettingScaffolds

    $resolvedRoot = Resolve-CodexOfficeProjectPath -Path $Path
    Ensure-CodexDirectory -Path $resolvedRoot
    Ensure-CodexDirectory -Path (Join-Path $resolvedRoot 'assets')
    Ensure-CodexDirectory -Path (Join-Path $resolvedRoot 'output')

    if ([string]::IsNullOrWhiteSpace($Slug)) {
        $Slug = (($Title -replace '[^A-Za-z0-9]+', '-').Trim('-')).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($Slug)) {
            $Slug = 'course-pack'
        }
    }

    $config = [ordered]@{
        title = $Title
        subtitle = $Subtitle
        author = $Author
        slug = $Slug
        themeColor = '#143B6B'
    } | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath (Join-Path $resolvedRoot 'coursepack.json') -Value $config -Encoding UTF8

    $slidesContent = @"
---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  section {
    font-family: "Aptos", "Segoe UI", sans-serif;
    color: #10253F;
    background: linear-gradient(135deg, #F7FBFF 0%, #E7F0FA 100%);
  }
  h1, h2 { color: #10253F; }
  footer { color: #4A6B8A; }
---

# $Title

### $Subtitle

---

## Learning goals

- Replace this slide with the three most important takeaways.
- Add diagrams or screenshots into `assets\`.
- Keep each slide tied to one exam-facing question.

---

## Worked example

- State the setup
- Show the governing equation
- Highlight the pitfall students usually miss
"@
    Set-Content -LiteralPath (Join-Path $resolvedRoot 'slides.md') -Value $slidesContent -Encoding UTF8

    $handoutContent = @"
#set page(width: 210mm, height: 297mm, margin: (x: 18mm, y: 16mm))
#set text(font: "Times New Roman", size: 11pt)
#set heading(numbering: "1.")

= $Title

== $Subtitle

This handout is the printable companion to the slide deck.

== Key points

- Define the main idea in one sentence.
- Add the core derivation or formula.
- Leave space for handwritten annotations.
"@
    Set-Content -LiteralPath (Join-Path $resolvedRoot 'handout.typ') -Value $handoutContent -Encoding UTF8

    $readme = @(
        "# $Title",
        '',
        '```powershell',
        ('coursepack-build "{0}"' -f $resolvedRoot),
        '```',
        '',
        'Generated files will appear in:',
        '',
        ('- `output\{0}.pptx`' -f $Slug),
        ('- `output\{0}-editable.pptx`' -f $Slug),
        ('- `output\{0}-slides.pdf`' -f $Slug),
        ('- `output\{0}-handout.pdf`' -f $Slug)
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath (Join-Path $resolvedRoot 'README.md') -Value $readme -Encoding UTF8

    [pscustomobject]@{
        Path = $resolvedRoot
        Title = $Title
        Slug = $Slug
    }
}

function Invoke-CodexCoursePackBuild {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [switch]$OpenOutput
    )

    Register-CodexOfficeTypesettingTools | Out-Null
    $resolvedRoot = Resolve-CodexOfficeProjectPath -Path $Path
    $configPath = Join-Path $resolvedRoot 'coursepack.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "coursepack.json was not found in $resolvedRoot. Run coursepack-init first."
    }

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $slug = if ($config.slug) { [string]$config.slug } else { 'course-pack' }
    $outputRoot = Join-Path $resolvedRoot 'output'
    Ensure-CodexDirectory -Path $outputRoot

    $slidesPath = Join-Path $resolvedRoot 'slides.md'
    if (Test-Path -LiteralPath $slidesPath) {
        marp-pptx $slidesPath (Join-Path $outputRoot ($slug + '.pptx'))
        marp-pptx-editable $slidesPath (Join-Path $outputRoot ($slug + '-editable.pptx'))
        marp-pdf $slidesPath (Join-Path $outputRoot ($slug + '-slides.pdf'))
    }

    $handoutPath = Join-Path $resolvedRoot 'handout.typ'
    if (Test-Path -LiteralPath $handoutPath) {
        typst-pdf $handoutPath (Join-Path $outputRoot ($slug + '-handout.pdf'))
    }

    if ($OpenOutput) {
        Start-Process explorer.exe $outputRoot | Out-Null
    }

    [pscustomobject]@{
        Root = $resolvedRoot
        OutputRoot = $outputRoot
        SlideDeck = (Join-Path $outputRoot ($slug + '.pptx'))
        EditableSlideDeck = (Join-Path $outputRoot ($slug + '-editable.pptx'))
        SlidesPdf = (Join-Path $outputRoot ($slug + '-slides.pdf'))
        HandoutPdf = (Join-Path $outputRoot ($slug + '-handout.pdf'))
    }
}

Initialize-CodexOfficeTypesettingToolVariables

Set-Alias -Name office-tools -Value Show-CodexOfficeTypesettingTools -Scope Global -Option AllScope -Force
Set-Alias -Name office-tool-paths -Value Get-CodexOfficeTypesettingTool -Scope Global -Option AllScope -Force
Set-Alias -Name office-samples -Value Invoke-CodexOfficeTypesettingSamples -Scope Global -Option AllScope -Force
Set-Alias -Name typst-pdf -Value Invoke-CodexTypstCompile -Scope Global -Option AllScope -Force
Set-Alias -Name tex-xe -Value Invoke-CodexXeLaTeX -Scope Global -Option AllScope -Force
Set-Alias -Name marp-deck -Value Invoke-CodexMarpDeck -Scope Global -Option AllScope -Force
Set-Alias -Name coursepack-init -Value Initialize-CodexCoursePackProject -Scope Global -Option AllScope -Force
Set-Alias -Name coursepack-build -Value Invoke-CodexCoursePackBuild -Scope Global -Option AllScope -Force

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
