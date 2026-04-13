function Get-CodexAuthHelperScriptPath {
    $profileRootCommand = Get-Command 'Get-CodexPowerShellProfileRoot' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $profileRootCommand) {
        return (Join-Path (Get-CodexPowerShellProfileRoot) 'Scripts\codex_auth_web.py')
    }

    $myDocuments = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    return (Join-Path (Join-Path $myDocuments 'PowerShell') 'Scripts\codex_auth_web.py')
}

function Get-CodexPythonPath {
    $python = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $python) {
        throw 'python is not available in PATH.'
    }

    if ($python.Source) {
        return $python.Source
    }

    if ($python.Path) {
        return $python.Path
    }

    return 'python'
}

function Ensure-CodexAuthDependencies {
    [CmdletBinding()]
    param()

    $python = Get-CodexPythonPath
    $probe = @'
import importlib.util
import sys
modules = {
    "playwright": "playwright",
    "requests": "requests",
    "bs4": "beautifulsoup4",
}
missing = [pkg for mod, pkg in modules.items() if importlib.util.find_spec(mod) is None]
if missing:
    print(",".join(missing))
    sys.exit(42)
'@

    $null = & $python -c $probe 2>$null
    if ($LASTEXITCODE -eq 0) {
        return
    }

    & $python -m pip install --quiet playwright requests beautifulsoup4
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to install required Python packages for web-auth helpers.'
    }
}

function Get-CodexChromiumExecutable {
    [CmdletBinding()]
    param(
        [ValidateSet('edge', 'chrome')]
        [string]$Browser = 'edge'
    )

    $candidates = switch ($Browser) {
        'edge' {
            @(
                "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
            )
        }
        'chrome' {
            @(
                "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            )
        }
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    throw "Unable to find the $Browser executable."
}

function Get-CodexChromiumUserDataDir {
    [CmdletBinding()]
    param(
        [ValidateSet('edge', 'chrome')]
        [string]$Browser = 'edge'
    )

    switch ($Browser) {
        'edge' {
            return (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')
        }
        'chrome' {
            return (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data')
        }
    }
}

function Test-CodexCdpEndpoint {
    [CmdletBinding()]
    param(
        [int]$Port = 9222
    )

    try {
        $null = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2
        return $true
    } catch {
        return $false
    }
}

function Wait-CodexCdpEndpoint {
    [CmdletBinding()]
    param(
        [int]$Port = 9222,
        [int]$TimeoutSeconds = 15
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-CodexCdpEndpoint -Port $Port) {
            return $true
        }

        Start-Sleep -Milliseconds 300
    }

    return $false
}

function Invoke-CodexAuthHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Ensure-CodexAuthDependencies

    $python = Get-CodexPythonPath
    $scriptPath = Get-CodexAuthHelperScriptPath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Helper script not found: $scriptPath"
    }

    $output = & $python $scriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        $text = [string]::Join([Environment]::NewLine, @($output))
        throw "codex_auth_web.py failed.`n$text"
    }

    $raw = [string]::Join([Environment]::NewLine, @($output)).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return ($raw | ConvertFrom-Json)
}

function Resolve-CodexExistingDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$Label = 'Directory'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Label must be specified."
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label does not exist: $Path"
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if (-not $item.PSIsContainer) {
        throw "$Label is not a directory: $Path"
    }

    return $item.FullName
}

