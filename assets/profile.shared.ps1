if ($global:CodexShellProfileLoaded) {
    return
}

$global:CodexShellProfileLoaded = $true

function Get-CodexDocumentsRoot {
    return [Environment]::GetFolderPath('MyDocuments')
}

function Get-CodexPowerShellProfileRoot {
    return (Join-Path (Get-CodexDocumentsRoot) 'PowerShell')
}

function Get-RegisteredPathEntries {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Machine', 'User')]
        [string]$Scope
    )

    $rawValue = [Environment]::GetEnvironmentVariable('Path', $Scope)
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        return @()
    }

    return $rawValue -split ';'
}

function Get-CodexPowerShellRoot {
    $candidates = New-Object System.Collections.Generic.List[string]
    $documentsRoot = Get-CodexDocumentsRoot

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_POWERSHELL_ROOT)) {
        [void]$candidates.Add($env:CODEX_POWERSHELL_ROOT)
    }

    [void]$candidates.Add((Join-Path $documentsRoot 'PowerShell\Toolkit'))
    [void]$candidates.Add((Join-Path $documentsRoot 'PowerShell\Codex'))
    [void]$candidates.Add((Join-Path $HOME 'Documents\PowerShell\Toolkit'))
    [void]$candidates.Add((Join-Path $HOME 'Documents\PowerShell\Codex'))

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $trimmed = $candidate.TrimEnd('\')
        $key = $trimmed.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        if (Test-Path -LiteralPath $trimmed) {
            return $trimmed
        }
    }

    return (Join-Path $documentsRoot 'PowerShell\Toolkit')
}

function Get-CodexPowerShellBinPath {
    return (Join-Path (Get-CodexPowerShellRoot) 'bin')
}

function Get-CodexPowerShellDocCacheRoot {
    return (Join-Path (Join-Path (Get-CodexPowerShellRoot) 'cache') 'doc-cache')
}

function Get-CodexTorchLibPath {
    return (Join-Path (Join-Path (Join-Path (Get-CodexPowerShellRoot) 'venvs\ocr311') 'Lib\site-packages\torch') 'lib')
}

function Get-CodexPreferredPathEntries {
    $entries = New-Object System.Collections.Generic.List[string]
    $codexBin = Get-CodexPowerShellBinPath
    $torchLib = Get-CodexTorchLibPath

    if (Test-Path -LiteralPath $codexBin) {
        [void]$entries.Add($codexBin)
    }

    if (Test-Path -LiteralPath $torchLib) {
        [void]$entries.Add($torchLib)
    }

    return $entries
}

function Get-CodexCliExecutablePath {
    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_DESKTOP_EXE)) {
        [void]$candidates.Add($env:CODEX_DESKTOP_EXE)
    }

    [void]$candidates.Add((Join-Path $HOME '.codex\.sandbox-bin\codex.exe'))

    $codexExeMatches = @(Get-Command 'codex.exe' -All -ErrorAction SilentlyContinue)
    foreach ($match in $codexExeMatches) {
        if (-not [string]::IsNullOrWhiteSpace($match.Path)) {
            [void]$candidates.Add($match.Path)
        }
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $key = $candidate.Trim().ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-CodexDesktopResourcesPath {
    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_DESKTOP_RESOURCES)) {
        [void]$candidates.Add($env:CODEX_DESKTOP_RESOURCES)
    }

    $codexExeMatches = @(Get-Command 'codex.exe' -All -ErrorAction SilentlyContinue)
    foreach ($match in $codexExeMatches) {
        if (-not [string]::IsNullOrWhiteSpace($match.Path)) {
            [void]$candidates.Add((Split-Path -Path $match.Path -Parent))
        }
    }

    $windowsAppsRoot = Join-Path $env:ProgramFiles 'WindowsApps'
    if (Test-Path -LiteralPath $windowsAppsRoot) {
        $packageDirs = @(Get-ChildItem -LiteralPath $windowsAppsRoot -Directory -Filter 'OpenAI.Codex_*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending)
        foreach ($dir in $packageDirs) {
            [void]$candidates.Add((Join-Path $dir.FullName 'app\resources'))
        }
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $trimmed = $candidate.TrimEnd('\')
        $key = $trimmed.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        $codexExePath = Join-Path $trimmed 'codex.exe'
        if (Test-Path -LiteralPath $codexExePath) {
            return $trimmed
        }
    }

    return $null
}

function Merge-PathEntries {
    param(
        [string[]]$Entries
    )

    $seen = @{}
    $merged = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $Entries) {
        $candidate = if ($null -eq $entry) { '' } else { $entry.Trim() }
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        if ([string]::IsNullOrWhiteSpace($expanded)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $expanded)) {
            continue
        }

        $key = $expanded.TrimEnd('\').ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = $expanded.ToLowerInvariant()
        }

        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        [void]$merged.Add($expanded)
    }

    return $merged
}

