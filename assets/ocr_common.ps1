Set-StrictMode -Version Latest

function Resolve-CodexLiteralPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Resolve-Path -LiteralPath $Path -ErrorAction Stop | Select-Object -First 1).Path
}

function Test-CodexCommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-CodexDirectorySizeMB {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $sum = (
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Measure-Object -Property Length -Sum
    ).Sum

    if ($null -eq $sum) {
        return 0
    }

    return [math]::Round($sum / 1MB, 2)
}

function Format-CodexSize {
    param(
        [Parameter(Mandatory = $true)]
        [double]$SizeMB
    )

    if ($SizeMB -ge 1024) {
        return ('{0:N2} GB' -f ($SizeMB / 1024))
    }

    return ('{0:N2} MB' -f $SizeMB)
}

function New-CodexTempFilePath {
    param(
        [string]$Extension = '.tmp'
    )

    if (-not $Extension.StartsWith('.')) {
        $Extension = ".$Extension"
    }

    return Join-Path ([IO.Path]::GetTempPath()) ("codex-ocr-{0}{1}" -f ([guid]::NewGuid().ToString('N')), $Extension)
}

function New-CodexTempDirectory {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ("codex-ocr-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    return $directory
}

function Resolve-TesseractLanguageCode {
    param(
        [string]$Lang = 'en'
    )

    $normalized = $Lang.Trim().ToLowerInvariant()

    switch -Regex ($normalized) {
        '^(en|eng|english)$' { return 'eng' }
        '^(zh|zh-cn|zh_hans|chi_sim|ch|chinese)$' { return 'chi_sim' }
        '^(zh-tw|zh_hant|chi_tra|traditional)$' { return 'chi_tra' }
        '^(ja|jpn|japanese)$' { return 'jpn' }
        '^(ko|kor|korean)$' { return 'kor' }
        '^(fr|fra|french)$' { return 'fra' }
        '^(de|deu|ger|german)$' { return 'deu' }
        '^(es|spa|spanish)$' { return 'spa' }
        default {
            if ($normalized -match ',') {
                return 'eng'
            }

            return $normalized
        }
    }
}

function Resolve-Capture2TextLanguage {
    param(
        [string]$Lang = 'en'
    )

    $normalized = $Lang.Trim().ToLowerInvariant()

    switch -Regex ($normalized) {
        '^(en|eng|english)$' { return 'English' }
        default { return 'English' }
    }
}

function Test-LanguageNeedsPaddle {
    param(
        [string]$Lang = 'en'
    )

    if ([string]::IsNullOrWhiteSpace($Lang)) {
        return $false
    }

    $normalized = $Lang.Trim().ToLowerInvariant()
    if ($normalized -match ',') {
        return $true
    }

    return $normalized -notmatch '^(en|eng|english)$'
}

function Test-DocumentQuestion {
    param(
        [string]$Question
    )

    if ([string]::IsNullOrWhiteSpace($Question)) {
        return $false
    }

    $normalized = $Question.ToLowerInvariant()
    return $normalized -match '(text|field|invoice|receipt|form|table|document|ocr|title|author|extract|read|what does|what text)'
}

function Test-AcademicPdfName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $name = [IO.Path]::GetFileNameWithoutExtension($InputPath).ToLowerInvariant()
    return $name -match '(paper|article|journal|manuscript|arxiv|supplement|appendix|preprint|thesis|report)'
}

function Select-CodexFirstAvailableCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if (Test-CodexCommandAvailable -Name $candidate) {
            return $candidate
        }
    }

    throw "None of the preferred commands are available: $([string]::Join(', ', $Candidates))"
}

function Invoke-CodexExternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string[]]$Arguments = @()
    )

    & $CommandName @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command '$CommandName' failed with exit code $LASTEXITCODE."
    }
}

function Invoke-CodexTesseractText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Lang = 'en'
    )

    $langCode = Resolve-TesseractLanguageCode -Lang $Lang
    Invoke-CodexExternal -CommandName 'tesseract' -Arguments @($InputPath, 'stdout', '-l', $langCode, '--psm', '6')
}

function Invoke-CodexCapture2Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Lang = 'en'
    )

    $captureLanguage = Resolve-Capture2TextLanguage -Lang $Lang
    Invoke-CodexExternal -CommandName 'capture2text' -Arguments @('-i', $InputPath, '-l', $captureLanguage)
}

