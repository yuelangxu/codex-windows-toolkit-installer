function Get-CodexExecutablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Name
    )

    foreach ($candidate in $Name) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $command) {
            continue
        }

        if ($command.CommandType -eq 'Alias') {
            $resolved = Get-Command $command.Definition -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $resolved) {
                $command = $resolved
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
            return $command.Source
        }

        if ($command.Path) {
            return $command.Path
        }

        if ($command.Definition) {
            return $command.Definition
        }
    }

    return $null
}

function ConvertTo-CodexBoolean {
    param(
        [string]$Value,
        [bool]$Default = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    switch ($Value.Trim().ToLowerInvariant()) {
        '1' { return $true }
        'true' { return $true }
        'yes' { return $true }
        'on' { return $true }
        '0' { return $false }
        'false' { return $false }
        'no' { return $false }
        'off' { return $false }
        default { return $Default }
    }
}

function Mask-CodexSecret {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    if ($Value.Length -le 8) {
        return ('*' * $Value.Length)
    }

    return '{0}{1}{2}' -f $Value.Substring(0, 4), ('*' * ($Value.Length - 8)), $Value.Substring($Value.Length - 4)
}

function Get-CodexOllamaInstalledModels {
    [CmdletBinding()]
    param()

    $ollama = Get-CodexExecutablePath -Name @('ollama')
    if ([string]::IsNullOrWhiteSpace($ollama)) {
        return @()
    }

    $output = & $ollama 'list' 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
        return @()
    }

    $models = New-Object System.Collections.Generic.List[string]
    foreach ($line in $output) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text) -or $text -match '^\s*NAME\s+') {
            continue
        }

        $name = ($text -split '\s+')[0]
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            [void]$models.Add($name)
        }
    }

    return @($models.ToArray())
}

function Get-CodexDefaultOllamaModel {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_OLLAMA_TRANSLATE_MODEL)) {
        return $env:CODEX_OLLAMA_TRANSLATE_MODEL
    }

    $models = @(Get-CodexOllamaInstalledModels)
    if ($models.Count -eq 0) {
        return ''
    }

    foreach ($candidate in @('qwen2.5:3b-instruct', 'qwen2.5:7b-instruct', 'llama3.1:8b-instruct', 'phi4-mini', 'phi3:mini')) {
        if ($models -contains $candidate) {
            return $candidate
        }
    }

    return $models[0]
}

function Get-CodexDefaultDocumentCacheRoot {
    [CmdletBinding()]
    param()

    $roots = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_POWERSHELL_ROOT)) {
        [void]$roots.Add($env:CODEX_POWERSHELL_ROOT)
    }

    [void]$roots.Add((Join-Path $HOME 'Documents\PowerShell\Toolkit'))
    [void]$roots.Add((Join-Path $HOME 'Documents\PowerShell\Codex'))

    $seen = @{}
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        $trimmed = $root.TrimEnd('\')
        $key = $trimmed.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        if (Test-Path -LiteralPath $trimmed) {
            return (Join-Path (Join-Path $trimmed 'cache') 'doc-cache')
        }
    }

    return (Join-Path (Join-Path (Join-Path $HOME 'Documents\PowerShell\Toolkit') 'cache') 'doc-cache')
}

function Initialize-CodexDocumentPipelineConfig {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_DOC_CACHE_ROOT)) {
        $cacheRoot = $env:CODEX_DOC_CACHE_ROOT
    } else {
        $cacheRoot = Get-CodexDefaultDocumentCacheRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_DOC_OCR_LANG)) {
        $defaultOcrLanguage = $env:CODEX_DOC_OCR_LANG
    } else {
        $defaultOcrLanguage = 'eng+chi_sim'
    }

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_DOC_TARGET_LANG)) {
        $defaultTargetLanguage = $env:CODEX_DOC_TARGET_LANG
    } else {
        $defaultTargetLanguage = 'zh'
    }

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_DOC_PRIVACY)) {
        $defaultPrivacy = $env:CODEX_DOC_PRIVACY
    } else {
        $defaultPrivacy = 'private'
    }
    $allowCloudForPrivate = ConvertTo-CodexBoolean -Value $env:CODEX_DOC_ALLOW_CLOUD_PRIVATE -Default:$false
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_DOC_IMAGE_PROFILE)) {
        $defaultImageProfile = $env:CODEX_DOC_IMAGE_PROFILE
    } else {
        $defaultImageProfile = 'auto'
    }
    $defaultPreprocessImages = ConvertTo-CodexBoolean -Value $env:CODEX_DOC_PREPROCESS_IMAGES -Default:$true
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_DOC_SCAN_SAMPLE_CHARS)) {
        $defaultScanSampleChars = [int]$env:CODEX_DOC_SCAN_SAMPLE_CHARS
    } else {
        $defaultScanSampleChars = 1400
    }

    $tools = [ordered]@{
        pdftotext = Get-CodexExecutablePath -Name @('pdftotext', 'pdftotext.exe')
        pdftoppm  = Get-CodexExecutablePath -Name @('pdftoppm', 'pdftoppm.exe')
        mutool    = Get-CodexExecutablePath -Name @('mutool', 'mutool.exe')
        ocrmypdf  = Get-CodexExecutablePath -Name @('ocrmypdf', 'ocrmypdf.exe')
        tesseract = Get-CodexExecutablePath -Name @('tesseract', 'tesseract.exe')
        magick    = Get-CodexExecutablePath -Name @('magick', 'magick.exe')
        ollama    = Get-CodexExecutablePath -Name @('ollama', 'ollama.exe')
    }

    $global:CodexDocumentPipelineConfig = [ordered]@{
        CacheRoot = $cacheRoot
        Defaults  = [ordered]@{
            OcrLanguage          = $defaultOcrLanguage
            TargetLanguage       = $defaultTargetLanguage
            Privacy              = $defaultPrivacy
            AllowCloudForPrivate = $allowCloudForPrivate
            TranslationChunkSize = 2800
            MinExtractedChars    = 24
            ImageProfile         = $defaultImageProfile
            PreprocessImages     = $defaultPreprocessImages
            ScanSampleChars      = $defaultScanSampleChars
        }
        Local     = [ordered]@{
            OllamaModel = Get-CodexDefaultOllamaModel
        }
        Cloud     = [ordered]@{
            OcrSpaceApiKey          = $env:OCR_SPACE_API_KEY
            AzureVisionEndpoint     = $env:AZURE_VISION_ENDPOINT
            AzureVisionKey          = $env:AZURE_VISION_KEY
            LibreTranslateUrl       = $env:LIBRETRANSLATE_URL
            LibreTranslateApiKey    = $env:LIBRETRANSLATE_API_KEY
            AzureTranslatorEndpoint = ''
            AzureTranslatorKey      = $env:AZURE_TRANSLATOR_KEY
            AzureTranslatorRegion   = $env:AZURE_TRANSLATOR_REGION
            DeepLAuthKey            = $env:DEEPL_AUTH_KEY
        }
        Providers = [ordered]@{
            ExtractLocal   = @('pdftotext', 'mutool', 'ocrmypdf', 'tesseract')
            ExtractCloud   = @('ocrspace', 'azurevision')
            TranslateLocal = @('ollama')
            TranslateCloud = @('libretranslate', 'deepl', 'azuretranslator')
        }
        Tools     = $tools
    }

    if (-not [string]::IsNullOrWhiteSpace($env:AZURE_TRANSLATOR_ENDPOINT)) {
        $global:CodexDocumentPipelineConfig.Cloud.AzureTranslatorEndpoint = $env:AZURE_TRANSLATOR_ENDPOINT
    } else {
        $global:CodexDocumentPipelineConfig.Cloud.AzureTranslatorEndpoint = 'https://api.cognitive.microsofttranslator.com'
    }

    New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
    return $global:CodexDocumentPipelineConfig
}

function Get-CodexDocumentPipelineConfig {
    [CmdletBinding()]
    param(
        [switch]$Sanitized
    )

    $config = Initialize-CodexDocumentPipelineConfig
    if (-not $Sanitized) {
        return [pscustomobject]$config
    }

    return [pscustomobject]@{
        CacheRoot = $config.CacheRoot
        Defaults  = [pscustomobject]$config.Defaults
        Local     = [pscustomobject]@{
            OllamaModel = $config.Local.OllamaModel
        }
        Cloud     = [pscustomobject]@{
            OcrSpaceApiKey          = Mask-CodexSecret $config.Cloud.OcrSpaceApiKey
            AzureVisionEndpoint     = $config.Cloud.AzureVisionEndpoint
            AzureVisionKey          = Mask-CodexSecret $config.Cloud.AzureVisionKey
            LibreTranslateUrl       = $config.Cloud.LibreTranslateUrl
            LibreTranslateApiKey    = Mask-CodexSecret $config.Cloud.LibreTranslateApiKey
            AzureTranslatorEndpoint = $config.Cloud.AzureTranslatorEndpoint
            AzureTranslatorKey      = Mask-CodexSecret $config.Cloud.AzureTranslatorKey
            AzureTranslatorRegion   = $config.Cloud.AzureTranslatorRegion
            DeepLAuthKey            = Mask-CodexSecret $config.Cloud.DeepLAuthKey
        }
        Providers = [pscustomobject]$config.Providers
        Tools     = [pscustomobject]$config.Tools
    }
}