function Test-CodexCommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Test-CodexModuleAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne (Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Import-CodexOptionalModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-CodexModuleAvailable -Name $Name)) {
        return $false
    }

    try {
        Import-Module $Name -Global -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-CodexStarshipConfigPath {
    return (Join-Path (Join-Path (Get-CodexPowerShellRoot) 'config') 'starship.toml')
}

function Test-CodexConsoleHost {
    return $Host.Name -match 'ConsoleHost|Visual Studio Code Host'
}

function Get-CommandTarget {
    param(
        $Command
    )

    if ($null -eq $Command) {
        return 'missing'
    }

    switch ($Command.CommandType) {
        'Alias' {
            return $Command.Definition
        }
        'Application' {
            if (-not [string]::IsNullOrWhiteSpace($Command.Source)) {
                return $Command.Source
            }

            if ($Command.Path) {
                return $Command.Path
            }

            return 'application'
        }
        'Function' {
            if ($Command.Name -eq 'codex') {
                $codexCli = Get-CodexCliExecutablePath
                if (-not [string]::IsNullOrWhiteSpace($codexCli)) {
                    return $codexCli
                }
            }
            if ($Command.Name -in @('apply_patch', 'applypatch', 'codex-command-runner')) {
                return (Join-Path (Get-CodexPowerShellBinPath) ("{0}.cmd" -f $Command.Name))
            }
            return '<function>'
        }
        default {
            if (-not [string]::IsNullOrWhiteSpace($Command.Source)) {
                return $Command.Source
            }

            if ($Command.Definition) {
                return $Command.Definition
            }

            return $Command.CommandType.ToString()
        }
    }
}

function Get-ResolvedCommandSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        return "$Name=missing"
    }

    $target = Get-CommandTarget -Command $command
    return "$Name=$($command.CommandType):$target"
}

function Set-NativeCommandAlias {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AliasName,

        [Parameter(Mandatory = $true)]
        [string]$ExecutableName
    )

    $nativeCommand = Get-Command $ExecutableName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $nativeCommand) {
        return $false
    }

    Remove-Item -Path "Alias:$AliasName" -Force -ErrorAction SilentlyContinue
    Set-Alias -Name $AliasName -Value $ExecutableName -Scope Global -Option AllScope -Force
    return $true
}

function Sync-CodexPath {
    $preferredPathEntries = Get-CodexPreferredPathEntries
    $machinePathEntries = Get-RegisteredPathEntries -Scope Machine
    $userPathEntries = Get-RegisteredPathEntries -Scope User
    $processPathEntries = if ([string]::IsNullOrWhiteSpace($env:Path)) { @() } else { $env:Path -split ';' }

    $allPathEntries = @($preferredPathEntries + $machinePathEntries + $userPathEntries + $processPathEntries)
    $mergedPathEntries = Merge-PathEntries -Entries $allPathEntries

    if ($mergedPathEntries.Count -gt 0) {
        $env:Path = [string]::Join(';', $mergedPathEntries)
    }
}

function Set-NativeCommandAliases {
    [void](Set-NativeCommandAlias -AliasName 'curl' -ExecutableName 'curl.exe')
    [void](Set-NativeCommandAlias -AliasName 'wget' -ExecutableName 'wget.exe')
    [void](Set-NativeCommandAlias -AliasName 'capture2text' -ExecutableName 'Capture2Text_CLI.exe')
}

function Initialize-CodexReadLine {
    if (-not (Test-CodexConsoleHost)) {
        return
    }

    try {
        Import-Module PSReadLine -ErrorAction Stop | Out-Null
        $predictionSource = 'History'
        if (Import-CodexOptionalModule -Name 'CompletionPredictor') {
            $predictionSource = 'HistoryAndPlugin'
        }

        Set-PSReadLineOption -PredictionSource $predictionSource -PredictionViewStyle ListView -HistorySearchCursorMovesToEnd
        Set-PSReadLineOption -EditMode Windows
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
        Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteCharOrExit
        Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -Function ReverseSearchHistory
        $env:CODEX_READLINE_MODE = "$predictionSource/ListView"
    } catch {
        $env:CODEX_READLINE_MODE = 'basic'
    }

    if (Import-CodexOptionalModule -Name 'PSFzf') {
        try {
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
            $env:CODEX_FZF_MODE = 'PSFzf'
        } catch {
            $env:CODEX_FZF_MODE = 'fzf'
        }
    } else {
        $env:CODEX_FZF_MODE = 'fzf'
    }
}

function Initialize-CodexOptionalModules {
    $loadedModules = New-Object System.Collections.Generic.List[string]

    if (Import-CodexOptionalModule -Name 'Terminal-Icons') {
        [void]$loadedModules.Add('Terminal-Icons')
    }

    if (Import-CodexOptionalModule -Name 'posh-git') {
        [void]$loadedModules.Add('posh-git')
    }

    $env:CODEX_IMPORTED_MODULES = [string]::Join(', ', $loadedModules.ToArray())
}

function Initialize-CodexToolAliases {
    function global:mkcd {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            [string]$Path
        )

        $created = New-Item -ItemType Directory -Path $Path -Force
        Set-Location -LiteralPath $created.FullName
    }

    function global:.. { Set-Location .. }
    function global:... { Set-Location ../.. }

    if (Test-CodexCommandAvailable -Name 'eza') {
        function global:ll {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [string[]]$Arguments = @()
            )

            & eza -lah --group-directories-first --icons=auto @Arguments
        }

        function global:la {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [string[]]$Arguments = @()
            )

            & eza -la --group-directories-first --icons=auto @Arguments
        }

        function global:lt {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [string[]]$Arguments = @()
            )

            & eza --tree --level=2 --group-directories-first --icons=auto @Arguments
        }
    }

    if (Test-CodexCommandAvailable -Name 'zoxide') {
        try {
            Invoke-Expression (& zoxide init powershell --cmd z | Out-String)
            $env:CODEX_NAV_MODE = 'zoxide'
        } catch {
            $env:CODEX_NAV_MODE = 'basic'
        }
    } else {
        $env:CODEX_NAV_MODE = 'basic'
    }

    if (Test-CodexCommandAvailable -Name 'lazygit') {
        Set-Alias -Name lg -Value lazygit -Scope Global -Option AllScope -Force
    }

    if (Test-CodexCommandAvailable -Name 'just') {
        Set-Alias -Name j -Value just -Scope Global -Option AllScope -Force
    }

    if (Test-CodexCommandAvailable -Name 'hyperfine') {
        Set-Alias -Name bench -Value hyperfine -Scope Global -Option AllScope -Force
    }
}

