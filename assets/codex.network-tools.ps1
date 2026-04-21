function Get-CodexNetworkToolkitRoot {
    [CmdletBinding()]
    param()

    $toolkitRootCommand = Get-Command 'Get-CodexPowerShellRoot' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $toolkitRootCommand) {
        return (Get-CodexPowerShellRoot)
    }

    $documentsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    return (Join-Path $documentsRoot 'PowerShell\Toolkit')
}

function Ensure-CodexNetworkDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    return $Path
}

function Get-CodexNetworkConfigRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexNetworkToolkitRoot) 'config')
}

function Get-CodexNetworkProfilePath {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexNetworkConfigRoot) 'network-profile.json')
}

function Get-CodexNetworkBackupRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Join-Path (Get-CodexNetworkToolkitRoot) 'backups') 'network')
}

function Get-CodexRemoteAccessExampleRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Join-Path (Get-CodexNetworkToolkitRoot) 'examples') 'remote-access-server')
}

function Get-CodexShadowsocksSourceFilePath {
    [CmdletBinding()]
    param()

    $candidate = Join-Path ([Environment]::GetFolderPath('Desktop')) 'lia.txt'
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    return $null
}

function Get-CodexShadowsocksSourceUrls {
    [CmdletBinding()]
    param()

    $fallback = @(
        'https://github.com/shadowsocks',
        'https://shadowsocks.org/'
    )

    $sourceFile = Get-CodexShadowsocksSourceFilePath
    if ($null -eq $sourceFile) {
        return $fallback
    }

    $matches = Select-String -Path $sourceFile -Pattern 'https?://\S+' -AllMatches -ErrorAction SilentlyContinue
    if ($null -eq $matches) {
        return $fallback
    }

    $urls = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches.Matches) {
        $value = $match.Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$urls.Add($value)
        }
    }

    if ($urls.Count -eq 0) {
        return $fallback
    }

    return $urls.ToArray()
}

function Get-CodexShadowsocksConfigRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexNetworkConfigRoot) 'shadowsocks')
}

function Get-CodexShadowsocksProfilesRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexShadowsocksConfigRoot) 'profiles')
}

function Get-CodexShadowsocksStateRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexNetworkToolkitRoot) 'state\shadowsocks')
}

function Get-CodexShadowsocksDownloadsRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexShadowsocksStateRoot) 'downloads')
}

function Get-CodexShadowsocksWindowsClientRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexShadowsocksStateRoot) 'windows-client')
}

function Get-CodexShadowsocksWindowsExecutablePath {
    [CmdletBinding()]
    param()

    $clientRoot = Get-CodexShadowsocksWindowsClientRoot
    if (-not (Test-Path -LiteralPath $clientRoot)) {
        return $null
    }

    $candidate = Get-ChildItem -LiteralPath $clientRoot -Recurse -Filter 'Shadowsocks.exe' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $candidate) {
        return $null
    }

    return $candidate.FullName
}

function Get-CodexShadowsocksWindowsConfigPath {
    [CmdletBinding()]
    param()

    $exePath = Get-CodexShadowsocksWindowsExecutablePath
    if ([string]::IsNullOrWhiteSpace($exePath)) {
        return $null
    }

    return (Join-Path (Split-Path -Parent $exePath) 'gui-config.json')
}

function Get-CodexShadowsocksExampleRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Join-Path (Get-CodexNetworkToolkitRoot) 'examples') 'shadowsocks-rust-server')
}

function Get-CodexShadowsocksPrivateRoot {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexNetworkConfigRoot) 'private')
}

function Get-CodexShadowsocksActiveSecretPath {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexShadowsocksPrivateRoot) 'shadowsocks.active.json')
}

function Get-CodexShadowsocksPrivateCandidatePaths {
    [CmdletBinding()]
    param()

    $desktopRoot = [Environment]::GetFolderPath('Desktop')
    $paths = @(
        (Join-Path $desktopRoot 'lia.private.txt'),
        (Join-Path $desktopRoot 'lia.private.json'),
        (Join-Path $desktopRoot 'lia.secret.txt'),
        (Join-Path $desktopRoot 'lia.secret.json'),
        (Join-Path $desktopRoot 'shadowsocks.private.txt'),
        (Join-Path $desktopRoot 'shadowsocks.private.json'),
        (Join-Path $HOME '.codex\private\shadowsocks.txt'),
        (Join-Path $HOME '.codex\private\shadowsocks.json'),
        (Join-Path $HOME '.config\codex\shadowsocks.txt'),
        (Join-Path $HOME '.config\codex\shadowsocks.json'),
        (Join-Path (Get-CodexShadowsocksPrivateRoot) 'shadowsocks.active.json'),
        (Join-Path $env:APPDATA 'Shadowsocks\gui-config.json'),
        (Join-Path $env:APPDATA 'shadowsocks\gui-config.json')
    )

    $results = New-Object System.Collections.Generic.List[string]
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        if (Test-Path -LiteralPath $path) {
            $resolved = (Resolve-Path -LiteralPath $path -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($null -ne $resolved) {
                [void]$results.Add($resolved.Path)
            } else {
                [void]$results.Add($path)
            }
        }
    }

    $profilesRoot = Get-CodexShadowsocksProfilesRoot
    if (Test-Path -LiteralPath $profilesRoot) {
        foreach ($item in Get-ChildItem -LiteralPath $profilesRoot -Filter '*.client.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) {
            [void]$results.Add($item.FullName)
        }
    }

    return @($results | Select-Object -Unique)
}

function ConvertFrom-CodexBase64UrlText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $normalized = $Text.Replace('-', '+').Replace('_', '/')
    switch ($normalized.Length % 4) {
        0 { }
        2 { $normalized += '==' }
        3 { $normalized += '=' }
        default {
            while (($normalized.Length % 4) -ne 0) {
                $normalized += '='
            }
        }
    }

    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($normalized))
}

function Get-CodexObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -eq $property) {
            continue
        }

        $value = $property.Value
        if ($null -eq $value) {
            continue
        }

        if ($value -is [string]) {
            if ([string]::IsNullOrWhiteSpace($value)) {
                continue
            }
        }

        return $value
    }

    return $null
}

function Format-CodexShadowsocksHostRedacted {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$HostValue
    )

    if ([string]::IsNullOrWhiteSpace($HostValue)) {
        return '(not set)'
    }

    $ipAddress = $null
    if ([System.Net.IPAddress]::TryParse($HostValue, [ref]$ipAddress)) {
        if ($HostValue.Contains('.')) {
            $parts = $HostValue -split '\.'
            if ($parts.Count -eq 4) {
                return ('{0}.{1}.{2}.x' -f $parts[0], $parts[1], $parts[2])
            }
        }

        return 'configured-ip'
    }

    if ($HostValue.Length -le 4) {
        return 'configured-host'
    }

    return ('{0}***{1}' -f $HostValue.Substring(0, 2), $HostValue.Substring($HostValue.Length - 2))
}

function ConvertFrom-CodexShadowsocksObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$SourceKind,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $rootObject = $InputObject
    $selectedObject = $InputObject

    $configs = Get-CodexObjectValue -InputObject $InputObject -Names @('configs', 'servers')
    if ($null -ne $configs) {
        $configList = @($configs)
        if ($configList.Count -gt 0) {
            $selectedIndex = 0
            $rawIndex = Get-CodexObjectValue -InputObject $InputObject -Names @('index', 'selectedIndex')
            if ($null -ne $rawIndex) {
                try {
                    $selectedIndex = [int]$rawIndex
                } catch {
                    $selectedIndex = 0
                }
            }

            if ($selectedIndex -lt 0 -or $selectedIndex -ge $configList.Count) {
                $selectedIndex = 0
            }

            $selectedObject = $configList[$selectedIndex]
        }
    }

    $server = [string](Get-CodexObjectValue -InputObject $selectedObject -Names @('server', 'server_host', 'serverHost', 'host', 'hostname'))
    $portValue = Get-CodexObjectValue -InputObject $selectedObject -Names @('server_port', 'serverPort', 'port')
    $method = [string](Get-CodexObjectValue -InputObject $selectedObject -Names @('method', 'cipher', 'encrypt_method'))
    $password = [string](Get-CodexObjectValue -InputObject $selectedObject -Names @('password', 'passwd', 'secret'))
    $name = [string](Get-CodexObjectValue -InputObject $selectedObject -Names @('remarks', 'name', 'tag', 'profile'))
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = [string](Get-CodexObjectValue -InputObject $rootObject -Names @('remarks', 'name', 'tag', 'profile'))
    }

    $localPortValue = Get-CodexObjectValue -InputObject $selectedObject -Names @('local_port', 'localPort', 'socks_port', 'socksPort')
    if ($null -eq $localPortValue) {
        $localPortValue = 1080
    }

    if ([string]::IsNullOrWhiteSpace($server) -or $null -eq $portValue -or [string]::IsNullOrWhiteSpace($method) -or [string]::IsNullOrWhiteSpace($password)) {
        return $null
    }

    try {
        $serverPort = [int]$portValue
        $localPort = [int]$localPortValue
    } catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = 'imported-shadowsocks'
    }

    return [pscustomobject]@{
        Name       = $name
        Server     = $server
        ServerPort = $serverPort
        LocalPort  = $localPort
        Method     = $method
        Password   = $password
        SourceKind = $SourceKind
        Source     = $Source
    }
}