function Set-CodexDocumentPipelineConfig {
    [CmdletBinding()]
    param(
        [string]$OcrLanguage,
        [string]$TargetLanguage,
        [ValidateSet('auto', 'screenshot', 'photo', 'scan')]
        [string]$ImageProfile,
        [ValidateSet('private', 'nonprivate')]
        [string]$Privacy,
        [int]$ScanSampleChars,
        [string]$CacheRoot,
        [string]$LibreTranslateUrl,
        [string]$LibreTranslateApiKey,
        [string]$OcrSpaceApiKey,
        [string]$AzureVisionEndpoint,
        [string]$AzureVisionKey,
        [string]$AzureTranslatorEndpoint,
        [string]$AzureTranslatorKey,
        [string]$AzureTranslatorRegion,
        [string]$DeepLAuthKey,
        [string]$OllamaModel,
        [switch]$AllowCloudForPrivate,
        [switch]$DisallowCloudForPrivate,
        [switch]$EnableImagePreprocess,
        [switch]$DisableImagePreprocess,
        [switch]$PersistUserEnvironment,
        [switch]$Show
    )

    $mapping = [ordered]@{}
    if ($PSBoundParameters.ContainsKey('OcrLanguage')) { $mapping['CODEX_DOC_OCR_LANG'] = $OcrLanguage }
    if ($PSBoundParameters.ContainsKey('TargetLanguage')) { $mapping['CODEX_DOC_TARGET_LANG'] = $TargetLanguage }
    if ($PSBoundParameters.ContainsKey('ImageProfile')) { $mapping['CODEX_DOC_IMAGE_PROFILE'] = $ImageProfile }
    if ($PSBoundParameters.ContainsKey('Privacy')) { $mapping['CODEX_DOC_PRIVACY'] = $Privacy }
    if ($PSBoundParameters.ContainsKey('ScanSampleChars')) { $mapping['CODEX_DOC_SCAN_SAMPLE_CHARS'] = $ScanSampleChars.ToString() }
    if ($PSBoundParameters.ContainsKey('CacheRoot')) { $mapping['CODEX_DOC_CACHE_ROOT'] = $CacheRoot }
    if ($PSBoundParameters.ContainsKey('LibreTranslateUrl')) { $mapping['LIBRETRANSLATE_URL'] = $LibreTranslateUrl }
    if ($PSBoundParameters.ContainsKey('LibreTranslateApiKey')) { $mapping['LIBRETRANSLATE_API_KEY'] = $LibreTranslateApiKey }
    if ($PSBoundParameters.ContainsKey('OcrSpaceApiKey')) { $mapping['OCR_SPACE_API_KEY'] = $OcrSpaceApiKey }
    if ($PSBoundParameters.ContainsKey('AzureVisionEndpoint')) { $mapping['AZURE_VISION_ENDPOINT'] = $AzureVisionEndpoint }
    if ($PSBoundParameters.ContainsKey('AzureVisionKey')) { $mapping['AZURE_VISION_KEY'] = $AzureVisionKey }
    if ($PSBoundParameters.ContainsKey('AzureTranslatorEndpoint')) { $mapping['AZURE_TRANSLATOR_ENDPOINT'] = $AzureTranslatorEndpoint }
    if ($PSBoundParameters.ContainsKey('AzureTranslatorKey')) { $mapping['AZURE_TRANSLATOR_KEY'] = $AzureTranslatorKey }
    if ($PSBoundParameters.ContainsKey('AzureTranslatorRegion')) { $mapping['AZURE_TRANSLATOR_REGION'] = $AzureTranslatorRegion }
    if ($PSBoundParameters.ContainsKey('DeepLAuthKey')) { $mapping['DEEPL_AUTH_KEY'] = $DeepLAuthKey }
    if ($PSBoundParameters.ContainsKey('OllamaModel')) { $mapping['CODEX_OLLAMA_TRANSLATE_MODEL'] = $OllamaModel }
    if ($AllowCloudForPrivate.IsPresent) { $mapping['CODEX_DOC_ALLOW_CLOUD_PRIVATE'] = '1' }
    if ($DisallowCloudForPrivate.IsPresent) { $mapping['CODEX_DOC_ALLOW_CLOUD_PRIVATE'] = '0' }
    if ($EnableImagePreprocess.IsPresent) { $mapping['CODEX_DOC_PREPROCESS_IMAGES'] = '1' }
    if ($DisableImagePreprocess.IsPresent) { $mapping['CODEX_DOC_PREPROCESS_IMAGES'] = '0' }

    foreach ($entry in $mapping.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
        Set-Item -Path ("Env:{0}" -f $entry.Key) -Value $entry.Value
        if ($PersistUserEnvironment) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'User')
        }
    }

    Initialize-CodexDocumentPipelineConfig | Out-Null
    if ($Show -or $mapping.Count -eq 0) {
        return Get-CodexDocumentPipelineConfig -Sanitized
    }

    return [pscustomobject]@{
        UpdatedKeys = @($mapping.Keys)
        Persisted   = $PersistUserEnvironment.IsPresent
        Config      = Get-CodexDocumentPipelineConfig -Sanitized
    }
}

function Resolve-CodexDocumentOutputDirectory {
    [CmdletBinding()]
    param(
        [string]$InputPath,
        [string]$OutputDir
    )

    if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
        New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
        return (Resolve-Path -LiteralPath $OutputDir).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($InputPath) -and (Test-Path -LiteralPath $InputPath)) {
        $item = Get-Item -LiteralPath $InputPath -ErrorAction Stop
        $resolved = Join-Path $item.DirectoryName ($item.BaseName + '_codex')
        New-Item -ItemType Directory -Force -Path $resolved | Out-Null
        return $resolved
    }

    $fallback = Join-Path (Get-Location).Path 'codex_doc'
    New-Item -ItemType Directory -Force -Path $fallback | Out-Null
    return $fallback
}

function Get-CodexDocumentFileKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($extension) {
        '.pdf' { return 'pdf' }
        '.png' { return 'image' }
        '.jpg' { return 'image' }
        '.jpeg' { return 'image' }
        '.bmp' { return 'image' }
        '.gif' { return 'image' }
        '.tif' { return 'image' }
        '.tiff' { return 'image' }
        '.webp' { return 'image' }
        '.txt' { return 'text' }
        '.md' { return 'text' }
        '.csv' { return 'text' }
        '.json' { return 'text' }
        '.yaml' { return 'text' }
        '.yml' { return 'text' }
        '.html' { return 'html' }
        '.htm' { return 'html' }
        '.mhtml' { return 'html' }
        '.mht' { return 'html' }
        '.docx' { return 'docx' }
        '.pptx' { return 'pptx' }
        '.epub' { return 'epub' }
        default { return 'unknown' }
    }
}

function Get-CodexArtifactStem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $item = Get-Item -LiteralPath $InputPath -ErrorAction Stop
    $extension = $item.Extension.TrimStart('.').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($extension)) {
        return $item.BaseName
    }

    return ('{0}.{1}' -f $item.BaseName, $extension)
}

function Split-CodexTextChunks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [int]$MaxChars = 2800
    )

    $clean = ($Text -replace "`r", '').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return @()
    }

    $paragraphs = $clean -split "`n{2,}"
    $chunks = New-Object System.Collections.Generic.List[string]
    $buffer = New-Object System.Text.StringBuilder

    foreach ($paragraph in $paragraphs) {
        $segment = $paragraph.Trim()
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }

        if (($buffer.Length + $segment.Length + 2) -le $MaxChars) {
            if ($buffer.Length -gt 0) {
                [void]$buffer.Append("`n`n")
            }
            [void]$buffer.Append($segment)
            continue
        }

        if ($buffer.Length -gt 0) {
            [void]$chunks.Add($buffer.ToString())
            $buffer.Clear() | Out-Null
        }

        if ($segment.Length -le $MaxChars) {
            [void]$buffer.Append($segment)
            continue
        }

        $sentences = $segment -split '(?<=[\.!\?])\s+'
        $local = New-Object System.Text.StringBuilder
        foreach ($sentence in $sentences) {
            $piece = $sentence.Trim()
            if ([string]::IsNullOrWhiteSpace($piece)) {
                continue
            }

            if (($local.Length + $piece.Length + 1) -gt $MaxChars -and $local.Length -gt 0) {
                [void]$chunks.Add($local.ToString())
                $local.Clear() | Out-Null
            }

            if ($piece.Length -gt $MaxChars) {
                for ($index = 0; $index -lt $piece.Length; $index += $MaxChars) {
                    $length = [Math]::Min($MaxChars, $piece.Length - $index)
                    [void]$chunks.Add($piece.Substring($index, $length))
                }
                continue
            }

            if ($local.Length -gt 0) {
                [void]$local.Append(' ')
            }
            [void]$local.Append($piece)
        }

        if ($local.Length -gt 0) {
            [void]$chunks.Add($local.ToString())
        }
    }

    if ($buffer.Length -gt 0) {
        [void]$chunks.Add($buffer.ToString())
    }

    return @($chunks.ToArray())
}

function ConvertTo-CodexOcrSpaceLanguage {
    [CmdletBinding()]
    param(
        [string]$Language
    )

    $lang = [string]$Language
    if ($null -eq $lang) {
        $lang = ''
    }
    $lang = $lang.ToLowerInvariant()
    if ($lang -match 'chi_sim|chs|zh') { return 'chs' }
    if ($lang -match 'chi_tra|cht') { return 'cht' }
    if ($lang -match 'jpn|ja') { return 'jpn' }
    if ($lang -match 'kor|ko') { return 'kor' }
    return 'eng'
}

function Get-CodexAzureVisionUri {
    [CmdletBinding()]
    param(
        [string]$Endpoint
    )

    $base = $Endpoint.TrimEnd('/')
    return "$base/computervision/imageanalysis:analyze?api-version=2024-02-01&features=read"
}

function Read-CodexTextArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
}

function Normalize-CodexExtractedText {
    [CmdletBinding()]
    param(
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    $normalized = $Text -replace "`r", ''
    $normalized = $normalized -replace "[\u00A0\u200B\uFEFF]", ' '
    $lines = $normalized -split "`n"
    $result = New-Object System.Collections.Generic.List[string]
    $previousBlank = $false
    foreach ($line in $lines) {
        $trimmed = $line.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            if (-not $previousBlank) {
                [void]$result.Add('')
                $previousBlank = $true
            }
            continue
        }

        [void]$result.Add($trimmed.Trim())
        $previousBlank = $false
    }

    return ([string]::Join("`n", @($result.ToArray()))).Trim()
}

function ConvertFrom-CodexMarkupToText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Markup
    )

    $text = $Markup
    $text = $text -replace '(?is)<script\b[^>]*>.*?</script>', ' '
    $text = $text -replace '(?is)<style\b[^>]*>.*?</style>', ' '
    $text = $text -replace '(?is)<br\b[^>]*>', "`n"
    $text = $text -replace '(?is)</(p|div|section|article|tr|table|ul|ol|blockquote|h[1-6])\s*>', "`n`n"
    $text = $text -replace '(?is)</(li|td|th)\s*>', "`n"
    $text = $text -replace '(?is)<li\b[^>]*>', '* '
    $text = $text -replace '(?is)<[^>]+>', ' '
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    return Normalize-CodexExtractedText -Text $text
}