function Initialize-CodexPrompt {
    if (-not (Test-CodexConsoleHost)) {
        $env:CODEX_PROMPT_MODE = 'default'
        return
    }

    $starshipConfig = Get-CodexStarshipConfigPath
    if (-not (Test-CodexCommandAvailable -Name 'starship') -or -not (Test-Path -LiteralPath $starshipConfig)) {
        $env:CODEX_PROMPT_MODE = 'default'
        return
    }

    try {
        $env:STARSHIP_CONFIG = $starshipConfig
        Invoke-Expression (& starship init powershell | Out-String)
        $env:CODEX_PROMPT_MODE = 'starship'
    } catch {
        $env:CODEX_PROMPT_MODE = 'default'
    }
}

$codexProfileRoot = Get-CodexPowerShellProfileRoot

$codexWebAuthProfile = Join-Path $codexProfileRoot 'codex.web-auth-tools.ps1'
if (Test-Path -LiteralPath $codexWebAuthProfile) {
    . $codexWebAuthProfile
}

$codexNetworkToolsProfile = Join-Path $codexProfileRoot 'codex.network-tools.ps1'
if (Test-Path -LiteralPath $codexNetworkToolsProfile) {
    . $codexNetworkToolsProfile
}

$codexDocumentToolsProfile = Join-Path $codexProfileRoot 'codex.document-tools.ps1'
if (Test-Path -LiteralPath $codexDocumentToolsProfile) {
    . $codexDocumentToolsProfile
}

$codexOcrTranslateProfile = Join-Path $codexProfileRoot 'codex.ocr-translate-tools.ps1'
if (Test-Path -LiteralPath $codexOcrTranslateProfile) {
    . $codexOcrTranslateProfile
}

function Invoke-CodexPowerShellWrapper {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tool,

        [string[]]$Arguments = @()
    )

    $wrapperPath = Join-Path (Get-CodexPowerShellBinPath) ("{0}.cmd" -f $Tool)
    if (-not (Test-Path -LiteralPath $wrapperPath)) {
        if ($Tool -eq 'codex') {
            $codexCli = Get-CodexCliExecutablePath
            if (-not [string]::IsNullOrWhiteSpace($codexCli)) {
                & $codexCli @Arguments
                return
            }
        }

        throw "Codex wrapper not found: $wrapperPath"
    }

    & $wrapperPath @Arguments
}

function codex {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments = @()
    )

    Invoke-CodexPowerShellWrapper -Tool 'codex' -Arguments $Arguments
}

function apply_patch {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments = @()
    )

    Invoke-CodexPowerShellWrapper -Tool 'apply_patch' -Arguments $Arguments
}

function applypatch {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments = @()
    )

    Invoke-CodexPowerShellWrapper -Tool 'applypatch' -Arguments $Arguments
}

function codex-command-runner {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments = @()
    )

    Invoke-CodexPowerShellWrapper -Tool 'codex-command-runner' -Arguments $Arguments
}

function Get-CodexHintEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [string]$Example
    )

    if (-not (Test-CodexCommandAvailable -Name $Name)) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Example)) {
        return ('  {0,-14} {1}' -f $Name, $Description)
    }

    return ('  {0,-14} {1}  e.g. {2}' -f $Name, $Description, $Example)
}