function Start-CodexAuthBrowser {
    [CmdletBinding()]
    param(
        [ValidateSet('edge', 'chrome')]
        [string]$Browser = 'edge',

        [string]$ProfileDirectory = 'Default',

        [int]$Port = 9222,

        [string]$Url = 'about:blank',

        [switch]$ForceRestart,

        [switch]$PassThru
    )

    if (Test-CodexCdpEndpoint -Port $Port) {
        $result = [pscustomobject]@{
            Browser          = $Browser
            Port             = $Port
            ProfileDirectory = $ProfileDirectory
            Status           = 'AlreadyListening'
            Endpoint         = "http://127.0.0.1:$Port"
        }

        if ($PassThru) {
            return $result
        }

        $result
        return
    }

    $exePath = Get-CodexChromiumExecutable -Browser $Browser
    $userDataDir = Get-CodexChromiumUserDataDir -Browser $Browser
    $processName = if ($Browser -eq 'edge') { 'msedge' } else { 'chrome' }
    $running = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)

    if ($running.Count -gt 0 -and -not $ForceRestart) {
        throw "Existing $Browser windows are running. Close them first or rerun with -ForceRestart."
    }

    if ($running.Count -gt 0 -and $ForceRestart) {
        $running | Stop-Process -Force
        Start-Sleep -Seconds 2
    }

    $arguments = @(
        "--remote-debugging-port=$Port",
        "--user-data-dir=""$userDataDir""",
        "--profile-directory=$ProfileDirectory",
        $Url
    )

    Start-Process -FilePath $exePath -ArgumentList $arguments | Out-Null

    if (-not (Wait-CodexCdpEndpoint -Port $Port -TimeoutSeconds 20)) {
        throw "Browser started, but CDP endpoint did not appear on port $Port."
    }

    $result = [pscustomobject]@{
        Browser          = $Browser
        Port             = $Port
        ProfileDirectory = $ProfileDirectory
        Status           = 'Started'
        Endpoint         = "http://127.0.0.1:$Port"
    }

    if ($PassThru) {
        return $result
    }

    $result
}

function Export-CodexAuthLinks {
    [CmdletBinding()]
    param(
        [string]$Url,

        [string]$PageUrlContains,

        [string]$OutFile,

        [int]$Port = 9222
    )

    $arguments = @('links', '--cdp', "http://127.0.0.1:$Port")
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        $arguments += @('--url', $Url)
    }
    if (-not [string]::IsNullOrWhiteSpace($PageUrlContains)) {
        $arguments += @('--page-url-contains', $PageUrlContains)
    }
    if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
        $arguments += @('--out', $OutFile)
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function New-CodexAuthSpec {
    [CmdletBinding()]
    param(
        [ValidateSet('auto', 'generic', 'moodle', 'sharepoint', 'panopto')]
        [string]$Site = 'auto',

        [string]$Url,

        [string]$PageUrlContains,

        [string]$OutFile,

        [int]$Port = 9222,

        [int]$Limit
    )

    $arguments = @('infer-spec', '--cdp', "http://127.0.0.1:$Port", '--site', $Site)
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        $arguments += @('--url', $Url)
    }
    if (-not [string]::IsNullOrWhiteSpace($PageUrlContains)) {
        $arguments += @('--page-url-contains', $PageUrlContains)
    }
    if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
        $arguments += @('--out', $OutFile)
    }
    if ($PSBoundParameters.ContainsKey('Limit') -and $Limit -gt 0) {
        $arguments += @('--limit', $Limit.ToString())
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function Save-CodexAuthContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [ValidateSet('auto', 'file', 'page', 'shortcut', 'folder', 'quiz')]
        [string]$Mode = 'auto',

        [string]$DestinationDir,

        [string]$OutFile,

        [string]$FileName,

        [int]$Port = 9222
    )

    $arguments = @('download', '--cdp', "http://127.0.0.1:$Port", '--url', $Url, '--mode', $Mode)
    if (-not [string]::IsNullOrWhiteSpace($DestinationDir)) {
        $arguments += @('--destination-dir', $DestinationDir)
    }
    if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
        $arguments += @('--out', $OutFile)
    }
    if (-not [string]::IsNullOrWhiteSpace($FileName)) {
        $arguments += @('--filename', $FileName)
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function Save-CodexAuthPage {
    [CmdletBinding()]
    param(
        [string]$Url,

        [string]$PageUrlContains,

        [string]$DestinationDir,

        [string]$OutFile,

        [string]$FileName,

        [int]$Port = 9222
    )

    $arguments = @('save-page', '--cdp', "http://127.0.0.1:$Port")
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        $arguments += @('--url', $Url)
    }
    if (-not [string]::IsNullOrWhiteSpace($PageUrlContains)) {
        $arguments += @('--page-url-contains', $PageUrlContains)
    }
    if (-not [string]::IsNullOrWhiteSpace($DestinationDir)) {
        $arguments += @('--destination-dir', $DestinationDir)
    }
    if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
        $arguments += @('--out', $OutFile)
    }
    if (-not [string]::IsNullOrWhiteSpace($FileName)) {
        $arguments += @('--filename', $FileName)
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function Invoke-CodexAuthBatchDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SpecPath,

        [string]$DestinationDir,

        [string]$ManifestPath,

        [int]$Port = 9222
    )

    $arguments = @('batch', '--cdp', "http://127.0.0.1:$Port", '--spec', $SpecPath)
    if (-not [string]::IsNullOrWhiteSpace($DestinationDir)) {
        $arguments += @('--destination-dir', $DestinationDir)
    }
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
        $arguments += @('--manifest', $ManifestPath)
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function Invoke-CodexAuthDump {
    [CmdletBinding()]
    param(
        [ValidateSet('auto', 'generic', 'moodle', 'sharepoint', 'panopto')]
        [string]$Site = 'auto',

        [string]$Url,

        [string]$PageUrlContains,

        [string]$DestinationDir = (Get-Location).Path,

        [string]$RootName,

        [string]$SpecPath,

        [string]$ManifestPath,

        [int]$Port = 9222,

        [int]$Limit
    )

    $spec = New-CodexAuthSpec -Site $Site -Url $Url -PageUrlContains $PageUrlContains -Port $Port -Limit $Limit
    if ($null -eq $spec) {
        throw 'Spec generation returned no result.'
    }

    $suggestedRoot = if (-not [string]::IsNullOrWhiteSpace($RootName)) { $RootName } elseif (-not [string]::IsNullOrWhiteSpace($spec.suggested_root)) { [string]$spec.suggested_root } else { 'auth_dump' }
    $rootDir = Join-Path $DestinationDir $suggestedRoot
    New-Item -ItemType Directory -Path $rootDir -Force | Out-Null

    $resolvedSpecPath = if (-not [string]::IsNullOrWhiteSpace($SpecPath)) { $SpecPath } else { Join-Path $rootDir 'download_spec.json' }
    $resolvedManifestPath = if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath } else { Join-Path $rootDir 'download_manifest.json' }

    $spec | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $resolvedSpecPath -Encoding UTF8
    $batch = Invoke-CodexAuthBatchDownload -SpecPath $resolvedSpecPath -DestinationDir $rootDir -ManifestPath $resolvedManifestPath -Port $Port

    [pscustomobject]@{
        Site         = $spec.site
        Title        = $spec.title
        Url          = $spec.url
        RootDir      = $rootDir
        SpecPath     = $resolvedSpecPath
        ManifestPath = $resolvedManifestPath
        ItemCount    = $spec.count
        Batch        = $batch
    }
}