function Read-CodexZipEntryText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchiveEntry]$Entry
    )

    $stream = $Entry.Open()
    try {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        try {
            return $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Invoke-CodexDocxTextExtraction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue | Out-Null
    $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $InputPath).Path)
    try {
        $entries = @(
            $archive.Entries |
                Where-Object {
                    $_.FullName -match '^word/(document|header\d+|footer\d+|footnotes|endnotes|comments)\.xml$'
                } |
                Sort-Object FullName
        )

        $segments = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $entries) {
            $xml = Read-CodexZipEntryText -Entry $entry
            $text = $xml
            $text = $text -replace '(?s)<w:tab[^>]*/>', "`t"
            $text = $text -replace '(?s)<w:(br|cr)[^>]*/>', "`n"
            $text = $text -replace '(?s)</w:p>', "`n`n"
            $text = $text -replace '(?s)</w:tr>', "`n"
            $text = $text -replace '(?s)</w:tc>', "`t"
            $text = $text -replace '(?s)<[^>]+>', ''
            $text = [System.Net.WebUtility]::HtmlDecode($text)
            $normalized = Normalize-CodexExtractedText -Text $text
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                [void]$segments.Add($normalized)
            }
        }

        return [pscustomobject]@{
            Provider = 'docx'
            Method   = 'native_openxml_word'
            Text     = ([string]::Join("`n`n", @($segments.ToArray()))).Trim()
        }
    } finally {
        $archive.Dispose()
    }
}

function Invoke-CodexPptxTextExtraction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue | Out-Null
    $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $InputPath).Path)
    try {
        $entries = @(
            $archive.Entries |
                Where-Object {
                    $_.FullName -match '^ppt/(slides/slide\d+|notesSlides/notesSlide\d+)\.xml$'
                } |
                Sort-Object FullName
        )

        $segments = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $entries) {
            $xml = Read-CodexZipEntryText -Entry $entry
            $text = $xml
            $text = $text -replace '(?s)<a:br\s*/>', "`n"
            $text = $text -replace '(?s)</a:p>', "`n`n"
            $text = $text -replace '(?s)<[^>]+>', ''
            $text = [System.Net.WebUtility]::HtmlDecode($text)
            $normalized = Normalize-CodexExtractedText -Text $text
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                [void]$segments.Add($normalized)
            }
        }

        return [pscustomobject]@{
            Provider = 'pptx'
            Method   = 'native_openxml_presentation'
            Text     = ([string]::Join("`n`n", @($segments.ToArray()))).Trim()
        }
    } finally {
        $archive.Dispose()
    }
}

function Invoke-CodexEpubTextExtraction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue | Out-Null
    $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $InputPath).Path)
    try {
        $entries = @(
            $archive.Entries |
                Where-Object {
                    $_.FullName -notmatch '^META-INF/' -and $_.FullName -match '\.(xhtml|html|htm)$'
                } |
                Sort-Object FullName
        )

        $segments = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $entries) {
            $markup = Read-CodexZipEntryText -Entry $entry
            $normalized = ConvertFrom-CodexMarkupToText -Markup $markup
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                [void]$segments.Add($normalized)
            }
        }

        return [pscustomobject]@{
            Provider = 'epub'
            Method   = 'native_epub_markup'
            Text     = ([string]::Join("`n`n", @($segments.ToArray()))).Trim()
        }
    } finally {
        $archive.Dispose()
    }
}

function Invoke-CodexHtmlTextExtraction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $markup = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8
    return [pscustomobject]@{
        Provider = 'html'
        Method   = 'native_markup'
        Text     = (ConvertFrom-CodexMarkupToText -Markup $markup)
    }
}

function Get-CodexImageGeometry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $tool = $config.Tools.magick
    if ([string]::IsNullOrWhiteSpace($tool)) {
        return $null
    }

    $output = & $tool 'identify' '-ping' '-format' '%w %h' $InputPath 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $output) {
        return $null
    }

    $text = ([string]::Join('', @($output))).Trim()
    if ($text -notmatch '^(?<w>\d+)\s+(?<h>\d+)$') {
        return $null
    }

    return [pscustomobject]@{
        Width  = [int]$Matches.w
        Height = [int]$Matches.h
        Ratio  = [math]::Round(([int]$Matches.w / [math]::Max([int]$Matches.h, 1)), 3)
    }
}

function Get-CodexImageProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$PreferredProfile
    )

    if (-not [string]::IsNullOrWhiteSpace($PreferredProfile) -and $PreferredProfile -ne 'auto') {
        return $PreferredProfile
    }

    $leaf = [System.IO.Path]::GetFileName($InputPath).ToLowerInvariant()
    if ($leaf -match 'screenshot|screen|snip|capture') {
        return 'screenshot'
    }
    if ($leaf -match 'lecture|notes|handwritten|whiteboard|board|photo|camera|img_|scan') {
        if ($leaf -match 'scan') {
            return 'scan'
        }
        return 'photo'
    }

    $geometry = Get-CodexImageGeometry -InputPath $InputPath
    if ($null -ne $geometry) {
        if ($geometry.Width -ge 1400 -and $geometry.Ratio -ge 1.45 -and $geometry.Ratio -le 2.4) {
            return 'screenshot'
        }
        if ($geometry.Ratio -lt 1.1) {
            return 'photo'
        }
    }

    $extension = [System.IO.Path]::GetExtension($InputPath).ToLowerInvariant()
    if ($extension -in @('.tif', '.tiff', '.bmp')) {
        return 'scan'
    }

    return 'photo'
}

function Invoke-CodexImagePreprocess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$ImageProfile
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $tool = $config.Tools.magick
    $resolvedProfile = Get-CodexImageProfile -InputPath $InputPath -PreferredProfile $ImageProfile
    if ([string]::IsNullOrWhiteSpace($tool) -or -not [bool]$config.Defaults.PreprocessImages) {
        return [pscustomobject]@{
            Path          = $InputPath
            ImageProfile  = $resolvedProfile
            Preprocessed  = $false
            TempPath      = $null
        }
    }

    $tempPath = Join-Path $config.CacheRoot ("{0}_preprocessed.png" -f ([System.Guid]::NewGuid().ToString('n')))
    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add($InputPath)
    [void]$arguments.Add('-auto-orient')
    [void]$arguments.Add('-strip')

    switch ($resolvedProfile) {
        'screenshot' {
            foreach ($arg in @('-colorspace', 'Gray', '-deskew', '40%', '-contrast-stretch', '0.5%x0.5%', '-sharpen', '0x1.0', '-resize', '175%')) {
                [void]$arguments.Add($arg)
            }
        }
        'scan' {
            foreach ($arg in @('-colorspace', 'Gray', '-deskew', '35%', '-contrast-stretch', '0.8%x0.8%', '-sharpen', '0x1.1', '-resize', '190%')) {
                [void]$arguments.Add($arg)
            }
        }
        default {
            foreach ($arg in @('-colorspace', 'Gray', '-deskew', '25%', '-auto-level', '-contrast-stretch', '1%x1%', '-adaptive-sharpen', '0x1.4', '-resize', '220%')) {
                [void]$arguments.Add($arg)
            }
        }
    }
    [void]$arguments.Add($tempPath)

    & $tool @arguments 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
        return [pscustomobject]@{
            Path          = $InputPath
            ImageProfile  = $resolvedProfile
            Preprocessed  = $false
            TempPath      = $null
        }
    }

    return [pscustomobject]@{
        Path          = $tempPath
        ImageProfile  = $resolvedProfile
        Preprocessed  = $true
        TempPath      = $tempPath
    }
}

function Get-CodexTextTranslationAssessment {
    [CmdletBinding()]
    param(
        [string]$Text,
        [string]$TargetLanguage
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [pscustomobject]@{
            NeedsTranslation = $false
            Reason           = 'no_text'
            SampleLength     = 0
            LatinLetters     = 0
            CjkCharacters    = 0
        }
    }

    $sample = $Text
    if ($sample.Length -gt 2200) {
        $sample = $sample.Substring(0, 2200)
    }
    $sample = Normalize-CodexExtractedText -Text $sample
    $latinLetters = ([regex]::Matches($sample, '[A-Za-z]')).Count
    $cjkCharacters = ([regex]::Matches($sample, '[\p{IsCJKUnifiedIdeographs}\p{IsHiragana}\p{IsKatakana}\p{IsHangulSyllables}]')).Count
    $letterCount = ([regex]::Matches($sample, '\p{L}')).Count
    $language = ''
    if ($null -ne $TargetLanguage) {
        $language = $TargetLanguage.ToLowerInvariant()
    }

    $needsTranslation = $false
    $reason = 'already_target_like'
    switch ($language) {
        'zh' {
            if ($cjkCharacters -ge [Math]::Max(12, [int]($letterCount * 0.25))) {
                $needsTranslation = $false
                $reason = 'already_cjk_heavy'
            } elseif ($latinLetters -ge 20) {
                $needsTranslation = $true
                $reason = 'latin_heavy_text'
            } else {
                $needsTranslation = $false
                $reason = 'insufficient_signal'
            }
        }
        'en' {
            if ($latinLetters -ge [Math]::Max(20, [int]($letterCount * 0.45))) {
                $needsTranslation = $false
                $reason = 'already_latin_heavy'
            } elseif ($cjkCharacters -ge 8) {
                $needsTranslation = $true
                $reason = 'cjk_heavy_text'
            } else {
                $needsTranslation = $false
                $reason = 'insufficient_signal'
            }
        }
        default {
            if ($letterCount -ge 20) {
                $needsTranslation = $true
                $reason = 'target_not_detected'
            } else {
                $needsTranslation = $false
                $reason = 'insufficient_signal'
            }
        }
    }

    return [pscustomobject]@{
        NeedsTranslation = $needsTranslation
        Reason           = $reason
        SampleLength     = $sample.Length
        LatinLetters     = $latinLetters
        CjkCharacters    = $cjkCharacters
    }
}