function Update-CodexPowerShellMetadata {
    $hintParts = @(
        (Get-ResolvedCommandSummary -Name 'codehint'),
        (Get-ResolvedCommandSummary -Name 'whichall'),
        (Get-ResolvedCommandSummary -Name 'refresh-path'),
        (Get-ResolvedCommandSummary -Name 'll'),
        (Get-ResolvedCommandSummary -Name 'z'),
        (Get-ResolvedCommandSummary -Name 'grepcode'),
        (Get-ResolvedCommandSummary -Name 'json'),
        (Get-ResolvedCommandSummary -Name 'yaml'),
        (Get-ResolvedCommandSummary -Name 'lazygit'),
        (Get-ResolvedCommandSummary -Name 'just'),
        (Get-ResolvedCommandSummary -Name 'hyperfine'),
        (Get-ResolvedCommandSummary -Name 'ocr-smart'),
        (Get-ResolvedCommandSummary -Name 'pdf-smart'),
        (Get-ResolvedCommandSummary -Name 'translate-smart'),
        (Get-ResolvedCommandSummary -Name 'doc-pipeline'),
        (Get-ResolvedCommandSummary -Name 'study-summary'),
        (Get-ResolvedCommandSummary -Name 'study-pack'),
        (Get-ResolvedCommandSummary -Name 'auth-browser'),
        (Get-ResolvedCommandSummary -Name 'auth-recover'),
        (Get-ResolvedCommandSummary -Name 'auth-extension-list'),
        (Get-ResolvedCommandSummary -Name 'git'),
        (Get-ResolvedCommandSummary -Name 'rg')
    )

    $helperNames = @(
        'codehint', 'whichall', 'refresh-path', 'mkcd', 'll', 'la', 'lt', 'z', 'zi', 'lg', 'j', 'bench',
        'json', 'yaml', 'grepcode', 'proxy-profile-set', 'proxy-profile-show', 'proxy-profile-clear',
        'remote-client-init', 'remote-server-bundle', 'remote-health', 'ss-source-show', 'ss-secret-discover', 'ss-secret-import', 'ss-secret-clear', 'ss-profile-new', 'ss-client-fetch', 'ss-client-open', 'ss-server-bundle',
        'ocr-smart', 'pdf-smart', 'translate-smart', 'doc-pipeline', 'doc-scan',
        'doc-batch', 'doc-config', 'doc-help', 'ocr-models', 'study-summary', 'study-pack', 'auth-browser', 'auth-links', 'auth-spec',
        'auth-save', 'auth-html', 'auth-batch', 'auth-dump', 'auth-recover', 'auth-chatgpt-browser', 'auth-chatgpt-dump', 'auth-chatgpt-export',
        'auth-chatgpt-study-dump', 'auth-chatgpt-list', 'auth-chatgpt-open', 'auth-chatgpt-save',
        'auth-chatgpt-ask', 'auth-chatgpt-delete', 'auth-extension-install', 'auth-extension-list',
        'auth-extension-enable', 'auth-extension-disable', 'auth-extension-open', 'auth-extension-click',
        'auth-extension-remove', 'auth-help'
    )

    $env:CODEX_POWERSHELL_HINTS = [string]::Join(' | ', $hintParts)
    $env:CODEX_POWERSHELL_HELPERS = [string]::Join(', ', $helperNames)
    $env:CODEX_POWERSHELL_TOOLBELT = 'rg fd fzf jq yq eza zoxide starship lazygit just hyperfine 7z sd uv pnpm xh mise dust procs'
}