function Invoke-CodexPaddleText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Lang = 'en'
    )

    Invoke-CodexExternal -CommandName 'paddleocr-read' -Arguments @($InputPath, '--lang', $Lang, '--text-only')
}

function Invoke-CodexEasyOcrText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Lang = 'en'
    )

    $languageArgument = ($Lang -replace '\s+', '') -replace ';', ','
    Invoke-CodexExternal -CommandName 'easyocr-read' -Arguments @($InputPath, '--langs', $languageArgument, '--gpu', 'false')
}

function Invoke-CodexDonutQa {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Question,

        [switch]$Cpu
    )

    if ([string]::IsNullOrWhiteSpace($Question)) {
        $Question = 'What does this document say?'
    }

    $arguments = @($InputPath, '--preset', 'docvqa', '--question', $Question)
    if ($Cpu) {
        $arguments += '--cpu'
    }

    Invoke-CodexExternal -CommandName 'donut-ocr' -Arguments $arguments
}

function Invoke-CodexLlavaPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Question,

        [switch]$Cpu
    )

    $prompt = $Question
    if ([string]::IsNullOrWhiteSpace($prompt)) {
        $prompt = 'Describe this image and extract any visible text from it:'
    }

    $arguments = @()
    if ($Cpu) {
        $arguments += '--cpu'
    }
    $arguments += "$prompt $InputPath"

    Invoke-CodexExternal -CommandName 'llava' -Arguments $arguments
}

function Convert-CodexPdfFirstPageToImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PdfPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $pythonScript = @"
import pypdfium2

pdf = pypdfium2.PdfDocument(r'''$PdfPath''')
page = pdf[0]
bitmap = page.render(scale=2)
bitmap.to_pil().save(r'''$OutputPath''')
"@

    $pythonScript | & python -
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to render the first page of '$PdfPath'."
    }

    return $OutputPath
}

function Get-CodexImageEnginePreference {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [ValidateSet('auto', 'document', 'screenshot', 'handwriting', 'understand')]
        [string]$Mode = 'auto',

        [string]$Lang = 'en',

        [string]$Question
    )

    if (-not [string]::IsNullOrWhiteSpace($Question) -or $Mode -eq 'understand') {
        if (Test-DocumentQuestion -Question $Question) {
            return @('donut-ocr', 'llava', 'paddleocr-read', 'easyocr-read', 'tesseract')
        }

        return @('llava', 'donut-ocr', 'paddleocr-read', 'easyocr-read', 'tesseract')
    }

    switch ($Mode) {
        'handwriting' {
            return @('paddleocr-read', 'easyocr-read', 'tesseract')
        }
        'screenshot' {
            if (Test-LanguageNeedsPaddle -Lang $Lang) {
                return @('paddleocr-read', 'easyocr-read', 'capture2text', 'tesseract')
            }

            return @('capture2text', 'tesseract', 'paddleocr-read', 'easyocr-read')
        }
        'document' {
            if (Test-LanguageNeedsPaddle -Lang $Lang) {
                return @('paddleocr-read', 'tesseract', 'easyocr-read')
            }

            return @('tesseract', 'paddleocr-read', 'easyocr-read')
        }
        default {
            $name = [IO.Path]::GetFileName($InputPath).ToLowerInvariant()
            $extension = [IO.Path]::GetExtension($InputPath).ToLowerInvariant()

            if (
                (Test-LanguageNeedsPaddle -Lang $Lang) -or
                ($name -match 'hand|scribble|whiteboard|note|camera|photo') -or
                ($extension -in @('.jpg', '.jpeg', '.webp', '.heic'))
            ) {
                return @('paddleocr-read', 'easyocr-read', 'tesseract')
            }

            return @('tesseract', 'capture2text', 'paddleocr-read', 'easyocr-read')
        }
    }
}

function Invoke-CodexImageEngine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Engine,

        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Lang = 'en',

        [string]$Question,

        [switch]$Cpu
    )

    switch ($Engine) {
        'capture2text' { Invoke-CodexCapture2Text -InputPath $InputPath -Lang $Lang; break }
        'tesseract' { Invoke-CodexTesseractText -InputPath $InputPath -Lang $Lang; break }
        'paddleocr-read' { Invoke-CodexPaddleText -InputPath $InputPath -Lang $Lang; break }
        'easyocr-read' { Invoke-CodexEasyOcrText -InputPath $InputPath -Lang $Lang; break }
        'donut-ocr' { Invoke-CodexDonutQa -InputPath $InputPath -Question $Question -Cpu:$Cpu; break }
        'llava' { Invoke-CodexLlavaPrompt -InputPath $InputPath -Question $Question -Cpu:$Cpu; break }
        default { throw "Unsupported OCR engine '$Engine'." }
    }
}