function Invoke-CodexPdfTextExtractionWithPdftotext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $tool = $config.Tools.pdftotext
    if ([string]::IsNullOrWhiteSpace($tool)) {
        throw 'pdftotext is not available.'
    }

    $tempPath = Join-Path $config.CacheRoot ("{0}_pdftotext.txt" -f ([System.Guid]::NewGuid().ToString('n')))
    & $tool '-q' '-enc' 'UTF-8' '-nopgbrk' $InputPath $tempPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "pdftotext failed with exit code $LASTEXITCODE"
    }

    if (Test-Path -LiteralPath $tempPath) {
        $text = Read-CodexTextArtifact -Path $tempPath
    } else {
        $text = ''
    }
    return [pscustomobject]@{
        Provider = 'pdftotext'
        Method   = 'native_pdf_text'
        Text     = $text
        TempPath = $tempPath
    }
}

function Invoke-CodexPdfTextExtractionWithMutool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $tool = $config.Tools.mutool
    if ([string]::IsNullOrWhiteSpace($tool)) {
        throw 'mutool is not available.'
    }

    $tempPath = Join-Path $config.CacheRoot ("{0}_mutool.txt" -f ([System.Guid]::NewGuid().ToString('n')))
    & $tool 'draw' '-q' '-F' 'txt' '-o' $tempPath $InputPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "mutool draw failed with exit code $LASTEXITCODE"
    }

    if (Test-Path -LiteralPath $tempPath) {
        $text = Read-CodexTextArtifact -Path $tempPath
    } else {
        $text = ''
    }
    return [pscustomobject]@{
        Provider = 'mutool'
        Method   = 'native_pdf_text'
        Text     = $text
        TempPath = $tempPath
    }
}

function Invoke-CodexPdfOcrLocal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Language,

        [switch]$ForceOcr
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $tool = $config.Tools.ocrmypdf
    if ([string]::IsNullOrWhiteSpace($tool)) {
        throw 'ocrmypdf is not available.'
    }

    $stamp = [System.Guid]::NewGuid().ToString('n')
    $sidecarPath = Join-Path $config.CacheRoot ("{0}_ocr.txt" -f $stamp)
    $outputPdfPath = Join-Path $config.CacheRoot ("{0}_ocr.pdf" -f $stamp)
    $jobCount = [Math]::Max([Environment]::ProcessorCount - 1, 1)
    if ([string]::IsNullOrWhiteSpace($Language)) {
        $ocrLanguage = $config.Defaults.OcrLanguage
    } else {
        $ocrLanguage = $Language
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add('--skip-text')
    [void]$arguments.Add('--sidecar')
    [void]$arguments.Add($sidecarPath)
    [void]$arguments.Add('--output-type')
    [void]$arguments.Add('none')
    [void]$arguments.Add('-j')
    [void]$arguments.Add($jobCount.ToString())
    [void]$arguments.Add('-l')
    [void]$arguments.Add($ocrLanguage)
    [void]$arguments.Add('--tesseract-timeout')
    [void]$arguments.Add('120')
    if ($ForceOcr) {
        [void]$arguments.Add('-f')
    }
    [void]$arguments.Add($InputPath)
    [void]$arguments.Add($outputPdfPath)

    & $tool @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ocrmypdf failed with exit code $LASTEXITCODE"
    }

    if (Test-Path -LiteralPath $sidecarPath) {
        $text = Read-CodexTextArtifact -Path $sidecarPath
    } else {
        $text = ''
    }
    return [pscustomobject]@{
        Provider   = 'ocrmypdf'
        Method     = 'local_ocr_pdf'
        Text       = $text
        TempPath   = $sidecarPath
        OutputPath = $outputPdfPath
    }
}

function Invoke-CodexImageOcrLocal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Language,

        [string]$ImageProfile
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $tool = $config.Tools.tesseract
    if ([string]::IsNullOrWhiteSpace($tool)) {
        throw 'tesseract is not available.'
    }

    if ([string]::IsNullOrWhiteSpace($Language)) {
        $ocrLanguage = $config.Defaults.OcrLanguage
    } else {
        $ocrLanguage = $Language
    }

    $preparedImage = Invoke-CodexImagePreprocess -InputPath $InputPath -ImageProfile $ImageProfile
    $pageSegMode = '6'
    if ($preparedImage.ImageProfile -eq 'photo') {
        $pageSegMode = '11'
    }

    $output = & $tool $preparedImage.Path 'stdout' '-l' $ocrLanguage '--psm' $pageSegMode 'quiet'
    if ($LASTEXITCODE -ne 0) {
        throw "tesseract failed with exit code $LASTEXITCODE"
    }

    $text = [string]::Join([Environment]::NewLine, @($output))
    return [pscustomobject]@{
        Provider         = 'tesseract'
        Method           = 'local_ocr_image'
        Text             = $text
        ImageProfile     = $preparedImage.ImageProfile
        PreprocessedPath = $preparedImage.TempPath
    }
}

function Invoke-CodexOcrSpaceExtract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Language
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $apiKey = $config.Cloud.OcrSpaceApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'OCR.space API key is not configured.'
    }

    $form = @{
        apikey            = $apiKey
        language          = (ConvertTo-CodexOcrSpaceLanguage -Language $Language)
        OCREngine         = '2'
        file              = Get-Item -LiteralPath $InputPath -ErrorAction Stop
        scale             = 'true'
        isOverlayRequired = 'false'
        detectOrientation = 'true'
    }

    $response = Invoke-RestMethod -Uri 'https://api.ocr.space/parse/image' -Method Post -Form $form -ErrorAction Stop
    if ($response.IsErroredOnProcessing) {
        if ($response.ErrorMessage) {
            $message = [string]::Join('; ', @($response.ErrorMessage))
        } else {
            $message = 'Unknown OCR.space error.'
        }
        throw $message
    }

    $text = [string]::Join("`n", @($response.ParsedResults | ForEach-Object { $_.ParsedText }))
    return [pscustomobject]@{
        Provider = 'ocrspace'
        Method   = 'cloud_ocr'
        Text     = $text
    }
}

function Invoke-CodexAzureVisionExtract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $config = Initialize-CodexDocumentPipelineConfig
    if ([string]::IsNullOrWhiteSpace($config.Cloud.AzureVisionEndpoint) -or [string]::IsNullOrWhiteSpace($config.Cloud.AzureVisionKey)) {
        throw 'Azure Vision endpoint/key is not configured.'
    }

    $uri = Get-CodexAzureVisionUri -Endpoint $config.Cloud.AzureVisionEndpoint
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $InputPath).Path)
    $headers = @{
        'Ocp-Apim-Subscription-Key' = $config.Cloud.AzureVisionKey
        'Content-Type'              = 'application/octet-stream'
    }

    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $bytes -ErrorAction Stop
    $text = ''
    if ($null -ne $response.readResult -and $null -ne $response.readResult.content) {
        $text = [string]$response.readResult.content
    }
    if ([string]::IsNullOrWhiteSpace($text) -and $null -ne $response.captionResult -and $null -ne $response.captionResult.text) {
        $text = [string]$response.captionResult.text
    }

    return [pscustomobject]@{
        Provider = 'azurevision'
        Method   = 'cloud_ocr'
        Text     = $text
    }
}

function Invoke-CodexLocalTextExtraction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Language,

        [string]$ImageProfile,

        [switch]$ForceOcr
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $minChars = [int]$config.Defaults.MinExtractedChars
    $kind = Get-CodexDocumentFileKind -Path $InputPath

    if ($kind -eq 'text') {
        return [pscustomobject]@{
            Provider = 'filesystem'
            Method   = 'native_text'
            Text     = Read-CodexTextArtifact -Path $InputPath
        }
    }

    if ($kind -eq 'html') {
        return Invoke-CodexHtmlTextExtraction -InputPath $InputPath
    }

    if ($kind -eq 'docx') {
        return Invoke-CodexDocxTextExtraction -InputPath $InputPath
    }

    if ($kind -eq 'pptx') {
        return Invoke-CodexPptxTextExtraction -InputPath $InputPath
    }

    if ($kind -eq 'epub') {
        return Invoke-CodexEpubTextExtraction -InputPath $InputPath
    }

    if ($kind -eq 'pdf') {
        if (-not $ForceOcr) {
            foreach ($provider in @('pdftotext', 'mutool')) {
                try {
                    if ($provider -eq 'pdftotext') {
                        $result = Invoke-CodexPdfTextExtractionWithPdftotext -InputPath $InputPath
                    } else {
                        $result = Invoke-CodexPdfTextExtractionWithMutool -InputPath $InputPath
                    }

                    if (-not [string]::IsNullOrWhiteSpace($result.Text) -and $result.Text.Trim().Length -ge $minChars) {
                        return $result
                    }
                } catch {
                }
            }
        }

        return Invoke-CodexPdfOcrLocal -InputPath $InputPath -Language $Language -ForceOcr:$ForceOcr
    }

    if ($kind -eq 'image') {
        return Invoke-CodexImageOcrLocal -InputPath $InputPath -Language $Language -ImageProfile $ImageProfile
    }

    throw "Unsupported file type for local extraction: $InputPath"
}

function Test-CodexCloudAllowed {
    [CmdletBinding()]
    param(
        [ValidateSet('private', 'nonprivate')]
        [string]$Privacy = 'private',

        [switch]$CloudFallback
    )

    $config = Initialize-CodexDocumentPipelineConfig
    if (-not $CloudFallback) {
        return $false
    }

    if ($Privacy -eq 'nonprivate') {
        return $true
    }

    return [bool]$config.Defaults.AllowCloudForPrivate
}

function Invoke-CodexCloudTextExtraction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$Language
    )

    $config = Initialize-CodexDocumentPipelineConfig
    foreach ($provider in $config.Providers.ExtractCloud) {
        try {
            switch ($provider) {
                'ocrspace' {
                    $result = Invoke-CodexOcrSpaceExtract -InputPath $InputPath -Language $Language
                    if (-not [string]::IsNullOrWhiteSpace($result.Text)) { return $result }
                }
                'azurevision' {
                    $result = Invoke-CodexAzureVisionExtract -InputPath $InputPath
                    if (-not [string]::IsNullOrWhiteSpace($result.Text)) { return $result }
                }
            }
        } catch {
        }
    }

    throw 'No configured cloud OCR provider succeeded.'
}

function Write-CodexTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
    return $Path
}