function Show-CodexShellHints {
    [CmdletBinding()]
    param()

    Update-CodexPowerShellMetadata

    Write-Host 'Codex PowerShell hints' -ForegroundColor Cyan

    $sections = @(
        @{
            Title = 'Shell'
            Entries = @(
                (Get-CodexHintEntry -Name 'codehint' -Description 'show this toolbox summary again'),
                (Get-CodexHintEntry -Name 'whichall' -Description 'resolve where a command comes from' -Example 'whichall git rg z'),
                (Get-CodexHintEntry -Name 'refresh-path' -Description 'reload PATH and helper bindings'),
                (Get-CodexHintEntry -Name 'mkcd' -Description 'create a directory and jump into it' -Example 'mkcd scratch'),
                (Get-CodexHintEntry -Name 'll' -Description 'rich directory listing with icons'),
                (Get-CodexHintEntry -Name 'lt' -Description '2-level tree view for quick scans')
            )
        },
        @{
            Title = 'Search / Data'
            Entries = @(
                (Get-CodexHintEntry -Name 'rg' -Description 'fast recursive search' -Example 'rg TODO src'),
                (Get-CodexHintEntry -Name 'grepcode' -Description 'repo-friendly search wrapper' -Example "grepcode 'Install-' ."),
                (Get-CodexHintEntry -Name 'json' -Description 'pretty-print JSON from file or pipeline'),
                (Get-CodexHintEntry -Name 'yaml' -Description 'pretty-print YAML or JSON through yq'),
                (Get-CodexHintEntry -Name 'sd' -Description 'streamlined search-and-replace' -Example "sd 'foo' 'bar' README.md")
            )
        },
        @{
            Title = 'Navigation / Dev'
            Entries = @(
                (Get-CodexHintEntry -Name 'z' -Description 'jump to frequently used directories' -Example 'z toolkit'),
                (Get-CodexHintEntry -Name 'lazygit' -Description 'interactive git UI' -Example 'lg'),
                (Get-CodexHintEntry -Name 'just' -Description 'run project recipes' -Example 'j test'),
                (Get-CodexHintEntry -Name 'hyperfine' -Description 'benchmark commands' -Example "bench 'npm test' 'pnpm test'"),
                (Get-CodexHintEntry -Name '7z' -Description 'archive and extract from shell')
            )
        },
        @{
            Title = 'Remote / Network'
            Entries = @(
                (Get-CodexHintEntry -Name 'remote-client-init' -Description 'write a resilient SSH client baseline and host alias' -Example 'remote-client-init -HostAlias labbox -HostName 203.0.113.10 -User admin'),
                (Get-CodexHintEntry -Name 'remote-server-bundle' -Description 'generate a deployable Windows OpenSSH server bundle'),
                (Get-CodexHintEntry -Name 'remote-health' -Description 'measure DNS and TCP reachability for a host' -Example 'remote-health -Host github.com -Port 22'),
                (Get-CodexHintEntry -Name 'ss-source-show' -Description 'read lia.txt and show official Shadowsocks sources plus latest releases'),
                (Get-CodexHintEntry -Name 'ss-secret-discover' -Description 'look for local-only Shadowsocks secrets in env vars, private files, or existing client configs'),
                (Get-CodexHintEntry -Name 'ss-secret-import' -Description 'import a local-only Shadowsocks secret into toolkit state without exposing it in the repo' -Example 'ss-secret-import -FetchWindowsClient -ExpandWindowsClient'),
                (Get-CodexHintEntry -Name 'ss-secret-clear' -Description 'remove the local active Shadowsocks secret file'),
                (Get-CodexHintEntry -Name 'ss-profile-new' -Description 'generate official Shadowsocks client/server JSON plus SIP002 URI' -Example 'ss-profile-new -Name dorm-link -Server 203.0.113.8'),
                (Get-CodexHintEntry -Name 'ss-client-fetch' -Description 'download the official Windows Shadowsocks client into toolkit state' -Example 'ss-client-fetch -Expand'),
                (Get-CodexHintEntry -Name 'ss-server-bundle' -Description 'generate a pinned shadowsocks-rust Linux server bundle'),
                (Get-CodexHintEntry -Name 'proxy-profile-show' -Description 'show the current redacted proxy profile'),
                (Get-CodexHintEntry -Name 'proxy-profile-set' -Description 'store proxy settings safely in the toolkit config' -Example 'proxy-profile-set -HttpsProxy http://proxy.example:8080 -NoProxy localhost,127.0.0.1')
            )
        },
        @{
            Title = 'Docs / OCR'
            Entries = @(
                (Get-CodexHintEntry -Name 'ocr-smart' -Description 'smart OCR for images and screenshots'),
                (Get-CodexHintEntry -Name 'pdf-smart' -Description 'smart PDF extraction / OCR'),
                (Get-CodexHintEntry -Name 'translate-smart' -Description 'translate extracted content'),
                (Get-CodexHintEntry -Name 'doc-pipeline' -Description 'route documents through the full pipeline'),
                (Get-CodexHintEntry -Name 'ocr-models' -Description 'inspect installed OCR capabilities'),
                (Get-CodexHintEntry -Name 'study-summary' -Description 'summarize one or more authenticated dump roots' -Example 'study-summary .\CourseDump'),
                (Get-CodexHintEntry -Name 'study-pack' -Description 'build a reusable HTML/Markdown/IPYNB study pack from dump roots' -Example 'study-pack .\CourseA,.\CourseB -OpenHtml')
            )
        },
        @{
            Title = 'Web Auth'
            Entries = @(
                (Get-CodexHintEntry -Name 'auth-browser' -Description 'launch browser automation session'),
                (Get-CodexHintEntry -Name 'auth-spec' -Description 'build a download spec file'),
                (Get-CodexHintEntry -Name 'auth-save' -Description 'save authenticated page content'),
                (Get-CodexHintEntry -Name 'auth-batch' -Description 'batch-download authenticated assets'),
                (Get-CodexHintEntry -Name 'auth-recover' -Description 'recover indirect or wrapper-page resources after a batch dump' -Example 'auth-recover .\CourseDump'),
                (Get-CodexHintEntry -Name 'auth-chatgpt-browser' -Description 'open the dedicated ChatGPT automation browser'),
                (Get-CodexHintEntry -Name 'auth-chatgpt-list' -Description 'list ChatGPT conversations' -Example 'auth-chatgpt-list -Limit 20'),
                (Get-CodexHintEntry -Name 'auth-chatgpt-ask' -Description 'send a prompt and save the result; prompt can be positional, pipeline, or -PromptPath' -Example 'auth-chatgpt-ask -NewChat -DestinationDir C:\Exports "Summarize Newton''s laws."'),
                (Get-CodexHintEntry -Name 'auth-extension-install' -Description 'install an unpacked/zip/CRX browser extension into the managed toolkit state' -Example 'auth-extension-install -DirectoryPath C:\Ext\MyExtension -Name MyExtension'),
                (Get-CodexHintEntry -Name 'auth-extension-open' -Description 'open an installed extension popup/options page inside the managed browser' -Example 'auth-extension-open -Name MyExtension -Surface popup'),
                (Get-CodexHintEntry -Name 'auth-extension-click' -Description 'click a control inside an installed extension page' -Example 'auth-extension-click -Name MyExtension -Surface popup -TextContains "Sign in"'),
                (Get-CodexHintEntry -Name 'auth-help' -Description 'show auth helper help')
            )
        }
    )

    foreach ($section in $sections) {
        $lines = @($section.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -eq 0) {
            continue
        }

        Write-Host ''
        Write-Host ("[{0}]" -f $section.Title) -ForegroundColor Yellow
        foreach ($line in $lines) {
            Write-Host $line
        }
    }

    Write-Host ''
    Write-Host ("Prompt={0} | ReadLine={1} | Modules={2}" -f $env:CODEX_PROMPT_MODE, $env:CODEX_READLINE_MODE, $(if ([string]::IsNullOrWhiteSpace($env:CODEX_IMPORTED_MODULES)) { 'none' } else { $env:CODEX_IMPORTED_MODULES })) -ForegroundColor DarkGray
}

Set-Alias -Name codehint -Value Show-CodexShellHints

