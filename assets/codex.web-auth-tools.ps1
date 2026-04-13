function Get-CodexAuthHelperScriptPath {
    return (Join-Path $HOME 'Documents\PowerShell\Scripts\codex_auth_web.py')
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

8. Use -Limit for a small smoke test before a full site dump:
   auth-dump -Site moodle -PageUrlContains moodle.ucl.ac.uk/course/view.php?id=123 -DestinationDir .\Test -Limit 5

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
Set-Alias -Name auth-help -Value Show-CodexAuthHelp -Scope Global -Option AllScope -Force