function Get-CodexPdfEnginePreference {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [ValidateSet('auto', 'searchable', 'academic', 'understand')]
        [string]$Mode = 'auto',

        [string]$OutPath,

        [string]$Question
    )

    if (-not [string]::IsNullOrWhiteSpace($Question) -or $Mode -eq 'understand') {
        if (Test-DocumentQuestion -Question $Question) {
            return @('donut-ocr', 'llava', 'nougat')
        }

        return @('llava', 'donut-ocr', 'nougat')
    }

    if ($Mode -eq 'academic') {
        return @('nougat', 'ocrmypdf')
    }

    if ($Mode -eq 'searchable') {
        return @('ocrmypdf', 'nougat')
    }

    if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
        $extension = [IO.Path]::GetExtension($OutPath).ToLowerInvariant()
        if ($extension -in @('.md', '.mmd')) {
            return @('nougat', 'ocrmypdf')
        }
        if ($extension -eq '.pdf') {
            return @('ocrmypdf', 'nougat')
        }
    }

    if (Test-AcademicPdfName -InputPath $InputPath) {
        return @('nougat', 'ocrmypdf')
    }

    return @('ocrmypdf', 'nougat')
}

function Invoke-CodexNougat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$OutPath
    )

    $stem = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $parent = Split-Path -Parent $InputPath
    $temporaryOutputDirectory = $null
    $outputDirectory = $null
    $finalOutputFile = $null

    if ([string]::IsNullOrWhiteSpace($OutPath)) {
        $outputDirectory = Join-Path $parent ("{0}_nougat" -f $stem)
    } else {
        $extension = [IO.Path]::GetExtension($OutPath).ToLowerInvariant()
        if ($extension -in @('.md', '.mmd')) {
            $temporaryOutputDirectory = New-CodexTempDirectory
            $outputDirectory = $temporaryOutputDirectory
            $finalOutputFile = $OutPath
        } else {
            $outputDirectory = $OutPath
        }
    }

    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Invoke-CodexExternal -CommandName 'nougat' -Arguments @($InputPath, '-o', $outputDirectory, '--no-skipping', '--full-precision')

    $generatedFile = Join-Path $outputDirectory ("{0}.mmd" -f $stem)
    if (-not (Test-Path -LiteralPath $generatedFile)) {
        throw "Nougat finished but did not produce '$generatedFile'."
    }

    if (-not [string]::IsNullOrWhiteSpace($finalOutputFile)) {
        Copy-Item -LiteralPath $generatedFile -Destination $finalOutputFile -Force
        if ($temporaryOutputDirectory) {
            Remove-Item -LiteralPath $temporaryOutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $finalOutputFile
    }

    return $generatedFile
}

function Invoke-CodexOcrmypdf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$OutPath
    )

    if ([string]::IsNullOrWhiteSpace($OutPath)) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($InputPath)
        $parent = Split-Path -Parent $InputPath
        $OutPath = Join-Path $parent ("{0}.searchable.pdf" -f $stem)
    }

    Invoke-CodexExternal -CommandName 'ocrmypdf' -Arguments @('--skip-text', $InputPath, $OutPath)
    return $OutPath
}