function Invoke-CodexOcrSmart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [string]$OutputDir,

        [string]$Language,

        [ValidateSet('auto', 'screenshot', 'photo', 'scan')]
        [string]$ImageProfile,

        [ValidateSet('private', 'nonprivate')]
        [string]$Privacy,

        [switch]$CloudFallback,

        [switch]$ForceOcr
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Input path not found: $InputPath"
    }

    $config = Initialize-CodexDocumentPipelineConfig
    if ([string]::IsNullOrWhiteSpace($Privacy)) {
        $resolvedPrivacy = [string]$config.Defaults.Privacy
    } else {
        $resolvedPrivacy = $Privacy
    }

    if ([string]::IsNullOrWhiteSpace($Language)) {
        $ocrLanguage = [string]$config.Defaults.OcrLanguage
    } else {
        $ocrLanguage = $Language
    }
    if ([string]::IsNullOrWhiteSpace($ImageProfile)) {
        $resolvedImageProfile = [string]$config.Defaults.ImageProfile
    } else {
        $resolvedImageProfile = $ImageProfile
    }
    $outputRoot = Resolve-CodexDocumentOutputDirectory -InputPath $InputPath -OutputDir $OutputDir
    $item = Get-Item -LiteralPath $InputPath -ErrorAction Stop
    $artifactStem = Get-CodexArtifactStem -InputPath $item.FullName
    $outputTextPath = Join-Path $outputRoot ($artifactStem + '.txt')
    $manifestPath = Join-Path $outputRoot ($artifactStem + '.ocr_manifest.json')

    $errors = New-Object System.Collections.Generic.List[string]
    $result = $null

    try {
        $result = Invoke-CodexLocalTextExtraction -InputPath $item.FullName -Language $ocrLanguage -ImageProfile $resolvedImageProfile -ForceOcr:$ForceOcr
    } catch {
        [void]$errors.Add($_.Exception.Message)
    }

    if (($null -eq $result -or [string]::IsNullOrWhiteSpace($result.Text)) -and (Test-CodexCloudAllowed -Privacy $resolvedPrivacy -CloudFallback:$CloudFallback)) {
        try {
            $result = Invoke-CodexCloudTextExtraction -InputPath $item.FullName -Language $ocrLanguage
        } catch {
            [void]$errors.Add($_.Exception.Message)
        }
    }

    if ($null -eq $result -or [string]::IsNullOrWhiteSpace($result.Text)) {
        throw ("Text extraction failed. " + ([string]::Join(' | ', @($errors.ToArray()))))
    }

    Write-CodexTextFile -Path $outputTextPath -Text $result.Text | Out-Null

    $manifest = [pscustomobject]@{
        InputPath      = $item.FullName
        OutputTextPath = $outputTextPath
        Provider       = $result.Provider
        Method         = $result.Method
        Privacy        = $resolvedPrivacy
        CloudFallback  = $CloudFallback.IsPresent
        ForceOcr       = $ForceOcr.IsPresent
        Language       = $ocrLanguage
        ImageProfile   = $result.ImageProfile
        TextLength     = $result.Text.Length
        Errors         = @($errors.ToArray())
        TempPath       = $result.TempPath
        OutputPath     = $result.OutputPath
        PreprocessedPath = $result.PreprocessedPath
    }

    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $manifest
}

function Invoke-CodexPdfSmart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [string]$OutputDir,

        [string]$Language,

        [ValidateSet('auto', 'screenshot', 'photo', 'scan')]
        [string]$ImageProfile,

        [ValidateSet('private', 'nonprivate')]
        [string]$Privacy,

        [switch]$CloudFallback,

        [switch]$ForceOcr
    )

    if ((Get-CodexDocumentFileKind -Path $InputPath) -ne 'pdf') {
        throw "pdf-smart only accepts PDF files: $InputPath"
    }

    $invokeParams = @{
        InputPath = $InputPath
    }
    if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
        $invokeParams.OutputDir = $OutputDir
    }
    if (-not [string]::IsNullOrWhiteSpace($Language)) {
        $invokeParams.Language = $Language
    }
    if (-not [string]::IsNullOrWhiteSpace($ImageProfile)) {
        $invokeParams.ImageProfile = $ImageProfile
    }
    if (-not [string]::IsNullOrWhiteSpace($Privacy)) {
        $invokeParams.Privacy = $Privacy
    }
    if ($CloudFallback) {
        $invokeParams.CloudFallback = $true
    }
    if ($ForceOcr) {
        $invokeParams.ForceOcr = $true
    }

    Invoke-CodexOcrSmart @invokeParams
}

function Invoke-CodexOllamaTranslateChunk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$SourceLanguage,

        [Parameter(Mandatory = $true)]
        [string]$TargetLanguage
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $tool = $config.Tools.ollama
    $model = $config.Local.OllamaModel
    if ([string]::IsNullOrWhiteSpace($tool) -or [string]::IsNullOrWhiteSpace($model)) {
        throw 'No Ollama executable/model is configured.'
    }

    if ([string]::IsNullOrWhiteSpace($SourceLanguage) -or $SourceLanguage -eq 'auto') {
        $sourceLabel = 'the source language'
    } else {
        $sourceLabel = $SourceLanguage
    }
    $prompt = @"
You are a translation engine.
Translate the following text from $sourceLabel to $TargetLanguage.
Preserve paragraph breaks, bullet markers, equations, and code blocks.
Return only the translated text.

$Text
"@

    $output = $prompt | & $tool 'run' $model 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "ollama run failed with exit code $LASTEXITCODE"
    }

    return ([string]::Join([Environment]::NewLine, @($output))).Trim()
}

function Invoke-CodexLibreTranslateChunk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$SourceLanguage,

        [Parameter(Mandatory = $true)]
        [string]$TargetLanguage
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $url = $config.Cloud.LibreTranslateUrl
    if ([string]::IsNullOrWhiteSpace($url)) {
        throw 'LibreTranslate URL is not configured.'
    }

    $body = @{
        q      = $Text
        source = 'auto'
        target = $TargetLanguage
        format = 'text'
    }
    if (-not [string]::IsNullOrWhiteSpace($SourceLanguage)) {
        $body.source = $SourceLanguage
    }
    if (-not [string]::IsNullOrWhiteSpace($config.Cloud.LibreTranslateApiKey)) {
        $body.api_key = $config.Cloud.LibreTranslateApiKey
    }

    $response = Invoke-RestMethod -Uri ($url.TrimEnd('/') + '/translate') -Method Post -Body $body -ErrorAction Stop
    return [string]$response.translatedText
}

function ConvertTo-CodexDeepLTargetLanguage {
    param(
        [string]$Language
    )

    switch ($Language.ToLowerInvariant()) {
        'zh' { return 'ZH' }
        'en' { return 'EN' }
        'pt' { return 'PT-PT' }
        default { return $Language.ToUpperInvariant() }
    }
}

function Invoke-CodexDeepLTranslateChunk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$SourceLanguage,

        [Parameter(Mandatory = $true)]
        [string]$TargetLanguage
    )

    $config = Initialize-CodexDocumentPipelineConfig
    if ([string]::IsNullOrWhiteSpace($config.Cloud.DeepLAuthKey)) {
        throw 'DeepL auth key is not configured.'
    }

    $body = @{
        text        = $Text
        target_lang = (ConvertTo-CodexDeepLTargetLanguage -Language $TargetLanguage)
    }
    if (-not [string]::IsNullOrWhiteSpace($SourceLanguage) -and $SourceLanguage -ne 'auto') {
        $body.source_lang = $SourceLanguage.ToUpperInvariant()
    }

    $headers = @{
        Authorization = "DeepL-Auth-Key $($config.Cloud.DeepLAuthKey)"
    }

    $response = Invoke-RestMethod -Uri 'https://api-free.deepl.com/v2/translate' -Method Post -Headers $headers -Body $body -ErrorAction Stop
    return [string]$response.translations[0].text
}

function Invoke-CodexAzureTranslateChunk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$SourceLanguage,

        [Parameter(Mandatory = $true)]
        [string]$TargetLanguage
    )

    $config = Initialize-CodexDocumentPipelineConfig
    if ([string]::IsNullOrWhiteSpace($config.Cloud.AzureTranslatorKey)) {
        throw 'Azure Translator key is not configured.'
    }

    $endpoint = $config.Cloud.AzureTranslatorEndpoint.TrimEnd('/')
    $uri = "$endpoint/translate?api-version=3.0&to=$TargetLanguage"
    if (-not [string]::IsNullOrWhiteSpace($SourceLanguage) -and $SourceLanguage -ne 'auto') {
        $uri += "&from=$SourceLanguage"
    }

    $headers = @{
        'Ocp-Apim-Subscription-Key' = $config.Cloud.AzureTranslatorKey
        'Content-Type'              = 'application/json; charset=UTF-8'
    }
    if (-not [string]::IsNullOrWhiteSpace($config.Cloud.AzureTranslatorRegion)) {
        $headers['Ocp-Apim-Subscription-Region'] = $config.Cloud.AzureTranslatorRegion
    }

    $body = @(@{ Text = $Text }) | ConvertTo-Json -Depth 4
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
    return [string]$response[0].translations[0].text
}

function Invoke-CodexTranslationProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$SourceLanguage,

        [Parameter(Mandatory = $true)]
        [string]$TargetLanguage
    )

    switch ($Provider) {
        'ollama' { return Invoke-CodexOllamaTranslateChunk -Text $Text -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage }
        'libretranslate' { return Invoke-CodexLibreTranslateChunk -Text $Text -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage }
        'deepl' { return Invoke-CodexDeepLTranslateChunk -Text $Text -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage }
        'azuretranslator' { return Invoke-CodexAzureTranslateChunk -Text $Text -SourceLanguage $SourceLanguage -TargetLanguage $TargetLanguage }
        default { throw "Unknown translation provider: $Provider" }
    }
}