function Export-CodexChatGptDump {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://chatgpt.com/',

        [string]$PageUrlContains = 'chatgpt.com',

        [Parameter(Mandatory = $true)]
        [string]$DestinationDir,

        [string]$RootName,

        [string[]]$Keyword,

        [string]$TopicLabel,

        [int]$Port = 9222,

        [int]$Limit,

        [switch]$SaveAll,

        [switch]$UseStudyKeywords
    )

    if (-not $SaveAll -and -not $UseStudyKeywords -and ($null -eq $Keyword -or $Keyword.Count -eq 0)) {
        throw 'Provide -Keyword, or use -UseStudyKeywords, or pass -SaveAll.'
    }

    $resolvedDestinationDir = Resolve-CodexExistingDirectory -Path $DestinationDir -Label 'ChatGPT destination directory'

    $advisories = New-Object System.Collections.Generic.List[string]
    $normalizedKeywords = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Keyword) {
        foreach ($rawKeyword in $Keyword) {
            foreach ($part in (($rawKeyword -split '[;,]') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
                [void]$normalizedKeywords.Add($part.Trim())
            }
        }
    }

    $broadKeywords = @('study', 'learning', 'learn', 'note', 'notes', 'course', 'courses', 'lecture', 'lectures', 'assignment', 'university', 'ucl', 'physics', 'math', 'mathematics', 'research', 'paper', 'essay', 'coding', 'python', 'car', 'cars', 'flower', 'flowers', 'garden')
    $broadHits = @($normalizedKeywords | Where-Object {
        $candidate = $_.ToLowerInvariant()
        ($candidate.Length -le 3) -or ($broadKeywords -contains $candidate)
    })

    if ($SaveAll) {
        [void]$advisories.Add('`-SaveAll` is the broadest mode and is the most likely to trigger temporary ChatGPT protections.')
    }
    if ($UseStudyKeywords) {
        [void]$advisories.Add('The built-in learning template is intentionally broad and can match a large portion of your chat history.')
    }
    if ($broadHits.Count -gt 0) {
        [void]$advisories.Add(('Broad/generic keywords detected: {0}' -f ([string]::Join(', ', ($broadHits | Select-Object -First 8)))))
    }
    if (-not $PSBoundParameters.ContainsKey('Limit') -and ($SaveAll -or $UseStudyKeywords -or $broadHits.Count -gt 0)) {
        [void]$advisories.Add('No `-Limit` was provided. The exporter will auto-cap broad scans to a safer sample size to reduce the chance of temporary restrictions.')
    }
    foreach ($advisory in @($advisories | Select-Object -Unique)) {
        Write-Warning $advisory
    }

    if ([string]::IsNullOrWhiteSpace($RootName)) {
        if ($UseStudyKeywords) {
            $rootPrefix = 'ChatGPT_Learning_Export'
        } elseif (-not [string]::IsNullOrWhiteSpace($TopicLabel)) {
            $safeTopic = ($TopicLabel -replace '[<>:"/\\|?*\x00-\x1f]', '_').Trim()
            if ([string]::IsNullOrWhiteSpace($safeTopic)) {
                $safeTopic = 'Topic'
            }
            $rootPrefix = 'ChatGPT_{0}_Export' -f $safeTopic
        } elseif ($SaveAll) {
            $rootPrefix = 'ChatGPT_All_Export'
        } else {
            $rootPrefix = 'ChatGPT_Topic_Export'
        }
        $resolvedRootName = '{0}_{1}' -f $rootPrefix, (Get-Date -Format 'yyyyMMdd_HHmmss')
    } else {
        $resolvedRootName = $RootName
    }
    $rootDir = Join-Path $resolvedDestinationDir $resolvedRootName
    New-Item -ItemType Directory -Path $rootDir -Force | Out-Null

    $arguments = @('chatgpt-export', '--cdp', "http://127.0.0.1:$Port", '--destination-dir', $rootDir)
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        $arguments += @('--url', $Url)
    }
    if (-not [string]::IsNullOrWhiteSpace($PageUrlContains)) {
        $arguments += @('--page-url-contains', $PageUrlContains)
    }
    if ($PSBoundParameters.ContainsKey('Limit') -and $Limit -gt 0) {
        $arguments += @('--limit', $Limit.ToString())
    }
    if ($SaveAll) {
        $arguments += '--save-all'
    }
    if ($UseStudyKeywords) {
        $arguments += '--default-study-keywords'
    }
    if (-not [string]::IsNullOrWhiteSpace($TopicLabel)) {
        $arguments += @('--topic-label', $TopicLabel)
    }
    if ($null -ne $Keyword) {
        foreach ($item in $Keyword) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $arguments += @('--keyword', $item)
            }
        }
    }

    $result = Invoke-CodexAuthHelper -Arguments $arguments
    if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'warnings') {
        foreach ($warning in @($result.warnings)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$warning)) {
                Write-Warning ([string]$warning)
            }
        }
    }
    $result
}