function Invoke-CodexPdfSmart {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [ValidateSet('auto', 'searchable', 'academic', 'understand')]
        [string]$Mode = 'auto',

        [string]$OutPath,

        [string]$Question,

        [switch]$Cpu
    )

    $resolvedInputPath = Resolve-CodexLiteralPath -Path $InputPath
    $engine = Select-CodexFirstAvailableCommand -Candidates (Get-CodexPdfEnginePreference -InputPath $resolvedInputPath -Mode $Mode -OutPath $OutPath -Question $Question)
    Write-Host "[pdf-smart] engine=$engine | mode=$Mode" -ForegroundColor DarkGray

    switch ($engine) {
        'ocrmypdf' {
            return Invoke-CodexOcrmypdf -InputPath $resolvedInputPath -OutPath $OutPath
        }
        'nougat' {
            return Invoke-CodexNougat -InputPath $resolvedInputPath -OutPath $OutPath
        }
        'donut-ocr' {
            $tempImage = New-CodexTempFilePath -Extension '.png'
            try {
                Convert-CodexPdfFirstPageToImage -PdfPath $resolvedInputPath -OutputPath $tempImage | Out-Null
                Invoke-CodexDonutQa -InputPath $tempImage -Question $Question -Cpu:$Cpu
            } finally {
                Remove-Item -LiteralPath $tempImage -Force -ErrorAction SilentlyContinue
            }
            return
        }
        'llava' {
            $tempImage = New-CodexTempFilePath -Extension '.png'
            try {
                Convert-CodexPdfFirstPageToImage -PdfPath $resolvedInputPath -OutputPath $tempImage | Out-Null
                Invoke-CodexLlavaPrompt -InputPath $tempImage -Question $Question -Cpu:$Cpu
            } finally {
                Remove-Item -LiteralPath $tempImage -Force -ErrorAction SilentlyContinue
            }
            return
        }
        default {
            throw "Unsupported PDF engine '$engine'."
        }
    }
}

function Get-CodexOcrInventory {
    $userHome = [Environment]::GetFolderPath('UserProfile')
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $ollamaRoot = Join-Path $userHome '.ollama\models'
    $nougatRoot = Join-Path $userHome '.cache\torch\hub\nougat-0.1.0-small'
    $donutRoot = Join-Path $userHome '.cache\huggingface\hub\models--naver-clova-ix--donut-base-finetuned-docvqa'
    $easyOcrRoot = Join-Path $userHome '.EasyOCR\model'
    $paddleOcrRoot = Join-Path $userHome '.paddleocr\whl'
    $tesseractRoot = Join-Path $programFiles 'Tesseract-OCR\tessdata'
    $items = @()

    $items += [pscustomobject]@{
        Tool      = 'llava'
        Model     = 'llava:latest'
        Command   = 'llava'
        CachePath = $ollamaRoot
        SizeMB    = Get-CodexDirectorySizeMB -Path $ollamaRoot
        Notes     = "Local multimodal model via Ollama; manifest at $(Join-Path $ollamaRoot 'manifests\registry.ollama.ai\library\llava\latest')"
    }
    $items += [pscustomobject]@{
        Tool      = 'nougat'
        Model     = '0.1.0-small'
        Command   = 'nougat'
        CachePath = $nougatRoot
        SizeMB    = Get-CodexDirectorySizeMB -Path $nougatRoot
        Notes     = 'Academic PDF recovery model cached under Torch Hub'
    }
    $items += [pscustomobject]@{
        Tool      = 'donut-ocr'
        Model     = 'naver-clova-ix/donut-base-finetuned-docvqa'
        Command   = 'donut-ocr'
        CachePath = $donutRoot
        SizeMB    = Get-CodexDirectorySizeMB -Path $donutRoot
        Notes     = 'Document QA model cached in Hugging Face Hub'
    }
    $items += [pscustomobject]@{
        Tool      = 'easyocr-read'
        Model     = 'craft_mlt_25k + english_g2'
        Command   = 'easyocr-read'
        CachePath = $easyOcrRoot
        SizeMB    = Get-CodexDirectorySizeMB -Path $easyOcrRoot
        Notes     = 'EasyOCR detection and recognition weights'
    }
    $items += [pscustomobject]@{
        Tool      = 'paddleocr-read'
        Model     = 'PP-OCR English det/rec + cls'
        Command   = 'paddleocr-read'
        CachePath = $paddleOcrRoot
        SizeMB    = Get-CodexDirectorySizeMB -Path $paddleOcrRoot
        Notes     = 'PaddleOCR local detector, recognizer, and angle classifier'
    }
    $items += [pscustomobject]@{
        Tool      = 'tesseract'
        Model     = 'tessdata multilingual pack'
        Command   = 'tesseract'
        CachePath = $tesseractRoot
        SizeMB    = Get-CodexDirectorySizeMB -Path $tesseractRoot
        Notes     = 'Tesseract language packs including eng, chi_sim, jpn, kor, and more'
    }

    foreach ($item in $items) {
        $sizeText = 'missing'
        if ($null -ne $item.SizeMB) {
            $sizeText = Format-CodexSize -SizeMB $item.SizeMB
        }

        $item | Add-Member -NotePropertyName Size -NotePropertyValue $sizeText
    }

    return $items
}