function ConvertFrom-CodexShadowsocksUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$SourceKind,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    if (-not $Uri.StartsWith('ss://', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Not a Shadowsocks SIP002 URI.'
    }

    $payload = $Uri.Substring(5)
    $tag = ''
    $fragmentIndex = $payload.IndexOf('#')
    if ($fragmentIndex -ge 0) {
        $tag = [Uri]::UnescapeDataString($payload.Substring($fragmentIndex + 1))
        $payload = $payload.Substring(0, $fragmentIndex)
    }

    $queryIndex = $payload.IndexOf('?')
    if ($queryIndex -ge 0) {
        $payload = $payload.Substring(0, $queryIndex)
    }

    $userInfo = $null
    $endpoint = $null
    if ($payload.Contains('@')) {
        $parts = $payload -split '@', 2
        $userInfo = $parts[0]
        $endpoint = $parts[1]
    } else {
        $decoded = ConvertFrom-CodexBase64UrlText -Text $payload
        $parts = $decoded -split '@', 2
        if ($parts.Count -ne 2) {
            throw 'Unable to decode the Shadowsocks URI.'
        }

        $userInfo = $parts[0]
        $endpoint = $parts[1]
    }

    if (-not $userInfo.Contains(':')) {
        $decodedUserInfo = ConvertFrom-CodexBase64UrlText -Text $userInfo
        if ($decodedUserInfo.Contains(':')) {
            $userInfo = $decodedUserInfo
        }
    }

    $userInfoParts = $userInfo -split ':', 2
    if ($userInfoParts.Count -ne 2) {
        throw 'Unable to parse Shadowsocks userinfo.'
    }

    $method = $userInfoParts[0]
    $password = $userInfoParts[1]
    $endpointUri = [Uri]("http://placeholder@{0}" -f $endpoint)

    return [pscustomobject]@{
        Name       = if ([string]::IsNullOrWhiteSpace($tag)) { 'imported-shadowsocks' } else { $tag }
        Server     = $endpointUri.Host
        ServerPort = $endpointUri.Port
        LocalPort  = 1080
        Method     = $method
        Password   = $password
        SourceKind = $SourceKind
        Source     = $Source
    }
}

function ConvertFrom-CodexShadowsocksText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$SourceKind,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $trimmed = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    $uriMatch = [regex]::Match($trimmed, 'ss://\S+')
    if ($uriMatch.Success) {
        return ConvertFrom-CodexShadowsocksUri -Uri $uriMatch.Value -SourceKind $SourceKind -Source $Source
    }

    if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) {
        try {
            $jsonObject = $trimmed | ConvertFrom-Json -ErrorAction Stop
            return ConvertFrom-CodexShadowsocksObject -InputObject $jsonObject -SourceKind $SourceKind -Source $Source
        } catch {
        }
    }

    $map = [ordered]@{}
    foreach ($line in ($trimmed -split "(`r`n|`n|`r)")) {
        $candidate = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate.StartsWith('#') -or $candidate.StartsWith(';')) {
            continue
        }

        if ($candidate -match '^\s*([A-Za-z0-9_\-]+)\s*[:=]\s*(.+?)\s*$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim()
            $map[$key] = $value
        }
    }

    if ($map.Count -eq 0) {
        return $null
    }

    $normalized = [ordered]@{}
    foreach ($entry in $map.GetEnumerator()) {
        $normalized[$entry.Key] = $entry.Value
    }

    if ($normalized.Contains('port') -and -not $normalized.Contains('server_port')) {
        $normalized['server_port'] = $normalized['port']
    }

    return ConvertFrom-CodexShadowsocksObject -InputObject ([pscustomobject]$normalized) -SourceKind $SourceKind -Source $Source
}

function Get-CodexShadowsocksSecretFromEnvironment {
    [CmdletBinding()]
    param()

    $uri = $env:CODEX_SS_URI
    if (-not [string]::IsNullOrWhiteSpace($uri)) {
        try {
            return ConvertFrom-CodexShadowsocksUri -Uri $uri -SourceKind 'Environment' -Source 'CODEX_SS_URI'
        } catch {
        }
    }

    $server = $env:CODEX_SS_SERVER
    $port = $env:CODEX_SS_PORT
    $method = $env:CODEX_SS_METHOD
    $password = $env:CODEX_SS_PASSWORD
    if (
        -not [string]::IsNullOrWhiteSpace($server) -and
        -not [string]::IsNullOrWhiteSpace($port) -and
        -not [string]::IsNullOrWhiteSpace($method) -and
        -not [string]::IsNullOrWhiteSpace($password)
    ) {
        return ConvertFrom-CodexShadowsocksObject -InputObject ([pscustomobject]@{
                name        = $env:CODEX_SS_NAME
                server      = $server
                server_port = $port
                local_port  = if ([string]::IsNullOrWhiteSpace($env:CODEX_SS_LOCAL_PORT)) { 1080 } else { $env:CODEX_SS_LOCAL_PORT }
                method      = $method
                password    = $password
            }) -SourceKind 'Environment' -Source 'CODEX_SS_SERVER/CODEX_SS_PORT/CODEX_SS_METHOD/CODEX_SS_PASSWORD'
    }

    return $null
}

function Get-CodexShadowsocksSecretFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $result = ConvertFrom-CodexShadowsocksText -Text $text -SourceKind 'File' -Source $Path
    if ($null -ne $result -and ([string]::IsNullOrWhiteSpace($result.Name) -or $result.Name -eq 'imported-shadowsocks')) {
        $fileName = [IO.Path]::GetFileNameWithoutExtension($Path)
        if ($fileName.EndsWith('.client', [System.StringComparison]::OrdinalIgnoreCase)) {
            $fileName = [IO.Path]::GetFileNameWithoutExtension($fileName)
        }

        if (-not [string]::IsNullOrWhiteSpace($fileName)) {
            $result.Name = $fileName
        }
    }

    return $result
}

function Find-CodexShadowsocksSecret {
    [CmdletBinding()]
    param(
        [string]$SourcePath
    )

    if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        $secret = Get-CodexShadowsocksSecretFromFile -Path $SourcePath
        if ($null -ne $secret) {
            return $secret
        }

        throw "No valid Shadowsocks secret material could be parsed from: $SourcePath"
    }

    $environmentSecret = Get-CodexShadowsocksSecretFromEnvironment
    if ($null -ne $environmentSecret) {
        return $environmentSecret
    }

    foreach ($candidatePath in (Get-CodexShadowsocksPrivateCandidatePaths)) {
        $secret = Get-CodexShadowsocksSecretFromFile -Path $candidatePath
        if ($null -ne $secret) {
            return $secret
        }
    }

    return $null
}

function Get-CodexShadowsocksSecretSummaryObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Secret,

        [string]$ActiveSecretPath = ''
    )

    return [pscustomobject]@{
        Found            = $true
        Name             = $Secret.Name
        SourceKind       = $Secret.SourceKind
        Source           = $Secret.Source
        Server           = Format-CodexShadowsocksHostRedacted -HostValue $Secret.Server
        ServerPort       = $Secret.ServerPort
        LocalPort        = $Secret.LocalPort
        Method           = $Secret.Method
        Password         = 'stored locally only'
        Sip002Uri        = 'stored locally only'
        ActiveSecretPath = $ActiveSecretPath
    }
}

function Get-CodexLocalComputerNetworkInfo {
    [CmdletBinding()]
    param()

    $ipv4Addresses = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($address in Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' }) {
            if (-not [string]::IsNullOrWhiteSpace($address.IPAddress)) {
                [void]$ipv4Addresses.Add($address.IPAddress)
            }
        }
    } catch {
        try {
            $hostAddresses = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME)
            foreach ($address in $hostAddresses) {
                if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and $address.IPAddressToString -notlike '127.*') {
                    [void]$ipv4Addresses.Add($address.IPAddressToString)
                }
            }
        } catch {
        }
    }

    $preferredAddress = if ($ipv4Addresses.Count -gt 0) { $ipv4Addresses[0] } else { '127.0.0.1' }
    return [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
        HostName     = [System.Net.Dns]::GetHostName()
        IPv4         = @($ipv4Addresses | Select-Object -Unique)
        PreferredIPv4 = $preferredAddress
    }
}

function Get-CodexShadowsocksGuiConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Get-CodexShadowsocksWindowsConfigPath
    }

    if ([string]::IsNullOrWhiteSpace($ConfigPath) -or -not (Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }

    return (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop)
}