function Show-CodexStartupBanner {
    $coreParts = @(
        "prompt=$($env:CODEX_PROMPT_MODE)",
        "predict=$($env:CODEX_READLINE_MODE)",
        "nav=$($env:CODEX_NAV_MODE)",
        'toolbelt: rg fd fzf jq yq eza z lazygit just hyperfine 7z xh mise dust procs',
        'docs: ocr-smart pdf-smart translate-smart doc-pipeline study-summary study-pack auth-browser auth-recover auth-chatgpt-ask auth-extension-open',
        'remote: remote-client-init remote-server-bundle remote-health ss-secret-import ss-profile-new ss-client-fetch',
        'hint: codehint'
    )

    Write-Host "[codex-shell] $([string]::Join(' | ', $coreParts))" -ForegroundColor DarkGray
}

function Test-CodexInteractiveBanner {
    $commandLine = [Environment]::CommandLine
    if ($commandLine -match '(^| )-(Command|EncodedCommand|File)( |$)') {
        return $false
    }

    return $true
}

function whichall {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Name = @('codehint', 'toolkit-inventory', 'codex', 'curl', 'wget', 'capture2text', 'rg', 'git', 'gh', 'node', 'python', 'fd', 'fzf', 'jq', 'yq', 'uv', 'pnpm', 'bat', 'delta', 'eza', 'zoxide', 'starship', 'lazygit', 'just', 'hyperfine', '7z', 'sd', 'xh', 'mise', 'dust', 'procs', 'nougat', 'ocrmypdf', 'pdftotext', 'pdftoppm', 'mutool', 'tesseract', 'Capture2Text_CLI', 'ollama', 'llava', 'easyocr-read', 'paddleocr-read', 'donut-ocr', 'ocr-smart', 'pdf-smart', 'translate-smart', 'doc-pipeline', 'doc-scan', 'doc-batch', 'doc-config', 'doc-help', 'ocr-models', 'study-summary', 'study-pack', 'whichall', 'refresh-path', 'mkcd', 'll', 'la', 'lt', 'z', 'lg', 'j', 'bench', 'json', 'yaml', 'grepcode', 'proxy-profile-set', 'proxy-profile-show', 'proxy-profile-clear', 'remote-client-init', 'remote-server-bundle', 'remote-health', 'ss-source-show', 'ss-secret-discover', 'ss-secret-import', 'ss-secret-clear', 'ss-profile-new', 'ss-client-fetch', 'ss-client-open', 'ss-server-bundle', 'auth-browser', 'auth-links', 'auth-spec', 'auth-save', 'auth-html', 'auth-batch', 'auth-dump', 'auth-recover', 'auth-moodle-spec', 'auth-sharepoint-spec', 'auth-panopto-spec', 'auth-moodle-dump', 'auth-sharepoint-dump', 'auth-panopto-dump', 'auth-chatgpt-browser', 'auth-chatgpt-dump', 'auth-chatgpt-export', 'auth-chatgpt-study-dump', 'auth-chatgpt-list', 'auth-chatgpt-open', 'auth-chatgpt-save', 'auth-chatgpt-ask', 'auth-chatgpt-delete', 'auth-extension-install', 'auth-extension-list', 'auth-extension-enable', 'auth-extension-disable', 'auth-extension-open', 'auth-extension-click', 'auth-extension-remove', 'auth-help')
    )

    foreach ($query in $Name) {
        $matches = Get-Command $query -All -ErrorAction SilentlyContinue
        if ($null -eq $matches -or $matches.Count -eq 0) {
            [pscustomobject]@{
                Query       = $query
                Name        = $query
                CommandType = 'Missing'
                Target      = ''
            }
            continue
        }

        foreach ($match in $matches) {
            [pscustomobject]@{
                Query       = $query
                Name        = $match.Name
                CommandType = $match.CommandType
                Target      = Get-CommandTarget -Command $match
            }
        }
    }
}

function Show-CodexToolkitInventory {
    [CmdletBinding()]
    param()

    $commandGroups = @(
        @{
            Title = 'Toolkit Helpers'
            Names = @('codehint', 'whichall', 'refresh-path', 'mkcd', 'll', 'la', 'lt', 'z', 'lg', 'j', 'bench', 'json', 'yaml', 'grepcode')
        }
        @{
            Title = 'Remote / Network'
            Names = @('proxy-profile-set', 'proxy-profile-show', 'proxy-profile-clear', 'remote-client-init', 'remote-server-bundle', 'remote-health', 'ss-source-show', 'ss-secret-discover', 'ss-secret-import', 'ss-secret-clear', 'ss-profile-new', 'ss-client-fetch', 'ss-client-open', 'ss-server-bundle')
        }
        @{
            Title = 'Core CLI'
            Names = @('git', 'rg', 'fd', 'fzf', 'jq', 'yq', 'uv', 'pnpm', 'bat', 'delta', 'eza', 'zoxide', 'starship', 'lazygit', 'just', 'hyperfine', '7z', 'sd', 'xh', 'mise', 'dust', 'procs')
        }
        @{
            Title = 'Docs / OCR'
            Names = @('ocr-smart', 'pdf-smart', 'translate-smart', 'doc-pipeline', 'doc-scan', 'doc-batch', 'doc-config', 'doc-help', 'ocr-models', 'study-summary', 'study-pack', 'easyocr-read', 'paddleocr-read', 'donut-ocr', 'nougat', 'ocrmypdf', 'pdftotext', 'pdftoppm', 'mutool', 'tesseract')
        }
        @{
            Title = 'Web Auth'
            Names = @('auth-browser', 'auth-links', 'auth-spec', 'auth-save', 'auth-html', 'auth-batch', 'auth-dump', 'auth-recover', 'auth-chatgpt-browser', 'auth-chatgpt-dump', 'auth-chatgpt-export', 'auth-chatgpt-study-dump', 'auth-chatgpt-list', 'auth-chatgpt-open', 'auth-chatgpt-save', 'auth-chatgpt-ask', 'auth-chatgpt-delete', 'auth-extension-install', 'auth-extension-list', 'auth-extension-enable', 'auth-extension-disable', 'auth-extension-open', 'auth-extension-click', 'auth-extension-remove', 'auth-help')
        }
    )

    foreach ($group in $commandGroups) {
        $rows = foreach ($name in $group.Names) {
            $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
            [pscustomobject]@{
                Name        = $name
                Status      = if ($null -eq $command) { 'Missing' } else { 'Available' }
                CommandType = if ($null -eq $command) { '' } else { $command.CommandType }
                Target      = if ($null -eq $command) { '' } else { Get-CommandTarget -Command $command }
            }
        }

        Write-Host ''
        Write-Host ("[{0}]" -f $group.Title) -ForegroundColor Yellow
        $rows | Format-Table Name, Status, CommandType, Target -AutoSize
    }
}