function Escape-CodexMarkdownCell {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ($Value.ToString() -replace '\|', '\|' -replace "(`r`n|`n|`r)", ' ')
}

function Get-CodexOcrReferenceMarkdown {
    $inventory = Get-CodexOcrInventory
    $lines = New-Object System.Collections.Generic.List[string]

    [void]$lines.Add('# Codex OCR Toolkit')
    [void]$lines.Add('')
    [void]$lines.Add('## Local Model Inventory')
    [void]$lines.Add('')
    [void]$lines.Add('| Command | Model | Cache path | Size | Notes |')
    [void]$lines.Add('| --- | --- | --- | --- | --- |')
    foreach ($item in $inventory) {
        $row = '| {0} | {1} | `{2}` | {3} | {4} |' -f (
            Escape-CodexMarkdownCell $item.Command
        ), (
            Escape-CodexMarkdownCell $item.Model
        ), (
            Escape-CodexMarkdownCell $item.CachePath
        ), (
            Escape-CodexMarkdownCell $item.Size
        ), (
            Escape-CodexMarkdownCell $item.Notes
        )
        [void]$lines.Add($row)
    }

    [void]$lines.Add('')
    [void]$lines.Add('## Quick Reference')
    [void]$lines.Add('')
    [void]$lines.Add('| Category | Best fit | Use when | Practical note |')
    [void]$lines.Add('| --- | --- | --- | --- |')
    [void]$lines.Add('| Suitable for documents | `pdf-smart -Mode searchable`, `ocrmypdf`, `tesseract`, `nougat`, `donut-ocr` | Scanned PDFs, printed pages, academic papers, structured forms | `pdf-smart` defaults to `ocrmypdf` for normal PDFs and switches to `nougat` for academic-style recovery or markdown output |')
    [void]$lines.Add('| Suitable for screenshots | `ocr-smart`, `capture2text`, `tesseract`, `paddleocr-read` | UI screenshots, terminal captures, clean English text blocks | `ocr-smart` prefers fast clean-text engines first, then falls back to Paddle/EasyOCR when text is mixed or noisy |')
    [void]$lines.Add('| Suitable for handwriting | `ocr-smart -Mode handwriting`, `paddleocr-read`, `easyocr-read` | Notes, whiteboards, camera photos, mixed handwriting and print | Paddle is the default handwriting-heavy route; EasyOCR is the lightweight fallback |')
    [void]$lines.Add('| Suitable for understanding and summarization | `ocr-smart -Mode understand`, `pdf-smart -Mode understand`, `llava`, `donut-ocr`, `nougat` | Open-ended description, document QA, academic markdown reconstruction | `pdf-smart -Mode understand` currently answers from the first page image; `pdf-smart -Mode academic` is the better route for full-paper recovery |')

    [void]$lines.Add('')
    [void]$lines.Add('## Smart Commands')
    [void]$lines.Add('')
    [void]$lines.Add('```powershell')
    [void]$lines.Add('ocr-smart .\shot.png')
    [void]$lines.Add('ocr-smart .\note.jpg -Mode handwriting -Lang en')
    [void]$lines.Add('ocr-smart .\form.png -Mode understand -Question "What text is shown?" -Cpu')
    [void]$lines.Add('pdf-smart .\scan.pdf -Mode searchable')
    [void]$lines.Add('pdf-smart .\paper.pdf -Mode academic')
    [void]$lines.Add('pdf-smart .\report.pdf -Mode understand -Question "What is the title on the first page?" -Cpu')
    [void]$lines.Add('ocr-models')
    [void]$lines.Add('```')

    [void]$lines.Add('')
    [void]$lines.Add('## Routing Rules')
    [void]$lines.Add('')
    [void]$lines.Add('- `ocr-smart` prefers `capture2text` or `tesseract` for clean screenshots, `paddleocr-read` for handwriting or mixed-language images, `donut-ocr` for document-style QA, and `llava` for open-ended image understanding.')
    [void]$lines.Add('- `pdf-smart` prefers `ocrmypdf` for searchable PDF output, `nougat` for academic markdown recovery, and first-page `donut-ocr` or `llava` for quick PDF understanding.')
    [void]$lines.Add('- `ocr-models -Markdown -OutFile <path>` regenerates this inventory with current sizes and cache locations.')

    return [string]::Join([Environment]::NewLine, $lines)
}