function Invoke-CodexTranslateSmart {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [Parameter(ParameterSetName = 'Text', Mandatory = $true)]
        [string]$Text,

        [string]$OutputDir,

        [string]$SourceLanguage = 'auto',

        [string]$TargetLanguage,

        [ValidateSet('auto', 'screenshot', 'photo', 'scan')]
        [string]$ImageProfile,

        [ValidateSet('private', 'nonprivate')]
        [string]$Privacy,

        [switch]$CloudFallback,

        [string[]]$ProviderOrder
    )

    $config = Initialize-CodexDocumentPipelineConfig
    if ([string]::IsNullOrWhiteSpace($Privacy)) {
        $resolvedPrivacy = [string]$config.Defaults.Privacy
    } else {
        $resolvedPrivacy = $Privacy
    }
    if ([string]::IsNullOrWhiteSpace($TargetLanguage)) {
        $resolvedTarget = [string]$config.Defaults.TargetLanguage
    } else {
        $resolvedTarget = $TargetLanguage
    }
    $inputText = ''
    $sourcePath = ''
    $outputRoot = $null
    $translationStem = ''

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $InputPath)) {
            throw "Input path not found: $InputPath"
        }

        $item = Get-Item -LiteralPath $InputPath -ErrorAction Stop
        $sourcePath = $item.FullName
        $inputKind = Get-CodexDocumentFileKind -Path $item.FullName
        if ($inputKind -eq 'text') {
            $translationStem = $item.BaseName
            $inputText = Read-CodexTextArtifact -Path $item.FullName
        } else {
            $translationStem = Get-CodexArtifactStem -InputPath $item.FullName
            $ocrParams = @{
                InputPath     = $item.FullName
                OutputDir     = $OutputDir
                Privacy       = $resolvedPrivacy
                CloudFallback = $CloudFallback
            }
            if (-not [string]::IsNullOrWhiteSpace($ImageProfile)) {
                $ocrParams.ImageProfile = $ImageProfile
            }
            $extracted = Invoke-CodexOcrSmart @ocrParams
            $inputText = Read-CodexTextArtifact -Path $extracted.OutputTextPath
            $sourcePath = $extracted.OutputTextPath
            $translationStem = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
        }
        $outputRoot = Resolve-CodexDocumentOutputDirectory -InputPath $sourcePath -OutputDir $OutputDir
    } else {
        $inputText = $Text
        $outputRoot = Resolve-CodexDocumentOutputDirectory -OutputDir $OutputDir
        $translationStem = 'translated_text'
    }

    if ([string]::IsNullOrWhiteSpace($inputText)) {
        throw 'No text is available for translation.'
    }

    if ($ProviderOrder -and $ProviderOrder.Count -gt 0) {
        $providers = @($ProviderOrder)
    } else {
        $providers = @($config.Providers.TranslateLocal + $config.Providers.TranslateCloud)
    }

    $chunks = @(Split-CodexTextChunks -Text $inputText -MaxChars ([int]$config.Defaults.TranslationChunkSize))
    if ($chunks.Count -eq 0) {
        throw 'No text chunks were generated for translation.'
    }

    $cloudAllowed = Test-CodexCloudAllowed -Privacy $resolvedPrivacy -CloudFallback:$CloudFallback
    $errors = New-Object System.Collections.Generic.List[string]
    $translatedText = $null
    $chosenProvider = ''

    foreach ($provider in $providers) {
        $isCloudProvider = $config.Providers.TranslateCloud -contains $provider
        if ($isCloudProvider -and -not $cloudAllowed) {
            continue
        }

        try {
            $translatedChunks = New-Object System.Collections.Generic.List[string]
            foreach ($chunk in $chunks) {
                [void]$translatedChunks.Add((Invoke-CodexTranslationProvider -Provider $provider -Text $chunk -SourceLanguage $SourceLanguage -TargetLanguage $resolvedTarget))
            }
            $translatedText = [string]::Join("`n`n", @($translatedChunks.ToArray()))
            $chosenProvider = $provider
            break
        } catch {
            [void]$errors.Add(('{0}: {1}' -f $provider, $_.Exception.Message))
        }
    }

    if ([string]::IsNullOrWhiteSpace($translatedText)) {
        throw ("Translation failed. " + ([string]::Join(' | ', @($errors.ToArray()))))
    }

    $translationPath = Join-Path $outputRoot ('{0}.{1}.txt' -f $translationStem, $resolvedTarget)
    $manifestPath = Join-Path $outputRoot ('{0}.translation_manifest.json' -f $translationStem)
    Write-CodexTextFile -Path $translationPath -Text $translatedText | Out-Null

    $manifest = [pscustomobject]@{
        SourcePath     = $sourcePath
        OutputPath     = $translationPath
        Provider       = $chosenProvider
        TargetLanguage = $resolvedTarget
        SourceLanguage = $SourceLanguage
        Privacy        = $resolvedPrivacy
        CloudFallback  = $CloudFallback.IsPresent
        ChunkCount     = $chunks.Count
        CharacterCount = $inputText.Length
        Errors         = @($errors.ToArray())
    }

    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $manifest
}

function Invoke-CodexDocumentPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$InputPath,

        [string]$OutputDir,

        [string]$OcrLanguage,

        [string]$SourceLanguage = 'auto',

        [string]$TargetLanguage,

        [ValidateSet('auto', 'screenshot', 'photo', 'scan')]
        [string]$ImageProfile,

        [ValidateSet('private', 'nonprivate')]
        [string]$Privacy,

        [switch]$CloudFallback,

        [switch]$ForceOcr,

        [switch]$ExtractOnly
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "Input path not found: $InputPath"
    }

    $config = Initialize-CodexDocumentPipelineConfig
    if ([string]::IsNullOrWhiteSpace($Privacy)) {
        $resolvedPrivacy = [string]$config.Defaults.Privacy
    } else {
        $resolvedPrivacy = $Privacy
    }
    if ([string]::IsNullOrWhiteSpace($TargetLanguage)) {
        $resolvedTarget = [string]$config.Defaults.TargetLanguage
    } else {
        $resolvedTarget = $TargetLanguage
    }
    $outputRoot = Resolve-CodexDocumentOutputDirectory -InputPath $InputPath -OutputDir $OutputDir

    $extractParams = @{
        InputPath     = $InputPath
        OutputDir     = $outputRoot
        Language      = $OcrLanguage
        Privacy       = $resolvedPrivacy
        CloudFallback = $CloudFallback
        ForceOcr      = $ForceOcr
    }
    if (-not [string]::IsNullOrWhiteSpace($ImageProfile)) {
        $extractParams.ImageProfile = $ImageProfile
    }
    $extract = Invoke-CodexOcrSmart @extractParams
    $translation = $null
    if (-not $ExtractOnly) {
        $translateParams = @{
            InputPath       = $extract.OutputTextPath
            OutputDir       = $outputRoot
            SourceLanguage  = $SourceLanguage
            TargetLanguage  = $resolvedTarget
            Privacy         = $resolvedPrivacy
            CloudFallback   = $CloudFallback
        }
        if (-not [string]::IsNullOrWhiteSpace($ImageProfile)) {
            $translateParams.ImageProfile = $ImageProfile
        }
        $translation = Invoke-CodexTranslateSmart @translateParams
    }

    $item = Get-Item -LiteralPath $InputPath -ErrorAction Stop
    $artifactStem = Get-CodexArtifactStem -InputPath $item.FullName
    $manifestPath = Join-Path $outputRoot ('{0}.pipeline_manifest.json' -f $artifactStem)
    $manifest = [pscustomobject]@{
        InputPath     = $item.FullName
        OutputDir     = $outputRoot
        Extraction    = $extract
        Translation   = $translation
        Privacy       = $resolvedPrivacy
        ImageProfile  = $ImageProfile
        CloudFallback = $CloudFallback.IsPresent
        ForceOcr      = $ForceOcr.IsPresent
        ExtractOnly   = $ExtractOnly.IsPresent
    }

    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $manifest
}

function Get-CodexRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$ChildPath
    )

    $baseResolved = (Resolve-Path -LiteralPath $BasePath).Path
    $childResolved = (Resolve-Path -LiteralPath $ChildPath).Path
    $baseUri = New-Object System.Uri(($baseResolved.TrimEnd('\') + '\'))
    $childUri = New-Object System.Uri($childResolved)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($childUri).ToString()).Replace('/', '\')
}

function New-CodexFileShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath,

        [string]$Description
    )

    $parent = Split-Path -Path $ShortcutPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = (Resolve-Path -LiteralPath $TargetPath).Path
        $shortcut.WorkingDirectory = Split-Path -Path $TargetPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $shortcut.Description = $Description
        }
        $shortcut.Save()
        return $ShortcutPath
    } catch {
        $urlPath = [System.IO.Path]::ChangeExtension($ShortcutPath, '.url')
        $resolvedTarget = (Resolve-Path -LiteralPath $TargetPath).Path
        $uri = [System.Uri]$resolvedTarget
        $content = @"
[InternetShortcut]
URL=$($uri.AbsoluteUri)
"@
        Set-Content -LiteralPath $urlPath -Value $content -Encoding ASCII
        return $urlPath
    }
}