function Get-CodexShadowsocksImportSource {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$SourcePath
    )

    $secret = Find-CodexShadowsocksSecret -SourcePath $SourcePath
    if ($null -eq $secret) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $secret.Name = $Name
    }

    return $secret
}

function Stop-CodexShadowsocksWindowsProcess {
    [CmdletBinding()]
    param()

    $running = @(Get-Process Shadowsocks -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) {
        return $false
    }

    foreach ($process in $running) {
        try {
            if ($process.MainWindowHandle -ne 0) {
                [void]$process.CloseMainWindow()
            }
        } catch {
        }
    }

    Start-Sleep -Milliseconds 900
    $remaining = @(Get-Process Shadowsocks -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0) {
        $remaining | Stop-Process -Force
        Start-Sleep -Milliseconds 700
    }

    return $true
}

function Invoke-CodexGitHubApiJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $headers = @{
        'User-Agent' = 'CodexNetworkToolkit'
        'Accept'     = 'application/vnd.github+json'
    }

    return Invoke-RestMethod -Headers $headers -Uri $Uri -TimeoutSec 30
}

function Get-CodexGitHubLatestRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    return Invoke-CodexGitHubApiJson -Uri ("https://api.github.com/repos/{0}/releases/latest" -f $Repository)
}

function New-CodexRandomHexSecret {
    [CmdletBinding()]
    param(
        [int]$ByteCount = 24
    )

    $bytes = [byte[]]::new($ByteCount)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

function ConvertTo-CodexBase64Url {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    return ([Convert]::ToBase64String($Bytes).TrimEnd('=')).Replace('+', '-').Replace('/', '_')
}

function New-CodexShadowsocksUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [int]$ServerPort,

        [string]$Tag
    )

    $userinfo = "{0}:{1}" -f $Method, $Password
    $encodedUserInfo = ConvertTo-CodexBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($userinfo))
    $uri = "ss://{0}@{1}:{2}" -f $encodedUserInfo, $Server, $ServerPort
    if (-not [string]::IsNullOrWhiteSpace($Tag)) {
        $uri += ("#{0}" -f [Uri]::EscapeDataString($Tag))
    }

    return $uri
}

function Get-CodexShadowsocksWindowsRelease {
    [CmdletBinding()]
    param()

    return Get-CodexGitHubLatestRelease -Repository 'shadowsocks/shadowsocks-windows'
}

function Get-CodexShadowsocksRustRelease {
    [CmdletBinding()]
    param()

    return Get-CodexGitHubLatestRelease -Repository 'shadowsocks/shadowsocks-rust'
}

function Get-CodexShadowsocksRustAssetInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetPattern
    )

    $release = Get-CodexShadowsocksRustRelease
    $asset = @($release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1)
    if ($asset.Count -eq 0) {
        throw "No shadowsocks-rust asset matched pattern: $AssetPattern"
    }

    $shaAsset = @($release.assets | Where-Object { $_.name -eq ("{0}.sha256" -f $asset[0].name) } | Select-Object -First 1)
    return [pscustomobject]@{
        Release = $release
        Asset   = $asset[0]
        Sha256  = if ($shaAsset.Count -gt 0) { $shaAsset[0] } else { $null }
    }
}

function Get-CodexSshRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexNetworkDirectory -Path (Join-Path $HOME '.ssh'))
}

function Get-CodexSshConfigDirectory {
    [CmdletBinding()]
    param()

    return (Ensure-CodexNetworkDirectory -Path (Join-Path (Get-CodexSshRoot) 'config.d'))
}

function Get-CodexSshMainConfigPath {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexSshRoot) 'config')
}

function Get-CodexSshManagedConfigPath {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexSshConfigDirectory) 'codex-network.conf')
}

function Backup-CodexNetworkFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $backupRoot = Ensure-CodexNetworkDirectory -Path (Get-CodexNetworkBackupRoot)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $leafName = Split-Path -Path $Path -Leaf
    $backupPath = Join-Path $backupRoot ("{0}.{1}.bak" -f $leafName, $timestamp)
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    return $backupPath
}

function Get-CodexNetworkDefaultProfile {
    [CmdletBinding()]
    param()

    $knownHostsPath = (Join-Path (Join-Path $HOME '.ssh') 'known_hosts') -replace '\\', '/'

    return [ordered]@{
        Proxy = [ordered]@{
            Enabled    = $false
            HttpProxy  = ''
            HttpsProxy = ''
            AllProxy   = ''
            NoProxy    = @('localhost', '127.0.0.1', '::1')
        }
        Client = [ordered]@{
            ConnectTimeoutSeconds      = 12
            ServerAliveIntervalSeconds = 15
            ServerAliveCountMax        = 4
            TCPKeepAlive               = $true
            Compression                = $true
            HashKnownHosts             = $true
            StrictHostKeyChecking      = 'accept-new'
            PreferredAuthentications   = 'publickey'
            IdentitiesOnly             = $true
            UserKnownHostsFile         = $knownHostsPath
        }
        Server = [ordered]@{
            Port                       = 22
            ClientAliveIntervalSeconds = 15
            ClientAliveCountMax        = 4
            TCPKeepAlive               = $true
            PasswordAuthentication     = $false
            PubkeyAuthentication       = $true
            AllowTcpForwarding         = $false
            AllowAgentForwarding       = $false
            GatewayPorts               = $false
            X11Forwarding              = $false
            PermitTunnel               = $false
            UseDns                     = $false
            LoginGraceTimeSeconds      = 20
            MaxAuthTries               = 3
        }
        Relay = [ordered]@{
            JumpHost = ''
        }
    }
}

function Set-CodexNetworkProfileValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Target,

        [Parameter(Mandatory = $true)]
        [object]$Source,

        [Parameter(Mandatory = $true)]
        [string[]]$Keys
    )

    foreach ($key in $Keys) {
        $property = $Source.PSObject.Properties[$key]
        if ($null -eq $property) {
            continue
        }

        $Target[$key] = $property.Value
    }
}

function Get-CodexNetworkProfile {
    [CmdletBinding()]
    param()

    $profile = Get-CodexNetworkDefaultProfile
    $profilePath = Get-CodexNetworkProfilePath

    if (-not (Test-Path -LiteralPath $profilePath)) {
        return $profile
    }

    try {
        $raw = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $profile
    }

    if ($null -ne $raw.Proxy) {
        Set-CodexNetworkProfileValues -Target $profile['Proxy'] -Source $raw.Proxy -Keys @('Enabled', 'HttpProxy', 'HttpsProxy', 'AllProxy')
        if ($null -ne $raw.Proxy.PSObject.Properties['NoProxy']) {
            $profile['Proxy']['NoProxy'] = @($raw.Proxy.NoProxy)
        }
    }

    if ($null -ne $raw.Client) {
        Set-CodexNetworkProfileValues -Target $profile['Client'] -Source $raw.Client -Keys @(
            'ConnectTimeoutSeconds',
            'ServerAliveIntervalSeconds',
            'ServerAliveCountMax',
            'TCPKeepAlive',
            'Compression',
            'HashKnownHosts',
            'StrictHostKeyChecking',
            'PreferredAuthentications',
            'IdentitiesOnly',
            'UserKnownHostsFile'
        )
    }

    if ($null -ne $raw.Server) {
        Set-CodexNetworkProfileValues -Target $profile['Server'] -Source $raw.Server -Keys @(
            'Port',
            'ClientAliveIntervalSeconds',
            'ClientAliveCountMax',
            'TCPKeepAlive',
            'PasswordAuthentication',
            'PubkeyAuthentication',
            'AllowTcpForwarding',
            'AllowAgentForwarding',
            'GatewayPorts',
            'X11Forwarding',
            'PermitTunnel',
            'UseDns',
            'LoginGraceTimeSeconds',
            'MaxAuthTries'
        )
    }

    if ($null -ne $raw.Relay) {
        Set-CodexNetworkProfileValues -Target $profile['Relay'] -Source $raw.Relay -Keys @('JumpHost')
    }

    return $profile
}

function Save-CodexNetworkProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Profile
    )

    $configRoot = Ensure-CodexNetworkDirectory -Path (Get-CodexNetworkConfigRoot)
    $profilePath = Join-Path $configRoot 'network-profile.json'
    $json = $Profile | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $profilePath -Value $json -Encoding utf8
    return $profilePath
}

function ConvertTo-CodexYesNo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Value
    )

    if ($Value) {
        return 'yes'
    }

    return 'no'
}

function Set-CodexProcessEnvironmentValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Remove-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
        return
    }

    Set-Item -Path "Env:$Name" -Value $Value
}

function Format-CodexProxyValue {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return '(not set)'
    }

    return ($Value -replace '://([^/@]+)@', '://***@')
}