function Export-CodexChatGptLearningDump {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://chatgpt.com/',

        [string]$PageUrlContains = 'chatgpt.com',

        [Parameter(Mandatory = $true)]
        [string]$DestinationDir,

        [string]$RootName,

        [int]$Port = 9222,

        [int]$Limit,

        [switch]$SaveAll
    )

    Export-CodexChatGptDump -Url $Url -PageUrlContains $PageUrlContains -DestinationDir $DestinationDir -RootName $RootName -Port $Port -Limit $Limit -SaveAll:$SaveAll -UseStudyKeywords -TopicLabel 'learning'
}

function Get-CodexChatGptConversationList {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://chatgpt.com/',
        [string]$PageUrlContains = 'chatgpt.com',
        [string]$TitleContains,
        [int]$Port = 9222,
        [int]$Limit
    )

    $arguments = @('chatgpt-list', '--cdp', "http://127.0.0.1:$Port", '--url', $Url)
    if (-not [string]::IsNullOrWhiteSpace($PageUrlContains)) {
        $arguments += @('--page-url-contains', $PageUrlContains)
    }
    if (-not [string]::IsNullOrWhiteSpace($TitleContains)) {
        $arguments += @('--title-contains', $TitleContains)
    }
    if ($PSBoundParameters.ContainsKey('Limit') -and $Limit -gt 0) {
        $arguments += @('--limit', $Limit.ToString())
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function Open-CodexChatGptConversation {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://chatgpt.com/',
        [string]$PageUrlContains = 'chatgpt.com',
        [string]$ConversationId,
        [string]$TitleContains,
        [switch]$NewChat,
        [string]$ExportDir,
        [int]$Port = 9222
    )

    $arguments = @('chatgpt-open', '--cdp', "http://127.0.0.1:$Port", '--url', $Url)
    if (-not [string]::IsNullOrWhiteSpace($PageUrlContains)) {
        $arguments += @('--page-url-contains', $PageUrlContains)
    }
    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        $arguments += @('--conversation-id', $ConversationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($TitleContains)) {
        $arguments += @('--title-contains', $TitleContains)
    }
    if ($NewChat) {
        $arguments += '--new-chat'
    }
    if (-not [string]::IsNullOrWhiteSpace($ExportDir)) {
        $resolvedExportDir = Resolve-CodexExistingDirectory -Path $ExportDir -Label 'ChatGPT export directory'
        $arguments += @('--export-dir', $resolvedExportDir)
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function Save-CodexChatGptConversation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationDir,
        [string]$Url = 'https://chatgpt.com/',
        [string]$PageUrlContains = 'chatgpt.com',
        [string]$ConversationId,
        [string]$TitleContains,
        [switch]$NewChat,
        [int]$Port = 9222
    )

    $resolvedDestinationDir = Resolve-CodexExistingDirectory -Path $DestinationDir -Label 'ChatGPT destination directory'
    $arguments = @('chatgpt-save', '--cdp', "http://127.0.0.1:$Port", '--url', $Url, '--destination-dir', $resolvedDestinationDir)
    if (-not [string]::IsNullOrWhiteSpace($PageUrlContains)) {
        $arguments += @('--page-url-contains', $PageUrlContains)
    }
    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        $arguments += @('--conversation-id', $ConversationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($TitleContains)) {
        $arguments += @('--title-contains', $TitleContains)
    }
    if ($NewChat) {
        $arguments += '--new-chat'
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function Invoke-CodexChatGptPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDir,

        [string]$Url = 'https://chatgpt.com/',
        [string]$PageUrlContains = 'chatgpt.com',
        [string]$ConversationId,
        [string]$TitleContains,
        [switch]$NewChat,
        [string[]]$AttachmentPath,
        [switch]$ExportHistoryBefore,
        [string]$ResultName,
        [int]$TimeoutSeconds = 300,
        [int]$Port = 9222
    )

    $resolvedDestinationDir = Resolve-CodexExistingDirectory -Path $DestinationDir -Label 'ChatGPT destination directory'
    $arguments = @('chatgpt-ask', '--cdp', "http://127.0.0.1:$Port", '--url', $Url, '--prompt', $Prompt, '--destination-dir', $resolvedDestinationDir, '--timeout', $TimeoutSeconds.ToString())
    if (-not [string]::IsNullOrWhiteSpace($PageUrlContains)) {
        $arguments += @('--page-url-contains', $PageUrlContains)
    }
    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        $arguments += @('--conversation-id', $ConversationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($TitleContains)) {
        $arguments += @('--title-contains', $TitleContains)
    }
    if ($NewChat) {
        $arguments += '--new-chat'
    }
    if ($ExportHistoryBefore) {
        $arguments += '--export-history-before'
    }
    if (-not [string]::IsNullOrWhiteSpace($ResultName)) {
        $arguments += @('--result-name', $ResultName)
    }
    if ($null -ne $AttachmentPath) {
        foreach ($path in $AttachmentPath) {
            if ([string]::IsNullOrWhiteSpace($path)) {
                continue
            }
            $resolvedAttachment = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
            $arguments += @('--attachment', $resolvedAttachment)
        }
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function Remove-CodexChatGptConversation {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://chatgpt.com/',
        [string]$PageUrlContains = 'chatgpt.com',
        [string]$ConversationId,
        [string]$TitleContains,
        [switch]$CurrentChat,
        [string]$ExportDir,
        [switch]$Force,
        [int]$Port = 9222
    )

    if (-not $Force) {
        throw 'Deleting a ChatGPT conversation is destructive. Rerun with -Force after verifying the target.'
    }

    if (-not $CurrentChat -and [string]::IsNullOrWhiteSpace($ConversationId) -and [string]::IsNullOrWhiteSpace($TitleContains)) {
        throw 'Provide -ConversationId, -TitleContains, or -CurrentChat.'
    }

    $arguments = @('chatgpt-delete', '--cdp', "http://127.0.0.1:$Port", '--confirm-delete')
    if (-not $CurrentChat -and -not [string]::IsNullOrWhiteSpace($Url)) {
        $arguments += @('--url', $Url)
    }
    if (-not [string]::IsNullOrWhiteSpace($PageUrlContains)) {
        $arguments += @('--page-url-contains', $PageUrlContains)
    }
    if (-not [string]::IsNullOrWhiteSpace($ConversationId)) {
        $arguments += @('--conversation-id', $ConversationId)
    }
    if (-not [string]::IsNullOrWhiteSpace($TitleContains)) {
        $arguments += @('--title-contains', $TitleContains)
    }
    if ($CurrentChat) {
        $arguments += '--current-chat'
    }
    if (-not [string]::IsNullOrWhiteSpace($ExportDir)) {
        $resolvedExportDir = Resolve-CodexExistingDirectory -Path $ExportDir -Label 'ChatGPT export directory'
        $arguments += @('--export-dir', $resolvedExportDir)
    }

    Invoke-CodexAuthHelper -Arguments $arguments
}

function New-CodexMoodleSpec {
    [CmdletBinding()]
    param(
        [string]$Url,
        [string]$PageUrlContains,
        [string]$OutFile,
        [int]$Port = 9222,
        [int]$Limit
    )

    New-CodexAuthSpec -Site 'moodle' -Url $Url -PageUrlContains $PageUrlContains -OutFile $OutFile -Port $Port -Limit $Limit
}

function New-CodexSharePointSpec {
    [CmdletBinding()]
    param(
        [string]$Url,
        [string]$PageUrlContains,
        [string]$OutFile,
        [int]$Port = 9222,
        [int]$Limit
    )

    New-CodexAuthSpec -Site 'sharepoint' -Url $Url -PageUrlContains $PageUrlContains -OutFile $OutFile -Port $Port -Limit $Limit
}

function New-CodexPanoptoSpec {
    [CmdletBinding()]
    param(
        [string]$Url,
        [string]$PageUrlContains,
        [string]$OutFile,
        [int]$Port = 9222,
        [int]$Limit
    )

    New-CodexAuthSpec -Site 'panopto' -Url $Url -PageUrlContains $PageUrlContains -OutFile $OutFile -Port $Port -Limit $Limit
}

function Invoke-CodexMoodleDump {
    [CmdletBinding()]
    param(
        [string]$Url,
        [string]$PageUrlContains,
        [string]$DestinationDir = (Get-Location).Path,
        [string]$RootName,
        [string]$SpecPath,
        [string]$ManifestPath,
        [int]$Port = 9222,
        [int]$Limit
    )

    Invoke-CodexAuthDump -Site 'moodle' -Url $Url -PageUrlContains $PageUrlContains -DestinationDir $DestinationDir -RootName $RootName -SpecPath $SpecPath -ManifestPath $ManifestPath -Port $Port -Limit $Limit
}

function Invoke-CodexSharePointDump {
    [CmdletBinding()]
    param(
        [string]$Url,
        [string]$PageUrlContains,
        [string]$DestinationDir = (Get-Location).Path,
        [string]$RootName,
        [string]$SpecPath,
        [string]$ManifestPath,
        [int]$Port = 9222,
        [int]$Limit
    )

    Invoke-CodexAuthDump -Site 'sharepoint' -Url $Url -PageUrlContains $PageUrlContains -DestinationDir $DestinationDir -RootName $RootName -SpecPath $SpecPath -ManifestPath $ManifestPath -Port $Port -Limit $Limit
}

function Invoke-CodexPanoptoDump {
    [CmdletBinding()]
    param(
        [string]$Url,
        [string]$PageUrlContains,
        [string]$DestinationDir = (Get-Location).Path,
        [string]$RootName,
        [string]$SpecPath,
        [string]$ManifestPath,
        [int]$Port = 9222,
        [int]$Limit
    )

    Invoke-CodexAuthDump -Site 'panopto' -Url $Url -PageUrlContains $PageUrlContains -DestinationDir $DestinationDir -RootName $RootName -SpecPath $SpecPath -ManifestPath $ManifestPath -Port $Port -Limit $Limit
}

function Show-CodexAuthHelp {
    [CmdletBinding()]
    param()

    @'
Codex web-auth helpers

1. Start a logged-in browser with CDP enabled:
   auth-browser -Browser edge -ForceRestart -Url https://example.com

2. Export links from the current authenticated page:
   auth-links -PageUrlContains example.com/dashboard -OutFile .\links.json

3. Infer a structured download spec from the current page:
   auth-spec -Site auto -PageUrlContains example.com/dashboard -OutFile .\download_spec.json
   auth-moodle-spec -PageUrlContains moodle.ucl.ac.uk/course/view.php?id=123

4. Save one authenticated resource:
   auth-save -Url https://example.com/file/123 -DestinationDir .\Downloads -Mode auto
   auth-save -Url https://moodle.ucl.ac.uk/mod/quiz/view.php?id=123 -DestinationDir .\QuizDump -Mode quiz

5. Save a page as HTML:
   auth-html -Url https://example.com/notes/1 -DestinationDir .\Pages

6. Run a batch download spec:
   auth-batch -SpecPath .\downloads.json -DestinationDir .\SiteDump -ManifestPath .\manifest.json

7. Do the whole flow in one command:
   auth-dump -Site moodle -PageUrlContains moodle.ucl.ac.uk/course/view.php?id=123 -DestinationDir .\Exports
   auth-moodle-dump -PageUrlContains moodle.ucl.ac.uk/course/view.php?id=123 -DestinationDir .\Exports
   auth-sharepoint-dump -PageUrlContains sharepoint.com -DestinationDir .\Exports
   auth-panopto-dump -PageUrlContains panopto.com -DestinationDir .\Exports
   auth-chatgpt-dump -DestinationDir C:\Exports -Keyword 'study','UCL','lecture' -TopicLabel learning
   auth-chatgpt-dump -DestinationDir C:\Exports -Keyword 'car','cars','automobile' -TopicLabel cars
   auth-chatgpt-dump -DestinationDir C:\Exports -Keyword 'peony','flower','garden' -TopicLabel flowers
   auth-chatgpt-dump -DestinationDir C:\Exports -SaveAll
   auth-chatgpt-study-dump -DestinationDir C:\Exports

8. Use -Limit for a small smoke test before a full site dump:
   auth-dump -Site moodle -PageUrlContains moodle.ucl.ac.uk/course/view.php?id=123 -DestinationDir .\Test -Limit 5
   auth-chatgpt-dump -DestinationDir C:\Exports -Keyword 'UCL','physics' -TopicLabel learning -Limit 12

10. ChatGPT control helpers:
   auth-chatgpt-list -Limit 20
   auth-chatgpt-open -NewChat
   auth-chatgpt-open -TitleContains 'Atomic Physics'
   auth-chatgpt-save -DestinationDir C:\Exports -TitleContains 'Atomic Physics'
   auth-chatgpt-delete -TitleContains 'Atomic Physics' -Force
   auth-chatgpt-delete -CurrentChat -ExportDir C:\Exports -Force
   auth-chatgpt-ask -NewChat -Prompt 'Summarize atomic orbitals.' -DestinationDir C:\Exports
   auth-chatgpt-ask -TitleContains 'Atomic Physics' -Prompt 'Continue from the previous derivation.' -DestinationDir C:\Exports -ExportHistoryBefore
   auth-chatgpt-ask -NewChat -Prompt 'Read the attached file and summarize it.' -AttachmentPath C:\Docs\notes.pdf,C:\Pics\diagram.png -DestinationDir C:\Exports

9. ChatGPT safety note:
   Broad keywords and -SaveAll can touch too many conversations too quickly.
   That may trigger temporary ChatGPT protections or temporary closures.
   If you omit -Limit on a broad ChatGPT export, the tool now auto-caps to a smaller sample and warns first.
   ChatGPT export/ask commands now expect an existing destination directory. If the directory does not exist, they fail fast.
   ChatGPT browser actions are now rate-limited by default across commands, so repeated list/open/ask/delete runs are spaced out automatically.
   If ChatGPT shows a Too many requests dialog, the tool now tries to click Got it and waits about 10 seconds before retrying.
   ChatGPT deletion now prefers an authenticated API path first and only falls back to UI actions when needed.
   The page helper now injects reduced-motion styles and hides common floating overlays that intercept clicks.
   ChatGPT deletion is destructive. Use auth-chatgpt-delete with -Force, and optionally -ExportDir to back up the chat before removing it.

Batch spec example:
[
  { "url": "https://example.com/file/123", "directory": "Week 1\\Files", "mode": "auto" },
  { "url": "https://example.com/page/456", "directory": "Week 1\\Pages", "mode": "page", "filename": "overview" },
  { "url": "https://example.com/video/789", "directory": "Week 1\\Links", "mode": "shortcut", "filename": "video" },
  { "url": "https://example.com/folder/321", "directory": "Week 1\\Folder Materials", "mode": "folder" }
]
'@ | Write-Host
}

Set-Alias -Name auth-browser -Value Start-CodexAuthBrowser -Scope Global -Option AllScope -Force
Set-Alias -Name auth-links -Value Export-CodexAuthLinks -Scope Global -Option AllScope -Force
Set-Alias -Name auth-spec -Value New-CodexAuthSpec -Scope Global -Option AllScope -Force
Set-Alias -Name auth-save -Value Save-CodexAuthContent -Scope Global -Option AllScope -Force
Set-Alias -Name auth-html -Value Save-CodexAuthPage -Scope Global -Option AllScope -Force
Set-Alias -Name auth-batch -Value Invoke-CodexAuthBatchDownload -Scope Global -Option AllScope -Force
Set-Alias -Name auth-dump -Value Invoke-CodexAuthDump -Scope Global -Option AllScope -Force
Set-Alias -Name auth-moodle-spec -Value New-CodexMoodleSpec -Scope Global -Option AllScope -Force
Set-Alias -Name auth-sharepoint-spec -Value New-CodexSharePointSpec -Scope Global -Option AllScope -Force
Set-Alias -Name auth-panopto-spec -Value New-CodexPanoptoSpec -Scope Global -Option AllScope -Force
Set-Alias -Name auth-moodle-dump -Value Invoke-CodexMoodleDump -Scope Global -Option AllScope -Force
Set-Alias -Name auth-sharepoint-dump -Value Invoke-CodexSharePointDump -Scope Global -Option AllScope -Force
Set-Alias -Name auth-panopto-dump -Value Invoke-CodexPanoptoDump -Scope Global -Option AllScope -Force
Set-Alias -Name auth-chatgpt-dump -Value Export-CodexChatGptDump -Scope Global -Option AllScope -Force
Set-Alias -Name auth-chatgpt-export -Value Export-CodexChatGptDump -Scope Global -Option AllScope -Force
Set-Alias -Name auth-chatgpt-study-dump -Value Export-CodexChatGptLearningDump -Scope Global -Option AllScope -Force
Set-Alias -Name auth-chatgpt-list -Value Get-CodexChatGptConversationList -Scope Global -Option AllScope -Force
Set-Alias -Name auth-chatgpt-open -Value Open-CodexChatGptConversation -Scope Global -Option AllScope -Force
Set-Alias -Name auth-chatgpt-save -Value Save-CodexChatGptConversation -Scope Global -Option AllScope -Force
Set-Alias -Name auth-chatgpt-ask -Value Invoke-CodexChatGptPrompt -Scope Global -Option AllScope -Force
Set-Alias -Name auth-chatgpt-delete -Value Remove-CodexChatGptConversation -Scope Global -Option AllScope -Force
Set-Alias -Name auth-help -Value Show-CodexAuthHelp -Scope Global -Option AllScope -Force