function Get-CodexDocumentRoutingDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [string]$TargetLanguage,

        [string]$OcrLanguage,

        [string]$ImageProfile
    )

    $config = Initialize-CodexDocumentPipelineConfig
    $kind = Get-CodexDocumentFileKind -Path $InputPath
    $sampleCharLimit = [int]$config.Defaults.ScanSampleChars
    $minChars = [int]$config.Defaults.MinExtractedChars
    $sampleText = ''
    $provider = ''
    $method = ''
    $route = 'unsupported'
    $supported = $true
    $notes = New-Object System.Collections.Generic.List[string]
    $resolvedImageProfile = $null

    switch ($kind) {
        'text' {
            $result = Invoke-CodexLocalTextExtraction -InputPath $InputPath -Language $OcrLanguage
            $sampleText = $result.Text
            $provider = $result.Provider
            $method = $result.Method
            $route = 'direct_text'
        }
        'html' {
            $result = Invoke-CodexLocalTextExtraction -InputPath $InputPath -Language $OcrLanguage
            $sampleText = $result.Text
            $provider = $result.Provider
            $method = $result.Method
            $route = 'direct_text'
        }
        'docx' {
            $result = Invoke-CodexLocalTextExtraction -InputPath $InputPath -Language $OcrLanguage
            $sampleText = $result.Text
            $provider = $result.Provider
            $method = $result.Method
            $route = 'direct_text'
        }
        'pptx' {
            $result = Invoke-CodexLocalTextExtraction -InputPath $InputPath -Language $OcrLanguage
            $sampleText = $result.Text
            $provider = $result.Provider
            $method = $result.Method
            $route = 'direct_text'
        }
        'epub' {
            $result = Invoke-CodexLocalTextExtraction -InputPath $InputPath -Language $OcrLanguage
            $sampleText = $result.Text
            $provider = $result.Provider
            $method = $result.Method
            $route = 'direct_text'
        }
        'pdf' {
            foreach ($candidate in @('pdftotext', 'mutool')) {
                try {
                    if ($candidate -eq 'pdftotext') {
                        $result = Invoke-CodexPdfTextExtractionWithPdftotext -InputPath $InputPath
                    } else {
                        $result = Invoke-CodexPdfTextExtractionWithMutool -InputPath $InputPath
                    }

                    if (-not [string]::IsNullOrWhiteSpace($result.Text) -and $result.Text.Trim().Length -ge $minChars) {
                        $sampleText = $result.Text
                        $provider = $result.Provider
                        $method = $result.Method
                        $route = 'direct_text'
                        break
                    }
                } catch {
                }
            }

            if ($route -ne 'direct_text') {
                $route = 'need_ocr'
                [void]$notes.Add('No sufficient native PDF text detected during scan.')
            }
        }
        'image' {
            $route = 'need_ocr'
            $resolvedImageProfile = Get-CodexImageProfile -InputPath $InputPath -PreferredProfile $ImageProfile
            $provider = 'tesseract'
            $method = 'local_ocr_image'
        }
        default {
            $supported = $false
            $route = 'unsupported'
            [void]$notes.Add(("Unsupported file type: {0}" -f $kind))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($sampleText) -and $sampleText.Length -gt $sampleCharLimit) {
        $sampleText = $sampleText.Substring(0, $sampleCharLimit)
    }
    $translation = Get-CodexTextTranslationAssessment -Text $sampleText -TargetLanguage $TargetLanguage

    return [pscustomobject]@{
        FullPath           = (Resolve-Path -LiteralPath $InputPath).Path
        Kind               = $kind
        Supported          = $supported
        ExtractionRoute    = $route
        Provider           = $provider
        Method             = $method
        SampleText         = $sampleText
        SampleLength       = $sampleText.Length
        NeedsTranslation   = $translation.NeedsTranslation
        TranslationReason  = $translation.Reason
        ImageProfile       = $resolvedImageProfile
        Notes              = @($notes.ToArray())
    }
}

function Invoke-CodexDocumentScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$RootPath,

        [string]$OutputDir,

        [string]$TargetLanguage,

        [string]$OcrLanguage,

        [ValidateSet('auto', 'screenshot', 'photo', 'scan')]
        [string]$ImageProfile,

        [switch]$Recurse,

        [int]$Limit = 0,

        [switch]$SkipShortcuts
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        throw "Root path not found: $RootPath"
    }

    $config = Initialize-CodexDocumentPipelineConfig
    if ([string]::IsNullOrWhiteSpace($TargetLanguage)) {
        $resolvedTargetLanguage = [string]$config.Defaults.TargetLanguage
    } else {
        $resolvedTargetLanguage = $TargetLanguage
    }

    $rootItem = Get-Item -LiteralPath $RootPath -ErrorAction Stop
    if ($rootItem.PSIsContainer) {
        if ($Recurse) {
            $files = @(Get-ChildItem -LiteralPath $rootItem.FullName -File -Recurse -ErrorAction Stop)
        } else {
            $files = @(Get-ChildItem -LiteralPath $rootItem.FullName -File -ErrorAction Stop)
        }
    } else {
        $files = @($rootItem)
    }

    if ($Limit -gt 0) {
        $files = @($files | Select-Object -First $Limit)
    }

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        if ($rootItem.PSIsContainer) {
            $outputRoot = Join-Path $rootItem.Parent.FullName ($rootItem.BaseName + '_codex_scan')
        } else {
            $outputRoot = Join-Path $rootItem.DirectoryName ($rootItem.BaseName + '_codex_scan')
        }
    } else {
        $outputRoot = $OutputDir
    }

    New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
    $routeRoots = [ordered]@{
        direct_text      = Join-Path $outputRoot '01_direct_text'
        need_ocr         = Join-Path $outputRoot '02_need_ocr'
        need_translation = Join-Path $outputRoot '03_need_translation'
        unsupported      = Join-Path $outputRoot '99_unsupported'
    }
    foreach ($routeRoot in $routeRoots.Values) {
        New-Item -ItemType Directory -Force -Path $routeRoot | Out-Null
    }

    $entries = New-Object System.Collections.Generic.List[object]
    $counters = [ordered]@{
        Total            = 0
        DirectText       = 0
        NeedOcr          = 0
        NeedTranslation  = 0
        Unsupported      = 0
    }

    foreach ($file in $files) {
        $counters.Total += 1
        try {
            $decision = Get-CodexDocumentRoutingDecision -InputPath $file.FullName -TargetLanguage $resolvedTargetLanguage -OcrLanguage $OcrLanguage -ImageProfile $ImageProfile
        } catch {
            $decision = [pscustomobject]@{
                FullPath           = $file.FullName
                Kind               = (Get-CodexDocumentFileKind -Path $file.FullName)
                Supported          = $false
                ExtractionRoute    = 'unsupported'
                Provider           = ''
                Method             = ''
                SampleText         = ''
                SampleLength       = 0
                NeedsTranslation   = $false
                TranslationReason  = 'scan_error'
                ImageProfile       = $null
                Notes              = @($_.Exception.Message)
            }
        }

        if ($rootItem.PSIsContainer) {
            $relativePath = Get-CodexRelativePath -BasePath $rootItem.FullName -ChildPath $file.FullName
        } else {
            $relativePath = Split-Path -Path $file.FullName -Leaf
        }

        $shortcutPaths = New-Object System.Collections.Generic.List[string]
        if (-not $SkipShortcuts) {
            if ($decision.ExtractionRoute -eq 'direct_text') {
                $directShortcut = Join-Path $routeRoots.direct_text ($relativePath + '.lnk')
                [void]$shortcutPaths.Add((New-CodexFileShortcut -TargetPath $file.FullName -ShortcutPath $directShortcut -Description 'Codex route: direct text'))
            } elseif ($decision.ExtractionRoute -eq 'need_ocr') {
                $ocrShortcut = Join-Path $routeRoots.need_ocr ($relativePath + '.lnk')
                [void]$shortcutPaths.Add((New-CodexFileShortcut -TargetPath $file.FullName -ShortcutPath $ocrShortcut -Description 'Codex route: needs OCR'))
            } else {
                $unsupportedShortcut = Join-Path $routeRoots.unsupported ($relativePath + '.lnk')
                [void]$shortcutPaths.Add((New-CodexFileShortcut -TargetPath $file.FullName -ShortcutPath $unsupportedShortcut -Description 'Codex route: unsupported'))
            }

            if ($decision.NeedsTranslation) {
                $translationShortcut = Join-Path $routeRoots.need_translation ($relativePath + '.lnk')
                [void]$shortcutPaths.Add((New-CodexFileShortcut -TargetPath $file.FullName -ShortcutPath $translationShortcut -Description 'Codex route: needs translation'))
            }
        }

        switch ($decision.ExtractionRoute) {
            'direct_text' { $counters.DirectText += 1 }
            'need_ocr' { $counters.NeedOcr += 1 }
            default { $counters.Unsupported += 1 }
        }
        if ($decision.NeedsTranslation) {
            $counters.NeedTranslation += 1
        }

        [void]$entries.Add([pscustomobject]@{
            FullPath          = $decision.FullPath
            RelativePath      = $relativePath
            Kind              = $decision.Kind
            Supported         = $decision.Supported
            ExtractionRoute   = $decision.ExtractionRoute
            Provider          = $decision.Provider
            Method            = $decision.Method
            NeedsTranslation  = $decision.NeedsTranslation
            TranslationReason = $decision.TranslationReason
            ImageProfile      = $decision.ImageProfile
            SampleLength      = $decision.SampleLength
            SampleText        = $decision.SampleText
            Notes             = $decision.Notes
            ShortcutPaths     = @($shortcutPaths.ToArray())
        })
    }

    $manifestPath = Join-Path $outputRoot 'scan_manifest.json'
    $manifest = [pscustomobject]@{
        RootPath       = $rootItem.FullName
        OutputDir      = $outputRoot
        Recurse        = $Recurse.IsPresent
        TargetLanguage = $resolvedTargetLanguage
        Counters       = [pscustomobject]$counters
        Entries        = @($entries.ToArray())
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    foreach ($routeName in @('direct_text', 'need_ocr', 'need_translation', 'unsupported')) {
        $routeEntries = @($manifest.Entries | Where-Object {
            switch ($routeName) {
                'direct_text' { $_.ExtractionRoute -eq 'direct_text' }
                'need_ocr' { $_.ExtractionRoute -eq 'need_ocr' }
                'need_translation' { $_.NeedsTranslation }
                'unsupported' { $_.ExtractionRoute -eq 'unsupported' }
            }
        })

        $routeManifestPath = Join-Path $routeRoots[$routeName] 'manifest.json'
        $routeEntries | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $routeManifestPath -Encoding UTF8
        $routePathList = Join-Path $routeRoots[$routeName] 'paths.txt'
        [string]::Join([Environment]::NewLine, @($routeEntries | ForEach-Object { $_.FullPath })) | Set-Content -LiteralPath $routePathList -Encoding UTF8
    }

    return [pscustomobject]@{
        RootPath      = $rootItem.FullName
        OutputDir     = $outputRoot
        ManifestPath  = $manifestPath
        Counters      = [pscustomobject]$counters
        Entries       = @($entries.ToArray())
    }
}