function Initialize-CodexNetworkEnvironment {
    [CmdletBinding()]
    param()

    $profilePath = Get-CodexNetworkProfilePath
    if (-not (Test-Path -LiteralPath $profilePath)) {
        return
    }

    $profile = Get-CodexNetworkProfile
    if ($profile['Proxy']['Enabled']) {
        Set-CodexProcessEnvironmentValue -Name 'HTTP_PROXY' -Value $profile['Proxy']['HttpProxy']
        Set-CodexProcessEnvironmentValue -Name 'HTTPS_PROXY' -Value $profile['Proxy']['HttpsProxy']
        Set-CodexProcessEnvironmentValue -Name 'ALL_PROXY' -Value $profile['Proxy']['AllProxy']
        Set-CodexProcessEnvironmentValue -Name 'NO_PROXY' -Value ([string]::Join(',', @($profile['Proxy']['NoProxy'])))
        Set-CodexProcessEnvironmentValue -Name 'http_proxy' -Value $profile['Proxy']['HttpProxy']
        Set-CodexProcessEnvironmentValue -Name 'https_proxy' -Value $profile['Proxy']['HttpsProxy']
        Set-CodexProcessEnvironmentValue -Name 'all_proxy' -Value $profile['Proxy']['AllProxy']
        Set-CodexProcessEnvironmentValue -Name 'no_proxy' -Value ([string]::Join(',', @($profile['Proxy']['NoProxy'])))
        return
    }

    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy')) {
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
}

function Ensure-CodexSshConfigInclude {
    [CmdletBinding()]
    param()

    $mainConfigPath = Get-CodexSshMainConfigPath
    $includeLine = 'Include config.d/*.conf'

    if (-not (Test-Path -LiteralPath $mainConfigPath)) {
        $initialContent = @(
            '# Managed by Codex Network Toolkit'
            $includeLine
            ''
        )
        Set-Content -LiteralPath $mainConfigPath -Value $initialContent -Encoding utf8
        return $mainConfigPath
    }

    $rawContent = Get-Content -LiteralPath $mainConfigPath -Raw
    if ($rawContent -match '(?m)^\s*Include\s+config\.d/\*\.conf\s*$') {
        return $mainConfigPath
    }

    $null = Backup-CodexNetworkFile -Path $mainConfigPath
    $newContent = if ([string]::IsNullOrWhiteSpace($rawContent)) {
        "$includeLine`n"
    } else {
        "$includeLine`n$rawContent"
    }

    Set-Content -LiteralPath $mainConfigPath -Value $newContent -Encoding utf8
    return $mainConfigPath
}

function New-CodexRemoteClientConfigContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostAlias,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [string]$User,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [Parameter(Mandatory = $true)]
        [string]$IdentityFile,

        [string]$JumpHost
    )

    $profile = Get-CodexNetworkProfile
    $client = $profile['Client']
    $relayJumpHost = if ([string]::IsNullOrWhiteSpace($JumpHost)) { $profile['Relay']['JumpHost'] } else { $JumpHost }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add(('# Generated by Codex Network Toolkit on {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    [void]$lines.Add('Host *')
    [void]$lines.Add(("    ConnectTimeout {0}" -f [int]$client['ConnectTimeoutSeconds']))
    [void]$lines.Add(("    ServerAliveInterval {0}" -f [int]$client['ServerAliveIntervalSeconds']))
    [void]$lines.Add(("    ServerAliveCountMax {0}" -f [int]$client['ServerAliveCountMax']))
    [void]$lines.Add(("    TCPKeepAlive {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$client['TCPKeepAlive']))))
    [void]$lines.Add(("    Compression {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$client['Compression']))))
    [void]$lines.Add(("    HashKnownHosts {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$client['HashKnownHosts']))))
    [void]$lines.Add(("    StrictHostKeyChecking {0}" -f [string]$client['StrictHostKeyChecking']))
    [void]$lines.Add(("    PreferredAuthentications {0}" -f [string]$client['PreferredAuthentications']))
    [void]$lines.Add(("    IdentitiesOnly {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$client['IdentitiesOnly']))))
    [void]$lines.Add(("    UserKnownHostsFile {0}" -f [string]$client['UserKnownHostsFile']))
    [void]$lines.Add('')
    [void]$lines.Add(('# Replace the values below with your real remote host details, then connect with: ssh {0}' -f $HostAlias))
    [void]$lines.Add(("Host {0}" -f $HostAlias))
    [void]$lines.Add(("    HostName {0}" -f $HostName))
    [void]$lines.Add(("    User {0}" -f $User))
    [void]$lines.Add(("    Port {0}" -f $Port))
    [void]$lines.Add(("    IdentityFile {0}" -f $IdentityFile))

    if (-not [string]::IsNullOrWhiteSpace($relayJumpHost)) {
        [void]$lines.Add(("    ProxyJump {0}" -f $relayJumpHost))
    }

    return ([string]::Join("`n", $lines.ToArray()) + "`n")
}

function Get-CodexRemoteServerConfigContent {
    [CmdletBinding()]
    param(
        [int]$Port
    )

    $profile = Get-CodexNetworkProfile
    $server = $profile['Server']
    if ($Port -le 0) {
        $Port = [int]$server['Port']
    }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add(('# Generated by Codex Network Toolkit on {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    [void]$lines.Add(("Port {0}" -f $Port))
    [void]$lines.Add(("PubkeyAuthentication {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$server['PubkeyAuthentication']))))
    [void]$lines.Add(("PasswordAuthentication {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$server['PasswordAuthentication']))))
    [void]$lines.Add('KbdInteractiveAuthentication no')
    [void]$lines.Add('PermitEmptyPasswords no')
    [void]$lines.Add(("TCPKeepAlive {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$server['TCPKeepAlive']))))
    [void]$lines.Add(("ClientAliveInterval {0}" -f [int]$server['ClientAliveIntervalSeconds']))
    [void]$lines.Add(("ClientAliveCountMax {0}" -f [int]$server['ClientAliveCountMax']))
    [void]$lines.Add(("AllowTcpForwarding {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$server['AllowTcpForwarding']))))
    [void]$lines.Add(("AllowAgentForwarding {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$server['AllowAgentForwarding']))))
    [void]$lines.Add(("GatewayPorts {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$server['GatewayPorts']))))
    [void]$lines.Add(("X11Forwarding {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$server['X11Forwarding']))))
    [void]$lines.Add(("PermitTunnel {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$server['PermitTunnel']))))
    [void]$lines.Add(("UseDNS {0}" -f (ConvertTo-CodexYesNo -Value ([bool]$server['UseDns']))))
    [void]$lines.Add(("LoginGraceTime {0}" -f [int]$server['LoginGraceTimeSeconds']))
    [void]$lines.Add(("MaxAuthTries {0}" -f [int]$server['MaxAuthTries']))
    [void]$lines.Add('Subsystem sftp sftp-server.exe')
    return ([string]::Join("`n", $lines.ToArray()) + "`n")
}

function Get-CodexRemoteServerInstallerContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $template = @'
param(
    [int]$Port = __DEFAULT_PORT__,
    [string[]]$AllowUsers = @(),
    [switch]$AllowPasswordBootstrap
)

$ErrorActionPreference = 'Stop'

function Test-CodexRemoteAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CodexRemoteKeyBootstrap {
    param(
        [string[]]$Users
    )

    $candidatePaths = @(
        (Join-Path $env:ProgramData 'ssh\administrators_authorized_keys')
    )

    foreach ($user in $Users) {
        if ([string]::IsNullOrWhiteSpace($user)) {
            continue
        }

        $candidatePaths += (Join-Path $env:SystemDrive ("Users\{0}\.ssh\authorized_keys" -f $user))
    }

    foreach ($path in $candidatePaths) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Length -gt 0)) {
            return $true
        }
    }

    return $false
}

if (-not (Test-CodexRemoteAdmin)) {
    throw 'Run Install-CodexRemoteAccessServer.ps1 from an elevated PowerShell session.'
}

$capability = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' } | Select-Object -First 1
if (($null -ne $capability) -and ($capability.State -ne 'Installed')) {
    Add-WindowsCapability -Online -Name $capability.Name | Out-Null
}

$configDir = Join-Path $env:ProgramData 'ssh'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$targetConfigPath = Join-Path $configDir 'sshd_config'
$sourceConfigPath = Join-Path $PSScriptRoot 'sshd_config.codex-optimized'

if (-not (Test-Path -LiteralPath $sourceConfigPath)) {
    throw "Bundled sshd_config not found: $sourceConfigPath"
}

if ((-not $AllowPasswordBootstrap) -and (-not (Test-CodexRemoteKeyBootstrap -Users $AllowUsers))) {
    throw 'No authorized_keys file was found. Add a key first or rerun with -AllowPasswordBootstrap.'
}

$configText = Get-Content -LiteralPath $sourceConfigPath -Raw
$configText = [Regex]::Replace($configText, '(?m)^Port\s+\d+\s*$', ("Port {0}" -f $Port))

if ($AllowPasswordBootstrap) {
    $configText = [Regex]::Replace($configText, '(?m)^PasswordAuthentication\s+\w+\s*$', 'PasswordAuthentication yes')
}

if ($AllowUsers.Count -gt 0) {
    if ($configText -match '(?m)^AllowUsers\s+') {
        $configText = [Regex]::Replace($configText, '(?m)^AllowUsers\s+.*$', ("AllowUsers {0}" -f ([string]::Join(' ', $AllowUsers))))
    } else {
        $configText = $configText.TrimEnd() + "`r`n" + ("AllowUsers {0}" -f ([string]::Join(' ', $AllowUsers))) + "`r`n"
    }
}

if (Test-Path -LiteralPath $targetConfigPath) {
    $backupPath = Join-Path $configDir ("sshd_config.backup.{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $targetConfigPath -Destination $backupPath -Force
}

Set-Content -LiteralPath $targetConfigPath -Value $configText -Encoding utf8

Set-Service -Name sshd -StartupType Automatic
if ((Get-Service -Name sshd).Status -ne 'Running') {
    Start-Service -Name sshd
} else {
    Restart-Service -Name sshd
}

$ruleName = 'Codex Remote Access SSH'
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($null -eq $existingRule) {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
}

Write-Host ("Codex remote access server configured on TCP port {0}." -f $Port) -ForegroundColor Green
Write-Host 'Run Test-NetConnection <server-host> -Port <port> from a client to validate reachability.' -ForegroundColor Cyan
'@

    return $template.Replace('__DEFAULT_PORT__', $Port.ToString())
}

function Get-CodexRemoteServerReadmeContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $lines = @(
        '# Codex Remote Access Server Bundle',
        '',
        'This bundle configures Windows OpenSSH Server with safer defaults for unstable networks.',
        '',
        '## Files',
        '',
        '- `Install-CodexRemoteAccessServer.ps1`: elevated installer for the target server',
        '- `sshd_config.codex-optimized`: generated baseline sshd config',
        '',
        '## Recommended steps on the server',
        '',
        '1. Add your public key to the server before disabling password login.',
        '2. Run `Install-CodexRemoteAccessServer.ps1` in an elevated PowerShell window.',
        '3. If you still need password bootstrap, run `Install-CodexRemoteAccessServer.ps1 -AllowPasswordBootstrap` once, then switch back to key-only auth.',
        ('4. Default generated port is `{0}`. Override with `-Port` if your deployment uses a different port.' -f $Port),
        '5. Use `-AllowUsers alice,bob` to restrict which local accounts can log in.',
        '',
        '## Client follow-up',
        '',
        'After the server is live, run `remote-client-init` on your client machine and connect with `ssh <alias>`.'
    )

    return ([string]::Join("`n", $lines) + "`n")
}

function proxy-profile-set {
    [CmdletBinding()]
    param(
        [string]$HttpProxy,
        [string]$HttpsProxy,
        [string]$AllProxy,
        [string[]]$NoProxy
    )

    if (-not $PSBoundParameters.ContainsKey('HttpProxy') -and -not $PSBoundParameters.ContainsKey('HttpsProxy') -and -not $PSBoundParameters.ContainsKey('AllProxy') -and -not $PSBoundParameters.ContainsKey('NoProxy')) {
        throw 'Provide at least one proxy value. Example: proxy-profile-set -HttpsProxy http://proxy.example:8080 -NoProxy localhost,127.0.0.1'
    }

    $profile = Get-CodexNetworkProfile

    if ($PSBoundParameters.ContainsKey('HttpProxy')) {
        $profile['Proxy']['HttpProxy'] = $HttpProxy
    }

    if ($PSBoundParameters.ContainsKey('HttpsProxy')) {
        $profile['Proxy']['HttpsProxy'] = $HttpsProxy
    }

    if ($PSBoundParameters.ContainsKey('AllProxy')) {
        $profile['Proxy']['AllProxy'] = $AllProxy
    }

    if ($PSBoundParameters.ContainsKey('NoProxy')) {
        $profile['Proxy']['NoProxy'] = @($NoProxy)
    }

    $profile['Proxy']['Enabled'] = $true
    $null = Save-CodexNetworkProfile -Profile $profile
    Initialize-CodexNetworkEnvironment
    proxy-profile-show
}

function proxy-profile-clear {
    [CmdletBinding()]
    param()

    $profile = Get-CodexNetworkProfile
    $profile['Proxy']['Enabled'] = $false
    $profile['Proxy']['HttpProxy'] = ''
    $profile['Proxy']['HttpsProxy'] = ''
    $profile['Proxy']['AllProxy'] = ''
    $profile['Proxy']['NoProxy'] = @('localhost', '127.0.0.1', '::1')
    $null = Save-CodexNetworkProfile -Profile $profile
    Initialize-CodexNetworkEnvironment
    proxy-profile-show
}

function proxy-profile-show {
    [CmdletBinding()]
    param()

    $profile = Get-CodexNetworkProfile
    [pscustomobject]@{
        Enabled     = [bool]$profile['Proxy']['Enabled']
        HttpProxy   = Format-CodexProxyValue -Value $profile['Proxy']['HttpProxy']
        HttpsProxy  = Format-CodexProxyValue -Value $profile['Proxy']['HttpsProxy']
        AllProxy    = Format-CodexProxyValue -Value $profile['Proxy']['AllProxy']
        NoProxy     = [string]::Join(',', @($profile['Proxy']['NoProxy']))
        ProfilePath = Get-CodexNetworkProfilePath
    }
}

function remote-client-init {
    [CmdletBinding()]
    param(
        [string]$HostAlias = 'codex-remote-template',
        [string]$HostName = 'example.com',
        [string]$User = 'remoteuser',
        [int]$Port = 0,
        [string]$IdentityFile = '~/.ssh/id_ed25519',
        [string]$JumpHost,
        [switch]$CreateKeyIfMissing
    )

    $profile = Get-CodexNetworkProfile
    if ($Port -le 0) {
        $Port = [int]$profile['Server']['Port']
    }

    $profilePath = Get-CodexNetworkProfilePath
    if (-not (Test-Path -LiteralPath $profilePath)) {
        $null = Save-CodexNetworkProfile -Profile $profile
    }

    $mainConfigPath = Ensure-CodexSshConfigInclude
    $managedConfigPath = Get-CodexSshManagedConfigPath
    $backupPath = Backup-CodexNetworkFile -Path $managedConfigPath

    if ($CreateKeyIfMissing) {
        $keyPath = Join-Path (Get-CodexSshRoot) 'id_ed25519'
        if (-not (Test-Path -LiteralPath $keyPath)) {
            & ssh-keygen.exe -t ed25519 -f $keyPath -N '' | Out-Null
        }
    }

    $content = New-CodexRemoteClientConfigContent -HostAlias $HostAlias -HostName $HostName -User $User -Port $Port -IdentityFile $IdentityFile -JumpHost $JumpHost
    Set-Content -LiteralPath $managedConfigPath -Value $content -Encoding utf8

    [pscustomobject]@{
        MainConfig    = $mainConfigPath
        ManagedConfig = $managedConfigPath
        HostAlias     = $HostAlias
        HostName      = $HostName
        Port          = $Port
        JumpHost      = if ([string]::IsNullOrWhiteSpace($JumpHost)) { $profile['Relay']['JumpHost'] } else { $JumpHost }
        Backup        = $backupPath
        ConnectWith   = ("ssh {0}" -f $HostAlias)
    }
}

function remote-server-bundle {
    [CmdletBinding()]
    param(
        [string]$OutputDir,
        [int]$Port = 0
    )

    $profile = Get-CodexNetworkProfile
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Get-CodexRemoteAccessExampleRoot
    }

    if ($Port -le 0) {
        $Port = [int]$profile['Server']['Port']
    }

    $resolvedOutputDir = Ensure-CodexNetworkDirectory -Path $OutputDir
    $configPath = Join-Path $resolvedOutputDir 'sshd_config.codex-optimized'
    $installerPath = Join-Path $resolvedOutputDir 'Install-CodexRemoteAccessServer.ps1'
    $readmePath = Join-Path $resolvedOutputDir 'README.md'

    Set-Content -LiteralPath $configPath -Value (Get-CodexRemoteServerConfigContent -Port $Port) -Encoding utf8
    Set-Content -LiteralPath $installerPath -Value (Get-CodexRemoteServerInstallerContent -Port $Port) -Encoding utf8
    Set-Content -LiteralPath $readmePath -Value (Get-CodexRemoteServerReadmeContent -Port $Port) -Encoding utf8

    [pscustomobject]@{
        OutputDir  = $resolvedOutputDir
        Installer  = $installerPath
        ServerConf = $configPath
        Readme     = $readmePath
    }
}

function remote-health {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Host')]
        [string]$TargetHost,

        [int]$Port = 22,

        [int]$TimeoutSeconds = 5,

        [switch]$UseTls
    )

    $dnsStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $addresses = @()
    $dnsError = $null
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($TargetHost) | Select-Object -ExpandProperty IPAddressToString
    } catch {
        $dnsError = $_.Exception.Message
    }
    $dnsStopwatch.Stop()

    $connectLatencyMs = $null
    $connectSucceeded = $false
    $tcpError = $null
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connectStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $connectTask = $client.ConnectAsync($TargetHost, $Port)
        if (-not $connectTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            throw "TCP connect timed out after $TimeoutSeconds seconds."
        }

        $connectStopwatch.Stop()
        $connectLatencyMs = [Math]::Round($connectStopwatch.Elapsed.TotalMilliseconds, 2)
        $connectSucceeded = $true
    } catch {
        $tcpError = $_.Exception.Message
    }

    $tlsSubject = $null
    $tlsIssuer = $null
    $tlsValidTo = $null
    $tlsError = $null
    if ($UseTls -and $connectSucceeded) {
        try {
            $sslStream = [System.Net.Security.SslStream]::new($client.GetStream(), $false, { $true })
            $sslStream.ReadTimeout = [Math]::Max(1000, $TimeoutSeconds * 1000)
            $sslStream.WriteTimeout = [Math]::Max(1000, $TimeoutSeconds * 1000)
            $sslStream.AuthenticateAsClient($TargetHost)
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($sslStream.RemoteCertificate)
            $tlsSubject = $certificate.Subject
            $tlsIssuer = $certificate.Issuer
            $tlsValidTo = $certificate.NotAfter
            $sslStream.Dispose()
        } catch {
            $tlsError = $_.Exception.Message
        }
    }

    $client.Dispose()

    [pscustomobject]@{
        Host         = $TargetHost
        Port         = $Port
        ProxyEnabled = [bool](Get-CodexNetworkProfile)['Proxy']['Enabled']
        DnsLookupMs  = [Math]::Round($dnsStopwatch.Elapsed.TotalMilliseconds, 2)
        Addresses    = if ($addresses.Count -gt 0) { [string]::Join(', ', $addresses) } else { '' }
        DnsError     = $dnsError
        TcpReachable = $connectSucceeded
        TcpConnectMs = $connectLatencyMs
        TcpError     = $tcpError
        TlsSubject   = $tlsSubject
        TlsIssuer    = $tlsIssuer
        TlsValidTo   = $tlsValidTo
        TlsError     = $tlsError
    }
}

function ss-source-show {
    [CmdletBinding()]
    param(
        [switch]$IncludeReleaseMetadata
    )

    $sourceFile = Get-CodexShadowsocksSourceFilePath
    $windowsRelease = Get-CodexShadowsocksWindowsRelease
    $rustRelease = Get-CodexShadowsocksRustRelease

    $result = [ordered]@{
        SourceFile           = if ($null -eq $sourceFile) { '' } else { $sourceFile }
        SeedUrls             = @((Get-CodexShadowsocksSourceUrls))
        WindowsClientRelease = $windowsRelease.tag_name
        WindowsClientPage    = $windowsRelease.html_url
        RustServerRelease    = $rustRelease.tag_name
        RustServerPage       = $rustRelease.html_url
    }

    if ($IncludeReleaseMetadata) {
        $result['WindowsAssets'] = @($windowsRelease.assets | Select-Object -ExpandProperty name)
        $result['RustAssets'] = @($rustRelease.assets | Select-Object -ExpandProperty name)
    }

    [pscustomobject]$result
}

function ss-secret-discover {
    [CmdletBinding()]
    param(
        [string]$SourcePath
    )

    $secret = Find-CodexShadowsocksSecret -SourcePath $SourcePath
    if ($null -eq $secret) {
        return [pscustomobject]@{
            Found            = $false
            Name             = ''
            SourceKind       = ''
            Source           = ''
            Server           = ''
            ServerPort       = 0
            LocalPort        = 0
            Method           = ''
            Password         = ''
            Sip002Uri        = ''
            ActiveSecretPath = Get-CodexShadowsocksActiveSecretPath
            CandidatePaths   = @((Get-CodexShadowsocksPrivateCandidatePaths))
        }
    }

    $summary = Get-CodexShadowsocksSecretSummaryObject -Secret $secret -ActiveSecretPath (Get-CodexShadowsocksActiveSecretPath)
    $summary | Add-Member -NotePropertyName CandidatePaths -NotePropertyValue @((Get-CodexShadowsocksPrivateCandidatePaths))
    return $summary
}

function ss-secret-import {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$SourcePath,
        [switch]$FetchWindowsClient,
        [switch]$ExpandWindowsClient,
        [switch]$Quiet
    )

    $secret = Find-CodexShadowsocksSecret -SourcePath $SourcePath
    if ($null -eq $secret) {
        return [pscustomobject]@{
            Imported         = $false
            Reason           = 'No local or environment Shadowsocks secret source was detected.'
            ActiveSecretPath = Get-CodexShadowsocksActiveSecretPath
            CandidatePaths   = @((Get-CodexShadowsocksPrivateCandidatePaths))
        }
    }

    $effectiveName = $Name
    if ([string]::IsNullOrWhiteSpace($effectiveName)) {
        $effectiveName = $secret.Name
    }

    if ([string]::IsNullOrWhiteSpace($effectiveName)) {
        $effectiveName = 'lia-private-import'
    }

    $profileResult = ss-profile-new `
        -Name $effectiveName `
        -Server $secret.Server `
        -ServerPort $secret.ServerPort `
        -LocalPort $secret.LocalPort `
        -Method $secret.Method `
        -Password $secret.Password

    $privateRoot = Ensure-CodexNetworkDirectory -Path (Get-CodexShadowsocksPrivateRoot)
    $activeSecretPath = Join-Path $privateRoot 'shadowsocks.active.json'
    $activeSecret = [ordered]@{
        imported_at = (Get-Date).ToString('o')
        source_kind = $secret.SourceKind
        source      = $secret.Source
        name        = $profileResult.Name
        server      = $secret.Server
        server_port = $secret.ServerPort
        local_port  = $secret.LocalPort
        method      = $secret.Method
        password    = $secret.Password
        sip002_uri  = New-CodexShadowsocksUri -Method $secret.Method -Password $secret.Password -Server $secret.Server -ServerPort $secret.ServerPort -Tag $profileResult.Name
        client_json = $profileResult.ClientConfig
        server_json = $profileResult.ServerConfig
    }
    Set-Content -LiteralPath $activeSecretPath -Value ($activeSecret | ConvertTo-Json -Depth 8) -Encoding utf8

    $fetchResult = $null
    if ($FetchWindowsClient) {
        $fetchResult = ss-client-fetch -Expand:$ExpandWindowsClient
    }

    $result = Get-CodexShadowsocksSecretSummaryObject -Secret $secret -ActiveSecretPath $activeSecretPath
    $result | Add-Member -NotePropertyName Imported -NotePropertyValue $true
    $result | Add-Member -NotePropertyName ProfileName -NotePropertyValue $profileResult.Name
    $result | Add-Member -NotePropertyName ClientConfig -NotePropertyValue $profileResult.ClientConfig
    $result | Add-Member -NotePropertyName ServerConfig -NotePropertyValue $profileResult.ServerConfig
    $result | Add-Member -NotePropertyName CandidatePaths -NotePropertyValue @((Get-CodexShadowsocksPrivateCandidatePaths))
    if ($null -ne $fetchResult) {
        $result | Add-Member -NotePropertyName WindowsClientRelease -NotePropertyValue $fetchResult.ReleaseTag
        $result | Add-Member -NotePropertyName WindowsClientPath -NotePropertyValue $fetchResult.LaunchPath
    }

    if (-not $Quiet) {
        return $result
    }

    return $result
}

function ss-secret-clear {
    [CmdletBinding()]
    param()

    $activeSecretPath = Get-CodexShadowsocksActiveSecretPath
    $removed = $false
    if (Test-Path -LiteralPath $activeSecretPath) {
        Remove-Item -LiteralPath $activeSecretPath -Force
        $removed = $true
    }

    [pscustomobject]@{
        Removed          = $removed
        ActiveSecretPath = $activeSecretPath
    }
}

function ss-profile-new {
    [CmdletBinding()]
    param(
        [string]$Name = 'lia-official-template',
        [string]$Server = 'example.com',
        [string]$ServerBind = '0.0.0.0',
        [int]$ServerPort = 8388,
        [int]$LocalPort = 1080,
        [string]$Method = 'chacha20-ietf-poly1305',
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($Password)) {
        $Password = New-CodexRandomHexSecret
    }

    $profilesRoot = Ensure-CodexNetworkDirectory -Path (Get-CodexShadowsocksProfilesRoot)
    $safeName = ($Name -replace '[^\w\.-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = 'lia-official-template'
    }

    $clientPath = Join-Path $profilesRoot ("{0}.client.json" -f $safeName)
    $serverPath = Join-Path $profilesRoot ("{0}.server.json" -f $safeName)

    $clientConfig = [ordered]@{
        server      = $Server
        server_port = $ServerPort
        local_port  = $LocalPort
        password    = $Password
        method      = $Method
    }

    $serverConfig = [ordered]@{
        server      = $ServerBind
        server_port = $ServerPort
        password    = $Password
        method      = $Method
        mode        = 'tcp_and_udp'
    }

    Set-Content -LiteralPath $clientPath -Value ($clientConfig | ConvertTo-Json -Depth 5) -Encoding utf8
    Set-Content -LiteralPath $serverPath -Value ($serverConfig | ConvertTo-Json -Depth 5) -Encoding utf8

    [pscustomobject]@{
        Name           = $safeName
        Method         = $Method
        Server         = $Server
        ServerPort     = $ServerPort
        LocalPort      = $LocalPort
        ClientConfig   = $clientPath
        ServerConfig   = $serverPath
        Sip002Uri      = New-CodexShadowsocksUri -Method $Method -Password $Password -Server $Server -ServerPort $ServerPort -Tag $safeName
        RecommendedDoc = 'https://shadowsocks.org/doc/configs.html'
    }
}

function ss-client-fetch {
    [CmdletBinding()]
    param(
        [string]$DestinationDir,
        [switch]$Expand,
        [switch]$Force
    )

    $release = Get-CodexShadowsocksWindowsRelease
    $asset = @($release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1)
    if ($asset.Count -eq 0) {
        throw 'No downloadable ZIP asset was found in the official shadowsocks-windows release.'
    }

    if ([string]::IsNullOrWhiteSpace($DestinationDir)) {
        $DestinationDir = Get-CodexShadowsocksDownloadsRoot
    }

    $resolvedDestinationDir = Ensure-CodexNetworkDirectory -Path $DestinationDir
    $archivePath = Join-Path $resolvedDestinationDir $asset[0].name
    if ($Force -or -not (Test-Path -LiteralPath $archivePath)) {
        Invoke-WebRequest -Headers @{ 'User-Agent' = 'CodexNetworkToolkit' } -Uri $asset[0].browser_download_url -OutFile $archivePath -TimeoutSec 60
    }

    $expandedPath = $null
    $launchPath = $null
    if ($Expand) {
        $expandedRoot = Ensure-CodexNetworkDirectory -Path (Get-CodexShadowsocksWindowsClientRoot)
        $expandedPath = Join-Path $expandedRoot ([IO.Path]::GetFileNameWithoutExtension($asset[0].name))
        if ($Force -and (Test-Path -LiteralPath $expandedPath)) {
            Remove-Item -LiteralPath $expandedPath -Recurse -Force
        }

        if (-not (Test-Path -LiteralPath $expandedPath)) {
            Expand-Archive -LiteralPath $archivePath -DestinationPath $expandedPath -Force
        }

        $candidate = Join-Path $expandedPath 'Shadowsocks.exe'
        if (Test-Path -LiteralPath $candidate) {
            $launchPath = $candidate
        }
    }

    [pscustomobject]@{
        ReleaseTag   = $release.tag_name
        ReleasePage  = $release.html_url
        ArchivePath  = $archivePath
        ExpandedPath = $expandedPath
        LaunchPath   = $launchPath
    }
}

function ss-client-open {
    [CmdletBinding()]
    param(
        [string]$ExecutablePath
    )

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        $root = Get-CodexShadowsocksWindowsClientRoot
        $candidate = Get-ChildItem -Path $root -Recurse -Filter 'Shadowsocks.exe' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -eq $candidate) {
            $fetchResult = ss-client-fetch -Expand
            $ExecutablePath = $fetchResult.LaunchPath
        } else {
            $ExecutablePath = $candidate.FullName
        }
    }

    if ([string]::IsNullOrWhiteSpace($ExecutablePath) -or -not (Test-Path -LiteralPath $ExecutablePath)) {
        throw 'Shadowsocks.exe could not be found. Run ss-client-fetch -Expand first.'
    }

    Start-Process -FilePath $ExecutablePath | Out-Null
    [pscustomobject]@{
        LaunchPath = $ExecutablePath
        Started    = $true
    }
}

function ss-client-info {
    [CmdletBinding()]
    param()

    $computer = Get-CodexLocalComputerNetworkInfo
    $configPath = Get-CodexShadowsocksWindowsConfigPath
    $guiConfig = Get-CodexShadowsocksGuiConfig -ConfigPath $configPath
    $currentServer = $null
    if ($null -ne $guiConfig -and $null -ne $guiConfig.configs -and @($guiConfig.configs).Count -gt 0) {
        $index = 0
        if ($null -ne $guiConfig.PSObject.Properties['index']) {
            try {
                $index = [int]$guiConfig.index
            } catch {
                $index = 0
            }
        }

        $configs = @($guiConfig.configs)
        if ($index -lt 0 -or $index -ge $configs.Count) {
            $index = 0
        }

        $currentServer = $configs[$index]
    }

    $process = Get-Process Shadowsocks -ErrorAction SilentlyContinue | Select-Object -First 1

    [pscustomobject]@{
        ClientExecutable     = Get-CodexShadowsocksWindowsExecutablePath
        ClientConfigPath     = $configPath
        ClientRunning        = ($null -ne $process)
        PortableMode         = if ($null -eq $guiConfig) { $null } else { [bool]$guiConfig.portableMode }
        Enabled              = if ($null -eq $guiConfig) { $null } else { [bool]$guiConfig.enabled }
        GlobalMode           = if ($null -eq $guiConfig) { $null } else { [bool]$guiConfig.global }
        ShareOverLan         = if ($null -eq $guiConfig) { $null } else { [bool]$guiConfig.shareOverLan }
        LocalPort            = if ($null -eq $guiConfig) { $null } else { [int]$guiConfig.localPort }
        CurrentServer        = if ($null -eq $currentServer) { '' } else { Format-CodexShadowsocksHostRedacted -HostValue ([string]$currentServer.server) }
        CurrentServerPort    = if ($null -eq $currentServer) { $null } else { [int]$currentServer.server_port }
        CurrentMethod        = if ($null -eq $currentServer) { '' } else { [string]$currentServer.method }
        ComputerName         = $computer.ComputerName
        HostName             = $computer.HostName
        UserName             = $computer.UserName
        PreferredIPv4        = $computer.PreferredIPv4
        IPv4                 = $computer.IPv4
    }
}

function ss-client-sync {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$SourcePath,
        [int]$LocalPort,
        [switch]$EnableClient,
        [switch]$GlobalMode,
        [switch]$ShareOverLan,
        [switch]$RestartClient,
        [switch]$StartClient
    )

    $secret = Get-CodexShadowsocksImportSource -Name $Name -SourcePath $SourcePath
    if ($null -eq $secret) {
        throw 'No Shadowsocks source could be discovered. Put a real config in a local private file or env var, then rerun ss-client-sync.'
    }

    $exePath = Get-CodexShadowsocksWindowsExecutablePath
    if ([string]::IsNullOrWhiteSpace($exePath)) {
        $fetch = ss-client-fetch -Expand
        $exePath = $fetch.LaunchPath
    }

    if ([string]::IsNullOrWhiteSpace($exePath) -or -not (Test-Path -LiteralPath $exePath)) {
        throw 'Official Shadowsocks Windows client is not available. Run ss-client-fetch -Expand first.'
    }

    $configPath = Join-Path (Split-Path -Parent $exePath) 'gui-config.json'
    $currentConfig = Get-CodexShadowsocksGuiConfig -ConfigPath $configPath
    if ($null -eq $currentConfig) {
        throw "Unable to load gui-config.json: $configPath"
    }

    $wasRunning = Stop-CodexShadowsocksWindowsProcess

    $effectiveLocalPort = if ($PSBoundParameters.ContainsKey('LocalPort')) { $LocalPort } elseif ($secret.LocalPort -gt 0) { $secret.LocalPort } else { [int]$currentConfig.localPort }
    $newServerConfig = [ordered]@{
        server        = $secret.Server
        server_port   = $secret.ServerPort
        password      = $secret.Password
        method        = $secret.Method
        remarks       = $secret.Name
        timeout       = 5
        warnLegacyUrl = $false
    }

    $currentConfig.configs = @([pscustomobject]$newServerConfig)
    $currentConfig.index = 0
    $currentConfig.localPort = $effectiveLocalPort
    $currentConfig.shareOverLan = $ShareOverLan.IsPresent
    $currentConfig.global = $GlobalMode.IsPresent
    $currentConfig.enabled = $EnableClient.IsPresent
    $currentConfig.firstRun = $false
    $currentConfig.portableMode = $true

    Backup-CodexNetworkFile -Path $configPath | Out-Null
    Set-Content -LiteralPath $configPath -Value ($currentConfig | ConvertTo-Json -Depth 12) -Encoding utf8

    $writtenConfig = Get-CodexShadowsocksGuiConfig -ConfigPath $configPath
    $writtenServer = $null
    if ($null -ne $writtenConfig -and $null -ne $writtenConfig.configs -and @($writtenConfig.configs).Count -gt 0) {
        $writtenServer = @($writtenConfig.configs)[0]
    }

    if (
        $null -eq $writtenConfig -or
        $null -eq $writtenServer -or
        [string]$writtenServer.server -ne $secret.Server -or
        [int]$writtenServer.server_port -ne $secret.ServerPort -or
        [string]$writtenServer.password -ne $secret.Password -or
        [string]$writtenServer.method -ne $secret.Method -or
        [int]$writtenConfig.localPort -ne $effectiveLocalPort
    ) {
        throw "Failed to persist Shadowsocks Windows client config at $configPath"
    }

    $computer = Get-CodexLocalComputerNetworkInfo
    if ($wasRunning -or $RestartClient) {
        Start-Process -FilePath $exePath | Out-Null
    } elseif ($StartClient) {
        if ($null -eq (Get-Process Shadowsocks -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            Start-Process -FilePath $exePath | Out-Null
        }
    }

    [pscustomobject]@{
        Updated            = $true
        ClientExecutable   = $exePath
        ClientConfigPath   = $configPath
        ProfileName        = $secret.Name
        SourceKind         = $secret.SourceKind
        Source             = $secret.Source
        Server             = Format-CodexShadowsocksHostRedacted -HostValue $secret.Server
        ServerPort         = $secret.ServerPort
        Method             = $secret.Method
        LocalPort          = $effectiveLocalPort
        Enabled            = $EnableClient.IsPresent
        GlobalMode         = $GlobalMode.IsPresent
        ShareOverLan       = $ShareOverLan.IsPresent
        ComputerName       = $computer.ComputerName
        PreferredIPv4      = $computer.PreferredIPv4
        IPv4               = $computer.IPv4
        RestartedOrStarted = ($wasRunning -or $RestartClient.IsPresent -or $StartClient.IsPresent)
    }
}

function Get-CodexShadowsocksServerReadme {
    [CmdletBinding()]
    param(
        [string]$ReleaseTag,
        [string]$AssetName
    )

    $lines = @(
        '# Codex Shadowsocks Server Bundle',
        '',
        'This bundle is generated from the official Shadowsocks sources listed in `lia.txt`.',
        '',
        '## Source anchors',
        '',
        '- `https://github.com/shadowsocks`',
        '- `https://shadowsocks.org/`',
        '',
        '## Included files',
        '',
        '- `install-shadowsocks-rust.sh`',
        '- `config.server.json`',
        '- `shadowsocks-rust.service`',
        '',
        ('## Pinned release'),
        '',
        ('- `shadowsocks-rust` release: `{0}`' -f $ReleaseTag),
        ('- asset: `{0}`' -f $AssetName),
        '',
        '## Server steps',
        '',
        '1. Copy this folder to an Ubuntu 22.04+ server.',
        '2. Review `config.server.json` and replace placeholders if needed.',
        '3. Run `bash install-shadowsocks-rust.sh`.',
        '4. Open the chosen TCP/UDP port on the server firewall and cloud firewall.',
        '',
        '## Client steps',
        '',
        'Import the generated client JSON or SIP002 URI with `ss-profile-new` on Windows.'
    )

    return ([string]::Join("`n", $lines) + "`n")
}

function ss-server-bundle {
    [CmdletBinding()]
    param(
        [string]$Name = 'lia-official-template',
        [string]$ServerAddress = '0.0.0.0',
        [int]$ServerPort = 8388,
        [string]$Method = 'chacha20-ietf-poly1305',
        [string]$Password,
        [string]$OutputDir,
        [string]$LinuxAssetPattern = 'shadowsocks-v*.x86_64-unknown-linux-gnu.tar.xz'
    )

    $existingServerProfilePath = Join-Path (Get-CodexShadowsocksProfilesRoot) ("{0}.server.json" -f ($Name -replace '[^\w\.-]+', '-').Trim('-'))
    if (Test-Path -LiteralPath $existingServerProfilePath) {
        $existingProfile = Get-Content -LiteralPath $existingServerProfilePath -Raw | ConvertFrom-Json

        if (-not $PSBoundParameters.ContainsKey('Password') -and $null -ne $existingProfile.password) {
            $Password = [string]$existingProfile.password
        }

        if (-not $PSBoundParameters.ContainsKey('ServerAddress') -and $null -ne $existingProfile.server) {
            $ServerAddress = [string]$existingProfile.server
        }

        if (-not $PSBoundParameters.ContainsKey('ServerPort') -and $null -ne $existingProfile.server_port) {
            $ServerPort = [int]$existingProfile.server_port
        }

        if (-not $PSBoundParameters.ContainsKey('Method') -and $null -ne $existingProfile.method) {
            $Method = [string]$existingProfile.method
        }
    }

    if ([string]::IsNullOrWhiteSpace($Password)) {
        $Password = New-CodexRandomHexSecret
    }

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Get-CodexShadowsocksExampleRoot
    }

    $assetInfo = Get-CodexShadowsocksRustAssetInfo -AssetPattern $LinuxAssetPattern
    $resolvedOutputDir = Ensure-CodexNetworkDirectory -Path $OutputDir

    $configPath = Join-Path $resolvedOutputDir 'config.server.json'
    $scriptPath = Join-Path $resolvedOutputDir 'install-shadowsocks-rust.sh'
    $servicePath = Join-Path $resolvedOutputDir 'shadowsocks-rust.service'
    $readmePath = Join-Path $resolvedOutputDir 'README.md'

    $serverConfig = [ordered]@{
        server      = $ServerAddress
        server_port = $ServerPort
        password    = $Password
        method      = $Method
        mode        = 'tcp_and_udp'
    }
    Set-Content -LiteralPath $configPath -Value ($serverConfig | ConvertTo-Json -Depth 5) -Encoding utf8

    $assetUrl = $assetInfo.Asset.browser_download_url
    $shaUrl = if ($null -ne $assetInfo.Sha256) { $assetInfo.Sha256.browser_download_url } else { '' }
    $binaryName = 'ssserver'
    $scriptLines = @(
        '#!/usr/bin/env bash',
        'set -euo pipefail',
        '',
        ("RELEASE_TAG='{0}'" -f $assetInfo.Release.tag_name),
        ("ASSET_NAME='{0}'" -f $assetInfo.Asset.name),
        ("ASSET_URL='{0}'" -f $assetUrl),
        ("SHA_URL='{0}'" -f $shaUrl),
        'WORKDIR="${WORKDIR:-$PWD}"',
        'TMPDIR="$(mktemp -d)"',
        'trap ''rm -rf "$TMPDIR"'' EXIT',
        'cd "$TMPDIR"',
        'curl -fsSL "$ASSET_URL" -o "$ASSET_NAME"',
        'if [[ -n "$SHA_URL" ]]; then',
        '  curl -fsSL "$SHA_URL" -o "$ASSET_NAME.sha256"',
        '  sha256sum -c "$ASSET_NAME.sha256"',
        'fi',
        'tar -xf "$ASSET_NAME"',
        ("sudo install -m 0755 {0} /usr/local/bin/{0}" -f $binaryName),
        'sudo mkdir -p /etc/shadowsocks-rust',
        'sudo cp "$WORKDIR/config.server.json" /etc/shadowsocks-rust/config.json',
        'sudo cp "$WORKDIR/shadowsocks-rust.service" /etc/systemd/system/shadowsocks-rust.service',
        'sudo systemctl daemon-reload',
        'sudo systemctl enable --now shadowsocks-rust.service',
        ('echo "Shadowsocks server is configured on port {0}. Remember to open TCP/UDP {0} in your firewall."' -f $ServerPort)
    )
    Set-Content -LiteralPath $scriptPath -Value ($scriptLines -join "`n") -Encoding utf8

    $serviceLines = @(
        '[Unit]',
        'Description=Shadowsocks Rust Server',
        'After=network-online.target',
        'Wants=network-online.target',
        '',
        '[Service]',
        'Type=simple',
        'ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks-rust/config.json',
        'Restart=on-failure',
        'RestartSec=3',
        'LimitNOFILE=51200',
        '',
        '[Install]',
        'WantedBy=multi-user.target'
    )
    Set-Content -LiteralPath $servicePath -Value ($serviceLines -join "`n") -Encoding utf8
    Set-Content -LiteralPath $readmePath -Value (Get-CodexShadowsocksServerReadme -ReleaseTag $assetInfo.Release.tag_name -AssetName $assetInfo.Asset.name) -Encoding utf8

    [pscustomobject]@{
        OutputDir    = $resolvedOutputDir
        ConfigPath   = $configPath
        InstallScript= $scriptPath
        ServicePath  = $servicePath
        ReadmePath   = $readmePath
        ReleaseTag   = $assetInfo.Release.tag_name
        AssetName    = $assetInfo.Asset.name
    }
}

Initialize-CodexNetworkEnvironment