Set-Alias -Name toolkit-inventory -Value Show-CodexToolkitInventory

function refresh-path {
    [CmdletBinding()]
    param()

    Initialize-CodexShell
    Write-Host '[codex-shell] PATH refreshed.' -ForegroundColor Green
    Show-CodexShellHints
}

function json {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        [Parameter(ValueFromPipeline = $true)]
        $InputObject,

        [int]$Depth = 100,

        [switch]$Compress
    )

    begin {
        $items = New-Object System.Collections.Generic.List[object]
    }

    process {
        if ($PSBoundParameters.ContainsKey('InputObject')) {
            [void]$items.Add($InputObject)
        }
    }

    end {
        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            $raw = Get-Content -LiteralPath $Path -Raw
            $raw | ConvertFrom-Json | ConvertTo-Json -Depth $Depth -Compress:$Compress
            return
        }

        if ($items.Count -eq 0) {
            Write-Error 'Provide a JSON file path or pipe JSON/object input into json.'
            return
        }

        $allStrings = $true
        foreach ($item in $items) {
            if ($item -isnot [string]) {
                $allStrings = $false
                break
            }
        }

        if ($allStrings) {
            $rawText = [string]::Join([Environment]::NewLine, [string[]]$items.ToArray())
            $rawText | ConvertFrom-Json | ConvertTo-Json -Depth $Depth -Compress:$Compress
            return
        }

        if ($items.Count -eq 1) {
            $items[0] | ConvertTo-Json -Depth $Depth -Compress:$Compress
            return
        }

        $items.ToArray() | ConvertTo-Json -Depth $Depth -Compress:$Compress
    }
}

function yaml {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )

    begin {
        $items = New-Object System.Collections.Generic.List[object]
    }

    process {
        if ($PSBoundParameters.ContainsKey('InputObject')) {
            [void]$items.Add($InputObject)
        }
    }

    end {
        $yq = Get-Command yq -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $yq) {
            Write-Error 'yq is not available in PATH.'
            return
        }

        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            & $yq.Source -P $Path
            return
        }

        if ($items.Count -eq 0) {
            Write-Error 'Provide a YAML/JSON file path or pipe YAML/JSON/object input into yaml.'
            return
        }

        $allStrings = $true
        foreach ($item in $items) {
            if ($item -isnot [string]) {
                $allStrings = $false
                break
            }
        }

        if ($allStrings) {
            $rawText = [string]::Join([Environment]::NewLine, [string[]]$items.ToArray())
            $rawText | & $yq.Source -P
            return
        }

        if ($items.Count -eq 1) {
            $items[0] | ConvertTo-Json -Depth 100 | & $yq.Source -P
            return
        }

        $items.ToArray() | ConvertTo-Json -Depth 100 | & $yq.Source -P
    }
}

function grepcode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Pattern,

        [Parameter(Position = 1)]
        [string]$Path = '.',

        [switch]$CaseSensitive,

        [switch]$Literal,

        [switch]$Word
    )

    $rg = Get-Command rg -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $rg) {
        Write-Error 'rg is not available in PATH.'
        return
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add('--line-number')
    [void]$arguments.Add('--column')
    [void]$arguments.Add('--hidden')

    if ($CaseSensitive) {
        [void]$arguments.Add('--case-sensitive')
    } else {
        [void]$arguments.Add('--smart-case')
    }

    if ($Literal) {
        [void]$arguments.Add('--fixed-strings')
    }

    if ($Word) {
        [void]$arguments.Add('--word-regexp')
    }

    $excludeGlobs = @(
        '!.git/',
        '!node_modules/',
        '!dist/',
        '!build/',
        '!coverage/',
        '!.next/',
        '!target/',
        '!bin/',
        '!obj/',
        '!out/',
        '!vendor/',
        '!__pycache__/',
        '!.venv/',
        '!venv/'
    )

    foreach ($glob in $excludeGlobs) {
        [void]$arguments.Add('--glob')
        [void]$arguments.Add($glob)
    }

    [void]$arguments.Add('--')
    [void]$arguments.Add($Pattern)
    [void]$arguments.Add($Path)

    & $rg.Source @arguments
}

