${existingCodexOllamaToolsLoaded} = Get-Variable -Name CodexOllamaToolsLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -ne ${existingCodexOllamaToolsLoaded} -and ${existingCodexOllamaToolsLoaded}.Value) {
    return
}

$global:CodexOllamaToolsLoaded = $true

function Get-CodexOllamaExecutablePath {
    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:OLLAMA_EXE)) {
        [void]$candidates.Add($env:OLLAMA_EXE)
    }

    [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'))

    $matches = @(Get-Command 'ollama.exe' -All -ErrorAction SilentlyContinue)
    foreach ($match in $matches) {
        if (-not [string]::IsNullOrWhiteSpace($match.Path)) {
            [void]$candidates.Add($match.Path)
        }
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        $trimmed = $candidate.Trim()
        $key = $trimmed.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        if (Test-Path -LiteralPath $trimmed) {
            return $trimmed
        }
    }

    return $null
}

function Test-CodexOllamaServerRunning {
    try {
        $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -Method Get -TimeoutSec 2 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Wait-CodexOllamaServer {
    param(
        [int]$TimeoutSeconds = 20
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-CodexOllamaServerRunning) {
            return $true
        }

        Start-Sleep -Milliseconds 300
    }

    return $false
}

function Start-CodexOllamaServer {
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    if (Test-CodexOllamaServerRunning) {
        return
    }

    $ollamaExe = Get-CodexOllamaExecutablePath
    if ([string]::IsNullOrWhiteSpace($ollamaExe)) {
        throw 'Unable to locate ollama.exe.'
    }

    if (-not $Quiet) {
        Write-Host '[ollama] starting local server on demand...' -ForegroundColor DarkGray
    }

    Start-Process -FilePath $ollamaExe -WorkingDirectory (Split-Path -Path $ollamaExe -Parent) -ArgumentList 'serve' -WindowStyle Hidden | Out-Null

    if (-not (Wait-CodexOllamaServer)) {
        throw 'Timed out waiting for the Ollama server to start.'
    }
}

function Test-CodexOllamaCommandRequiresServer {
    param(
        [string[]]$Arguments = @()
    )

    if ($Arguments.Count -eq 0) {
        return $false
    }

    $subcommand = $Arguments[0].ToLowerInvariant()
    return $subcommand -notin @('help', '--help', '-h', 'version', '--version', '-v', 'serve')
}

function Invoke-CodexOllamaCommand {
    param(
        [string[]]$Arguments = @()
    )

    $ollamaExe = Get-CodexOllamaExecutablePath
    if ([string]::IsNullOrWhiteSpace($ollamaExe)) {
        throw 'Unable to locate ollama.exe.'
    }

    if (Test-CodexOllamaCommandRequiresServer -Arguments $Arguments) {
        Start-CodexOllamaServer
    }

    & $ollamaExe @Arguments
}

function global:ollama {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments = @()
    )

    Invoke-CodexOllamaCommand -Arguments $Arguments
}