function Invoke-CodexDocumentBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$RootPath,

        [string]$OutputDir,

        [string]$OcrLanguage,

        [string]$SourceLanguage = 'auto',

        [string]$TargetLanguage,

        [ValidateSet('auto', 'screenshot', 'photo', 'scan')]
        [string]$ImageProfile,

        [ValidateSet('private', 'nonprivate')]
        [string]$Privacy,

        [switch]$CloudFallback,

        [switch]$Recurse,

        [int]$Limit = 0,

        [switch]$TranslateAll,

        [switch]$TranslateAfterOcr,

        [switch]$ForceOcr
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        throw "Root path not found: $RootPath"
    }

    $config = Initialize-CodexDocumentPipelineConfig
    if ([string]::IsNullOrWhiteSpace($TargetLanguage)) {
        $resolvedTargetLanguage = [string]$config.Defaults.TargetLanguage
    } else {
        $resolvedTargetLanguage = $TargetLanguage
    }
    if ([string]::IsNullOrWhiteSpace($Privacy)) {
        $resolvedPrivacy = [string]$config.Defaults.Privacy
    } else {
        $resolvedPrivacy = $Privacy
    }

    $rootItem = Get-Item -LiteralPath $RootPath -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        if ($rootItem.PSIsContainer) {
            $batchRoot = Join-Path $rootItem.Parent.FullName ($rootItem.BaseName + '_codex_batch')
        } else {
            $batchRoot = Join-Path $rootItem.DirectoryName ($rootItem.BaseName + '_codex_batch')
        }
    } else {
        $batchRoot = $OutputDir
    }

    $scanOutput = Join-Path $batchRoot '_scan'
    $scanParams = @{
        RootPath       = $RootPath
        OutputDir      = $scanOutput
        TargetLanguage = $resolvedTargetLanguage
        OcrLanguage    = $OcrLanguage
        Recurse        = $Recurse
        Limit          = $Limit
    }
    if (-not [string]::IsNullOrWhiteSpace($ImageProfile)) {
        $scanParams.ImageProfile = $ImageProfile
    }
    $scan = Invoke-CodexDocumentScan @scanParams
    $processedRoot = Join-Path $batchRoot 'processed'
    New-Item -ItemType Directory -Force -Path $processedRoot | Out-Null

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $scan.Entries) {
        if (-not $entry.Supported) {
            [void]$results.Add([pscustomobject]@{
                InputPath    = $entry.FullPath
                RelativePath = $entry.RelativePath
                Status       = 'skipped'
                Reason       = 'unsupported'
                OutputDir    = $null
            })
            continue
        }

        $relativeParent = Split-Path -Path $entry.RelativePath -Parent
        if ([string]::IsNullOrWhiteSpace($relativeParent)) {
            $fileOutputDir = $processedRoot
        } else {
            $fileOutputDir = Join-Path $processedRoot $relativeParent
        }

        $shouldTranslate = $false
        if ($TranslateAll) {
            $shouldTranslate = $true
        } elseif ($entry.NeedsTranslation) {
            $shouldTranslate = $true
        } elseif ($TranslateAfterOcr -and $entry.ExtractionRoute -eq 'need_ocr') {
            $shouldTranslate = $true
        }

        try {
            $pipelineParams = @{
                InputPath      = $entry.FullPath
                OutputDir      = $fileOutputDir
                SourceLanguage = $SourceLanguage
                TargetLanguage = $resolvedTargetLanguage
                Privacy        = $resolvedPrivacy
                CloudFallback  = $CloudFallback
                ForceOcr       = ($ForceOcr.IsPresent -or $entry.ExtractionRoute -eq 'need_ocr')
            }
            if (-not [string]::IsNullOrWhiteSpace($OcrLanguage)) {
                $pipelineParams.OcrLanguage = $OcrLanguage
            }
            if (-not [string]::IsNullOrWhiteSpace($ImageProfile)) {
                $pipelineParams.ImageProfile = $ImageProfile
            }
            if (-not $shouldTranslate) {
                $pipelineParams.ExtractOnly = $true
            }

            $result = Invoke-CodexDocumentPipeline @pipelineParams
            if ($null -ne $result.Translation) {
                $translationPath = $result.Translation.OutputPath
            } else {
                $translationPath = $null
            }
            [void]$results.Add([pscustomobject]@{
                InputPath        = $entry.FullPath
                RelativePath     = $entry.RelativePath
                Status           = 'processed'
                OutputDir        = $fileOutputDir
                ExtractionPath   = $result.Extraction.OutputTextPath
                TranslationPath  = $translationPath
                ExtractOnly      = $result.ExtractOnly
                CloudFallback    = $result.CloudFallback
            })
        } catch {
            [void]$results.Add([pscustomobject]@{
                InputPath    = $entry.FullPath
                RelativePath = $entry.RelativePath
                Status       = 'error'
                Reason       = $_.Exception.Message
                OutputDir    = $fileOutputDir
            })
        }
    }

    $batchManifestPath = Join-Path $batchRoot 'batch_manifest.json'
    $batchManifest = [pscustomobject]@{
        RootPath          = $rootItem.FullName
        OutputDir         = $batchRoot
        ScanManifestPath  = $scan.ManifestPath
        TargetLanguage    = $resolvedTargetLanguage
        Privacy           = $resolvedPrivacy
        Recurse           = $Recurse.IsPresent
        TranslateAll      = $TranslateAll.IsPresent
        TranslateAfterOcr = $TranslateAfterOcr.IsPresent
        Results           = @($results.ToArray())
    }
    $batchManifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $batchManifestPath -Encoding UTF8

    return [pscustomobject]@{
        RootPath         = $rootItem.FullName
        OutputDir        = $batchRoot
        ScanManifestPath = $scan.ManifestPath
        ManifestPath     = $batchManifestPath
        Results          = @($results.ToArray())
    }
}

function Get-CodexDocumentCapabilities {
    [CmdletBinding()]
    param()

    $config = Initialize-CodexDocumentPipelineConfig
    $ollamaModels = @(Get-CodexOllamaInstalledModels)

    return [pscustomobject]@{
        Tools = [pscustomobject]@{
            pdftotext = -not [string]::IsNullOrWhiteSpace($config.Tools.pdftotext)
            pdftoppm  = -not [string]::IsNullOrWhiteSpace($config.Tools.pdftoppm)
            mutool    = -not [string]::IsNullOrWhiteSpace($config.Tools.mutool)
            ocrmypdf  = -not [string]::IsNullOrWhiteSpace($config.Tools.ocrmypdf)
            tesseract = -not [string]::IsNullOrWhiteSpace($config.Tools.tesseract)
            magick    = -not [string]::IsNullOrWhiteSpace($config.Tools.magick)
            ollama    = -not [string]::IsNullOrWhiteSpace($config.Tools.ollama)
        }
        ToolPaths = [pscustomobject]$config.Tools
        Defaults  = [pscustomobject]$config.Defaults
        Local     = [pscustomobject]@{
            OllamaModel           = $config.Local.OllamaModel
            InstalledOllamaModels = $ollamaModels
        }
        Formats   = [pscustomobject]@{
            NativeText = @('txt', 'md', 'csv', 'json', 'yaml', 'yml', 'html', 'htm', 'mhtml')
            OpenXml    = @('docx', 'pptx')
            Ebook      = @('epub')
            Pdf        = @('pdf')
            Images     = @('png', 'jpg', 'jpeg', 'bmp', 'gif', 'tif', 'tiff', 'webp')
        }
        CloudConfigured = [pscustomobject]@{
            OCRSpace        = -not [string]::IsNullOrWhiteSpace($config.Cloud.OcrSpaceApiKey)
            AzureVision     = (-not [string]::IsNullOrWhiteSpace($config.Cloud.AzureVisionEndpoint)) -and (-not [string]::IsNullOrWhiteSpace($config.Cloud.AzureVisionKey))
            LibreTranslate  = -not [string]::IsNullOrWhiteSpace($config.Cloud.LibreTranslateUrl)
            AzureTranslator = -not [string]::IsNullOrWhiteSpace($config.Cloud.AzureTranslatorKey)
            DeepL           = -not [string]::IsNullOrWhiteSpace($config.Cloud.DeepLAuthKey)
        }
    }
}

function Show-CodexDocumentPipelineHelp {
    @'
Codex OCR / translation helpers

Quick extraction:
  pdf-smart .\paper.pdf
  ocr-smart .\scan.png
  ocr-smart .\lecture_photo.jpg -ImageProfile photo
  ocr-smart .\webpage_capture.png -ImageProfile screenshot
  ocr-smart .\notes.docx
  ocr-smart .\slides.pptx
  ocr-smart .\book.epub

Pipeline:
  doc-pipeline .\scan.pdf -TargetLanguage zh -Privacy private
  doc-pipeline .\public_scan.pdf -TargetLanguage en -Privacy nonprivate -CloudFallback

Batch routing:
  doc-scan .\CourseFolder -Recurse
  doc-batch .\CourseFolder -Recurse -TranslateAfterOcr

Translation only:
  translate-smart .\notes.txt -TargetLanguage zh

Config:
  doc-config -Show
  doc-config -ImageProfile auto -EnableImagePreprocess -PersistUserEnvironment
  doc-config -LibreTranslateUrl http://localhost:5000 -PersistUserEnvironment
  doc-config -OcrSpaceApiKey <key> -AzureTranslatorKey <key> -AzureTranslatorRegion <region>

Outputs:
  <input>_codex\<input>.txt
  <input>_codex\<input>.<lang>.txt
  <input>_codex\*.manifest.json
  <folder>_codex_scan\01_direct_text / 02_need_ocr / 03_need_translation
'@
}

Set-Alias -Name ocr-smart -Value Invoke-CodexOcrSmart -Scope Global -Option AllScope -Force
Set-Alias -Name pdf-smart -Value Invoke-CodexPdfSmart -Scope Global -Option AllScope -Force
Set-Alias -Name translate-smart -Value Invoke-CodexTranslateSmart -Scope Global -Option AllScope -Force
Set-Alias -Name doc-pipeline -Value Invoke-CodexDocumentPipeline -Scope Global -Option AllScope -Force
Set-Alias -Name doc-scan -Value Invoke-CodexDocumentScan -Scope Global -Option AllScope -Force
Set-Alias -Name doc-batch -Value Invoke-CodexDocumentBatch -Scope Global -Option AllScope -Force
Set-Alias -Name doc-config -Value Set-CodexDocumentPipelineConfig -Scope Global -Option AllScope -Force
Set-Alias -Name ocr-models -Value Get-CodexDocumentCapabilities -Scope Global -Option AllScope -Force
Set-Alias -Name doc-help -Value Show-CodexDocumentPipelineHelp -Scope Global -Option AllScope -Force

Initialize-CodexDocumentPipelineConfig | Out-Null