function Initialize-CodexShell {
    $codexPowerShellRoot = Get-CodexPowerShellRoot
    $codexPowerShellBin = Get-CodexPowerShellBinPath
    $codexDocCacheRoot = Get-CodexPowerShellDocCacheRoot
    $starshipConfig = Get-CodexStarshipConfigPath

    New-Item -ItemType Directory -Force -Path @($codexPowerShellRoot, $codexPowerShellBin, $codexDocCacheRoot, (Split-Path -Parent $starshipConfig)) | Out-Null

    $env:CODEX_POWERSHELL_ROOT = $codexPowerShellRoot
    $env:CODEX_POWERSHELL_BIN = $codexPowerShellBin
    $env:CODEX_APPLY_PATCH = (Join-Path $codexPowerShellBin 'apply_patch.cmd')
    $env:CODEX_APPLYPATCH = (Join-Path $codexPowerShellBin 'applypatch.cmd')
    $env:CODEX_COMMAND_RUNNER = (Join-Path $codexPowerShellBin 'codex-command-runner.cmd')

    $codexCliExecutable = Get-CodexCliExecutablePath
    if (-not [string]::IsNullOrWhiteSpace($codexCliExecutable)) {
        $env:CODEX_DESKTOP_EXE = $codexCliExecutable
    }

    $codexDesktopResources = Get-CodexDesktopResourcesPath
    if (-not [string]::IsNullOrWhiteSpace($codexDesktopResources)) {
        $env:CODEX_DESKTOP_RESOURCES = $codexDesktopResources
    }

    Sync-CodexPath
    Set-NativeCommandAliases
    $env:NO_ALBUMENTATIONS_UPDATE = '1'
    $env:PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK = 'True'
    $env:HF_HUB_DISABLE_SYMLINKS_WARNING = '1'
    $env:TRANSFORMERS_NO_ADVISORY_WARNINGS = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    $env:STARSHIP_CONFIG = $starshipConfig
    if ([string]::IsNullOrWhiteSpace($env:CODEX_DOC_OCR_LANG)) { $env:CODEX_DOC_OCR_LANG = 'eng+chi_sim' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_DOC_TARGET_LANG)) { $env:CODEX_DOC_TARGET_LANG = 'zh' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_DOC_PRIVACY)) { $env:CODEX_DOC_PRIVACY = 'private' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_DOC_ALLOW_CLOUD_PRIVATE)) { $env:CODEX_DOC_ALLOW_CLOUD_PRIVATE = '0' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_DOC_CACHE_ROOT)) { $env:CODEX_DOC_CACHE_ROOT = $codexDocCacheRoot }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_DOC_IMAGE_PROFILE)) { $env:CODEX_DOC_IMAGE_PROFILE = 'auto' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_DOC_PREPROCESS_IMAGES)) { $env:CODEX_DOC_PREPROCESS_IMAGES = '1' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_DOC_SCAN_SAMPLE_CHARS)) { $env:CODEX_DOC_SCAN_SAMPLE_CHARS = '1400' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_AUTH_MIN_REQUEST_INTERVAL_SECONDS)) { $env:CODEX_AUTH_MIN_REQUEST_INTERVAL_SECONDS = '4.5' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_AUTH_REQUEST_INTERVAL_JITTER_SECONDS)) { $env:CODEX_AUTH_REQUEST_INTERVAL_JITTER_SECONDS = '0.75' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_CDP_PORT)) { $env:CODEX_CHATGPT_CDP_PORT = '9333' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_BROWSER)) { $env:CODEX_CHATGPT_BROWSER = 'edge' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_BROWSE_DELAY_SECONDS)) { $env:CODEX_CHATGPT_BROWSE_DELAY_SECONDS = '1.625' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_MUTATION_DELAY_SECONDS)) { $env:CODEX_CHATGPT_MUTATION_DELAY_SECONDS = '4.5' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_DELAY_JITTER_SECONDS)) { $env:CODEX_CHATGPT_DELAY_JITTER_SECONDS = '0.625' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_GOT_IT_COOLDOWN_SECONDS)) { $env:CODEX_CHATGPT_GOT_IT_COOLDOWN_SECONDS = '4.5' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_SIDEBAR_SETTLE_SECONDS)) { $env:CODEX_CHATGPT_SIDEBAR_SETTLE_SECONDS = '1' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_POST_ACTION_SETTLE_SECONDS)) { $env:CODEX_CHATGPT_POST_ACTION_SETTLE_SECONDS = '0.75' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_POLL_INTERVAL_SECONDS)) { $env:CODEX_CHATGPT_POLL_INTERVAL_SECONDS = '0.5' }
    if ([string]::IsNullOrWhiteSpace($env:CODEX_CHATGPT_INLINE_PROMPT_MAX_CHARS)) { $env:CODEX_CHATGPT_INLINE_PROMPT_MAX_CHARS = '3500' }
    Initialize-CodexReadLine
    Initialize-CodexOptionalModules
    Initialize-CodexToolAliases
    Initialize-CodexPrompt
    Update-CodexPowerShellMetadata
}

Initialize-CodexShell
if (Test-CodexInteractiveBanner) {
    Show-CodexStartupBanner
}

