function Set-CodexPhoneAlias {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AliasName,

        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    Remove-Item -Path "Alias:$AliasName" -Force -ErrorAction SilentlyContinue
    Set-Alias -Name $AliasName -Value $TargetName -Scope Global -Option AllScope -Force
}

function Get-CodexPhoneToolkitRoot {
    [CmdletBinding()]
    param()

    $toolkitRootCommand = Get-Command 'Get-CodexPowerShellRoot' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $toolkitRootCommand) {
        return (Get-CodexPowerShellRoot)
    }

    $documentsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    return (Join-Path $documentsRoot 'PowerShell\Toolkit')
}

function Ensure-CodexPhoneDirectory {
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

function Get-CodexPhoneStateRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexPhoneDirectory -Path (Join-Path (Get-CodexPhoneToolkitRoot) 'state\phone-debug'))
}

function Get-CodexPhoneDiagnosticsRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexPhoneDirectory -Path (Join-Path (Get-CodexPhoneStateRoot) 'diagnostics'))
}

function Get-CodexPhoneCaptureRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexPhoneDirectory -Path (Join-Path (Get-CodexPhoneStateRoot) 'captures'))
}

function Get-CodexPhoneAuditRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexPhoneDirectory -Path (Join-Path (Get-CodexPhoneStateRoot) 'audits'))
}

function Get-CodexPhoneStorageRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexPhoneDirectory -Path (Join-Path (Get-CodexPhoneStateRoot) 'storage-scans'))
}

function Get-CodexPhonePullRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexPhoneDirectory -Path (Join-Path (Get-CodexPhoneStateRoot) 'pulls'))
}

function Get-CodexPhoneExampleRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexPhoneDirectory -Path (Join-Path (Join-Path (Get-CodexPhoneToolkitRoot) 'examples') 'phone-tools'))
}

function Get-CodexPhoneApkToolsRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexPhoneDirectory -Path (Join-Path (Join-Path (Get-CodexPhoneToolkitRoot) 'examples') 'android-apk-tools'))
}

function Get-CodexPhoneTermuxBootstrapRoot {
    [CmdletBinding()]
    param()

    return (Ensure-CodexPhoneDirectory -Path (Join-Path (Join-Path (Get-CodexPhoneToolkitRoot) 'examples') 'termux-bootstrap'))
}

function Get-CodexPhoneApkCatalogPath {
    [CmdletBinding()]
    param()

    return (Join-Path (Get-CodexPhoneApkToolsRoot) 'phone-apk-tools.json')
}

function Get-CodexPhoneApkImportsPath {
    [CmdletBinding()]
    param()

    return (Join-Path (Join-Path (Get-CodexPhoneToolkitRoot) 'config') 'phone-apk-imports.json')
}

function Resolve-CodexAdbPath {
    [CmdletBinding()]
    param()

    $command = Get-Command adb -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
            return $command.Source
        }

        if (-not [string]::IsNullOrWhiteSpace($command.Path)) {
            return $command.Path
        }
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe'),
        'C:\Program Files\Android\platform-tools\adb.exe',
        'C:\Program Files (x86)\Android\platform-tools\adb.exe',
        'C:\platform-tools\adb.exe',
        'C:\adb\adb.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw 'adb.exe was not found. Install Android SDK Platform-Tools or add adb to PATH.'
}

function Resolve-CodexScrcpyPath {
    [CmdletBinding()]
    param()

    $command = Get-Command scrcpy -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        if (-not [string]::IsNullOrWhiteSpace($command.Source)) {
            return $command.Source
        }

        if (-not [string]::IsNullOrWhiteSpace($command.Path)) {
            return $command.Path
        }
    }

    throw 'scrcpy was not found. Install Genymobile.scrcpy or add scrcpy to PATH.'
}

function Invoke-CodexAdb {
    [CmdletBinding()]
    param(
        [string]$Serial,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $adbPath = Resolve-CodexAdbPath
    $argumentList = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        [void]$argumentList.Add('-s')
        [void]$argumentList.Add($Serial)
    }

    foreach ($argument in $Arguments) {
        [void]$argumentList.Add($argument)
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $adbPath
    $psi.Arguments = [string]::Join(' ', ($argumentList | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    }))
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $output = ($stdout + $stderr).Trim()
    if ($process.ExitCode -ne 0 -and -not $AllowFailure) {
        if ([string]::IsNullOrWhiteSpace($output)) {
            throw ("adb exited with code {0}" -f $process.ExitCode)
        }

        throw $output
    }

    return $output
}

function ConvertTo-CodexPhoneShellLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    return "'" + ($Text -replace "'", "'\''") + "'"
}

function Get-CodexAdbDevices {
    [CmdletBinding()]
    param()

    $output = Invoke-CodexAdb -Arguments @('devices')
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match '^(?<serial>\S+)\s+(?<state>device|unauthorized|offline)$') {
            [void]$rows.Add([pscustomobject]@{
                Serial = $matches.serial
                State  = $matches.state
            })
        }
    }

    return $rows.ToArray()
}

function Resolve-CodexPhoneSerial {
    [CmdletBinding()]
    param(
        [string]$Serial
    )

    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        return $Serial
    }

    $devices = @(Get-CodexAdbDevices | Where-Object State -eq 'device')
    if ($devices.Count -eq 0) {
        throw 'No authorized adb device is connected.'
    }

    if ($devices.Count -gt 1) {
        $serialList = [string]::Join(', ', @($devices | ForEach-Object Serial))
        throw ("Multiple adb devices are connected. Specify -Serial. Devices: {0}" -f $serialList)
    }

    return $devices[0].Serial
}

function Get-CodexPhoneTimestamp {
    [CmdletBinding()]
    param()

    return (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Test-CodexPhoneRemoteExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,

        [Parameter(Mandatory = $true)]
        [string]$RemotePath
    )

    $result = Invoke-CodexAdb -Serial $Serial -Arguments @('shell', 'ls', '-ld', $RemotePath) -AllowFailure
    if ([string]::IsNullOrWhiteSpace($result)) {
        return $false
    }

    return ($result -notmatch 'No such file or directory')
}

function Get-CodexPhoneRemoteKind {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,

        [Parameter(Mandatory = $true)]
        [string]$RemotePath
    )

    $result = Invoke-CodexAdb -Serial $Serial -Arguments @('shell', 'ls', '-ld', $RemotePath) -AllowFailure
    $lastLine = (($result -split "`r?`n" | Select-Object -Last 1).Trim())
    if ([string]::IsNullOrWhiteSpace($lastLine) -or $lastLine -match 'No such file or directory') {
        return 'missing'
    }

    if ($lastLine.StartsWith('d')) {
        return 'directory'
    }

    return 'file'
}

function Get-CodexPhoneRemoteFileSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,

        [Parameter(Mandatory = $true)]
        [string]$RemotePath
    )

    $result = Invoke-CodexAdb -Serial $Serial -Arguments @('shell', 'ls', '-ln', $RemotePath) -AllowFailure
    $lastLine = (($result -split "`r?`n" | Select-Object -Last 1).Trim())
    if ([string]::IsNullOrWhiteSpace($lastLine) -or $lastLine -match 'No such file or directory') {
        return 0L
    }

    if ($lastLine -match '^\S+\s+\d+\s+\d+\s+\d+\s+(?<size>\d+)\s+') {
        return [int64]$matches.size
    }

    if ($lastLine -match '^\S+\s+\d+\s+\S+\s+\S+\s+(?<size>\d+)\s+') {
        return [int64]$matches.size
    }

    return 0L
}

function Get-CodexPhoneBatterySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial
    )

    $batteryText = Invoke-CodexAdb -Serial $Serial -Arguments @('shell', 'dumpsys', 'battery')
    $level = if ($batteryText -match '(?m)^\s*level:\s*(\d+)\s*$') { [int]$matches[1] } else { $null }
    $status = if ($batteryText -match '(?m)^\s*status:\s*(\d+)\s*$') { [int]$matches[1] } else { $null }
    $temperature = if ($batteryText -match '(?m)^\s*temperature:\s*(\d+)\s*$') { [double]$matches[1] / 10.0 } else { $null }
    $powered = if ($batteryText -match '(?m)^\s*powered:\s*(true|false)\s*$') { $matches[1] -eq 'true' } else { $null }

    [pscustomobject]@{
        LevelPercent = $level
        StatusCode   = $status
        TemperatureC = $temperature
        Powered      = $powered
        Raw          = $batteryText
    }
}

function Get-CodexPhoneStatus {
    [CmdletBinding()]
    param(
        [string]$Serial
    )

    $resolvedSerial = Resolve-CodexPhoneSerial -Serial $Serial
    $manufacturer = (Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'getprop', 'ro.product.manufacturer')).Trim()
    $model = (Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'getprop', 'ro.product.model')).Trim()
    $device = (Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'getprop', 'ro.product.device')).Trim()
    $androidVersion = (Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'getprop', 'ro.build.version.release')).Trim()
    $sdk = (Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'getprop', 'ro.build.version.sdk')).Trim()
    $usbMode = (Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'getprop', 'sys.usb.config')).Trim()
    $storage = Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'df', '-h', '/sdcard') -AllowFailure
    $battery = Get-CodexPhoneBatterySummary -Serial $resolvedSerial

    [pscustomobject]@{
        Serial          = $resolvedSerial
        Manufacturer    = $manufacturer
        Model           = $model
        Device          = $device
        AndroidVersion  = $androidVersion
        Sdk             = $sdk
        UsbConfig       = $usbMode
        BatteryPercent  = $battery.LevelPercent
        TemperatureC    = $battery.TemperatureC
        Powered         = $battery.Powered
        StorageSnapshot = $storage
    }
}

function Export-CodexPhoneUiDump {
    [CmdletBinding()]
    param(
        [string]$Serial,

        [string]$OutputDir,

        [string]$NamePrefix = 'phone_current'
    )

    $resolvedSerial = Resolve-CodexPhoneSerial -Serial $Serial
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Join-Path (Get-CodexPhoneCaptureRoot) (Get-CodexPhoneTimestamp)
    }

    Ensure-CodexPhoneDirectory -Path $OutputDir | Out-Null
    $timestamp = Get-CodexPhoneTimestamp
    $remotePng = "/sdcard/${NamePrefix}_${timestamp}.png"
    $remoteXml = "/sdcard/${NamePrefix}_${timestamp}.xml"
    $localPng = Join-Path $OutputDir ("{0}.png" -f $NamePrefix)
    $localXml = Join-Path $OutputDir ("{0}.xml" -f $NamePrefix)

    Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'screencap', '-p', $remotePng) | Out-Null
    Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'uiautomator', 'dump', $remoteXml) | Out-Null
    Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('pull', $remotePng, $localPng) | Out-Null
    Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('pull', $remoteXml, $localXml) | Out-Null
    Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'rm', '-f', $remotePng, $remoteXml) -AllowFailure | Out-Null

    [pscustomobject]@{
        Serial     = $resolvedSerial
        OutputDir  = $OutputDir
        Screenshot = $localPng
        UiXml      = $localXml
    }
}

function Save-CodexPhoneAdbOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,

        [Parameter(Mandatory = $true)]
        [string]$OutFile,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $content = Invoke-CodexAdb -Serial $Serial -Arguments $Arguments -AllowFailure
    Set-Content -LiteralPath $OutFile -Value $content -Encoding UTF8
}

function Invoke-CodexPhoneDiagnostics {
    [CmdletBinding()]
    param(
        [string]$Serial,

        [string]$OutputRoot,

        [int]$Samples = 3,

        [int]$SampleDelaySeconds = 5
    )

    $resolvedSerial = Resolve-CodexPhoneSerial -Serial $Serial
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        $OutputRoot = Get-CodexPhoneDiagnosticsRoot
    }

    Ensure-CodexPhoneDirectory -Path $OutputRoot | Out-Null
    $timestamp = Get-CodexPhoneTimestamp
    $outDir = Join-Path $OutputRoot ("phone-diagnostics-{0}" -f $timestamp)
    Ensure-CodexPhoneDirectory -Path $outDir | Out-Null

    $commands = @(
        @{ Name = 'adb_version.txt'; Arguments = @('version') }
        @{ Name = 'device_getprop.txt'; Arguments = @('shell', 'getprop') }
        @{ Name = 'storage_df_h.txt'; Arguments = @('shell', 'df', '-h') }
        @{ Name = 'battery.txt'; Arguments = @('shell', 'dumpsys', 'battery') }
        @{ Name = 'batterystats.txt'; Arguments = @('shell', 'dumpsys', 'batterystats') }
        @{ Name = 'cpuinfo.txt'; Arguments = @('shell', 'dumpsys', 'cpuinfo') }
        @{ Name = 'meminfo.txt'; Arguments = @('shell', 'dumpsys', 'meminfo') }
        @{ Name = 'activity_processes.txt'; Arguments = @('shell', 'dumpsys', 'activity', 'processes') }
        @{ Name = 'location.txt'; Arguments = @('shell', 'dumpsys', 'location') }
        @{ Name = 'settings_global.txt'; Arguments = @('shell', 'settings', 'list', 'global') }
        @{ Name = 'settings_secure.txt'; Arguments = @('shell', 'settings', 'list', 'secure') }
        @{ Name = 'settings_system.txt'; Arguments = @('shell', 'settings', 'list', 'system') }
        @{ Name = 'packages_third_party.txt'; Arguments = @('shell', 'pm', 'list', 'packages', '-3') }
    )

    foreach ($command in $commands) {
        Save-CodexPhoneAdbOutput -Serial $resolvedSerial -OutFile (Join-Path $outDir $command.Name) -Arguments $command.Arguments
    }

    $sampleDir = Join-Path $outDir 'samples'
    Ensure-CodexPhoneDirectory -Path $sampleDir | Out-Null
    for ($index = 1; $index -le $Samples; $index++) {
        $samplePrefix = '{0:D2}' -f $index
        Save-CodexPhoneAdbOutput -Serial $resolvedSerial -OutFile (Join-Path $sampleDir "$samplePrefix-top.txt") -Arguments @('shell', 'top', '-n', '1')
        Save-CodexPhoneAdbOutput -Serial $resolvedSerial -OutFile (Join-Path $sampleDir "$samplePrefix-cpuinfo.txt") -Arguments @('shell', 'dumpsys', 'cpuinfo')
        Save-CodexPhoneAdbOutput -Serial $resolvedSerial -OutFile (Join-Path $sampleDir "$samplePrefix-meminfo.txt") -Arguments @('shell', 'dumpsys', 'meminfo')
        Save-CodexPhoneAdbOutput -Serial $resolvedSerial -OutFile (Join-Path $sampleDir "$samplePrefix-location.txt") -Arguments @('shell', 'dumpsys', 'location')
        if ($index -lt $Samples) {
            Start-Sleep -Seconds $SampleDelaySeconds
        }
    }

    $readme = @"
Files to check first:
- storage_df_h.txt
- cpuinfo.txt
- meminfo.txt
- location.txt
- samples\01-top.txt

What usually points to lag or battery drain:
- Very low free space on /data or /sdcard
- One app staying near the top of cpuinfo/top across multiple samples
- Repeated location requests in location.txt from the same app
- Heavy background processes in activity_processes.txt
"@
    Set-Content -LiteralPath (Join-Path $outDir 'README.txt') -Value $readme -Encoding UTF8

    [pscustomobject]@{
        Serial    = $resolvedSerial
        OutputDir = $outDir
        Samples   = $Samples
    }
}

function Get-CodexPhoneNoiseDefaultPackages {
    [CmdletBinding()]
    param()

    return @(
        'com.xingin.xhs',
        'com.zhihu.android',
        'com.instagram.android',
        'com.instagram.barcelona',
        'com.facebook.katana',
        'com.linkedin.android',
        'com.tencent.mm',
        'com.tencent.mobileqq',
        'com.tencent.wework',
        'com.xiaomi.discover',
        'com.miui.msa.global',
        'com.facebook.services',
        'com.facebook.appmanager',
        'com.facebook.system'
    )
}

function Get-CodexPhoneNoiseMetricCount {
    [CmdletBinding()]
    param(
        [string]$Text,
        [string]$Pattern
    )

    return ([regex]::Matches($Text, $Pattern)).Count
}

function Get-CodexPhoneStandbyBucketName {
    [CmdletBinding()]
    param(
        [string]$RawValue
    )

    switch ($RawValue.Trim()) {
        '5' { 'exempted' }
        '10' { 'active' }
        '20' { 'working_set' }
        '30' { 'frequent' }
        '40' { 'rare' }
        '45' { 'restricted' }
        '50' { 'never' }
        default { "unknown($RawValue)" }
    }
}

function Get-CodexPhoneNoiseMetrics {
    [CmdletBinding()]
    param(
        [string]$LogText,
        [string]$Package
    )

    $escaped = [regex]::Escape($Package)
    [pscustomobject]@{
        BgStartDenied = Get-CodexPhoneNoiseMetricCount -Text $LogText -Pattern "Background start not allowed:.*$escaped"
        RejectRestart = Get-CodexPhoneNoiseMetricCount -Text $LogText -Pattern "Reject RestartService packageName ?:? ?$escaped"
        UnableAutoStart = Get-CodexPhoneNoiseMetricCount -Text $LogText -Pattern "Unable to launch app $escaped"
        PermissionDenial = Get-CodexPhoneNoiseMetricCount -Text $LogText -Pattern "Permission Denial:.*$escaped"
        AlarmMentions = Get-CodexPhoneNoiseMetricCount -Text $LogText -Pattern "AlarmManager:.*$escaped"
        ProcessDied = Get-CodexPhoneNoiseMetricCount -Text $LogText -Pattern "Process $escaped.*has died"
    }
}

function Get-CodexPhoneTextValue {
    [CmdletBinding()]
    param(
        [string]$Text,
        [string]$Pattern
    )

    $match = [regex]::Match($Text, "(?m)$Pattern")
    if (-not $match.Success) {
        return $null
    }

    return $match.Value.Trim()
}

function Invoke-CodexPhoneNoiseAudit {
    [CmdletBinding()]
    param(
        [string]$Serial,

        [string[]]$Packages = (Get-CodexPhoneNoiseDefaultPackages),

        [switch]$ApplyMitigations,

        [switch]$MuteNotifications,

        [switch]$ForceStop,

        [string]$OutputPath
    )

    $resolvedSerial = Resolve-CodexPhoneSerial -Serial $Serial
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        Ensure-CodexPhoneDirectory -Path (Get-CodexPhoneAuditRoot) | Out-Null
        $OutputPath = Join-Path (Get-CodexPhoneAuditRoot) ("phone-noise-audit-{0}.json" -f (Get-CodexPhoneTimestamp))
    }

    $alarmText = Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'dumpsys', 'alarm')
    $jobText = Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'dumpsys', 'jobscheduler')
    $logcatText = Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('logcat', '-d', '-v', 'threadtime') -AllowFailure
    $disabledText = Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'pm', 'list', 'packages', '-d') -AllowFailure

    $results = foreach ($package in $Packages) {
        $bucketRaw = (Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'am', 'get-standby-bucket', $package) -AllowFailure).Trim()
        $appOpsText = Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'cmd', 'appops', 'get', $package) -AllowFailure
        $packageText = Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'dumpsys', 'package', $package) -AllowFailure
        $pkgRegex = [regex]::Escape($package)

        $wakeups = 0
        if ($alarmText -match "(?m)^.*$pkgRegex.*?(\d+)\s+wakeups:.*$") {
            $wakeups = [int]$Matches[1]
        }

        $jobCount = [regex]::Matches($jobText, "(?m)^JOB #.*$pkgRegex.*$").Count
        $noise = Get-CodexPhoneNoiseMetrics -LogText $logcatText -Package $package

        $runAnyLine = Get-CodexPhoneTextValue -Text $appOpsText -Pattern '^RUN_ANY_IN_BACKGROUND:.*$'
        $runInLine = Get-CodexPhoneTextValue -Text $appOpsText -Pattern '^RUN_IN_BACKGROUND:.*$'
        $startFgLine = Get-CodexPhoneTextValue -Text $appOpsText -Pattern '^START_FOREGROUND:.*$'
        $notificationsLine = Get-CodexPhoneTextValue -Text $appOpsText -Pattern '^POST_NOTIFICATION:.*$'
        $fineLocationLine = Get-CodexPhoneTextValue -Text $packageText -Pattern 'android\.permission\.ACCESS_FINE_LOCATION: granted=.*$'
        $coarseLocationLine = Get-CodexPhoneTextValue -Text $packageText -Pattern 'android\.permission\.ACCESS_COARSE_LOCATION: granted=.*$'

        $disabled = $disabledText -match $pkgRegex
        $noiseScore = [math]::Round(
            ($wakeups / 25.0) +
            ($noise.AlarmMentions / 40.0) +
            ($noise.BgStartDenied * 4.0) +
            ($noise.RejectRestart * 3.0) +
            ($noise.UnableAutoStart * 3.0) +
            ($noise.PermissionDenial * 2.0) +
            ($noise.ProcessDied * 1.5) +
            ($jobCount * 0.5),
            1
        )

        [pscustomobject]@{
            Package = $package
            StandbyBucket = Get-CodexPhoneStandbyBucketName -RawValue $bucketRaw
            Wakeups = $wakeups
            JobCount = $jobCount
            BgStartDenied = $noise.BgStartDenied
            RejectRestart = $noise.RejectRestart
            UnableAutoStart = $noise.UnableAutoStart
            PermissionDenial = $noise.PermissionDenial
            AlarmMentions = $noise.AlarmMentions
            ProcessDied = $noise.ProcessDied
            NoiseScore = $noiseScore
            RunInBackground = if ($runInLine) { $runInLine } else { 'n/a' }
            RunAnyInBackground = if ($runAnyLine) { $runAnyLine } else { 'n/a' }
            StartForeground = if ($startFgLine) { $startFgLine } else { 'n/a' }
            FineLocation = if ($fineLocationLine) { $fineLocationLine } else { 'n/a' }
            CoarseLocation = if ($coarseLocationLine) { $coarseLocationLine } else { 'n/a' }
            Notifications = if ($notificationsLine) { $notificationsLine } else { 'n/a' }
            Disabled = $disabled
        }
    }

    if ($ApplyMitigations) {
        foreach ($package in $Packages) {
            Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'am', 'set-standby-bucket', $package, 'restricted') -AllowFailure | Out-Null
            Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'cmd', 'appops', 'set', $package, 'RUN_IN_BACKGROUND', 'ignore') -AllowFailure | Out-Null
            Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'cmd', 'appops', 'set', $package, 'RUN_ANY_IN_BACKGROUND', 'ignore') -AllowFailure | Out-Null
            if ($ForceStop) {
                Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'am', 'force-stop', $package) -AllowFailure | Out-Null
            }
        }
    }

    if ($MuteNotifications) {
        foreach ($package in $Packages) {
            Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'cmd', 'appops', 'set', $package, 'POST_NOTIFICATION', 'ignore') -AllowFailure | Out-Null
            if ($ForceStop) {
                Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'am', 'force-stop', $package) -AllowFailure | Out-Null
            }
        }
    }

    $summary = @($results | Sort-Object @{ Expression = 'NoiseScore'; Descending = $true }, @{ Expression = 'Wakeups'; Descending = $true })
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return $summary
}

function Get-CodexPhoneStorageDefaultFolders {
    [CmdletBinding()]
    param()

    return @(
        'DCIM',
        'Pictures',
        'Movies',
        'Download',
        'Documents',
        'Tencent',
        'Android',
        'MIUI',
        'Music',
        'Recordings'
    )
}

function Get-CodexPhoneFolderKilobytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,

        [Parameter(Mandatory = $true)]
        [string]$RemotePath
    )

    $output = Invoke-CodexAdb -Serial $Serial -Arguments @('shell', 'du', '-sk', $RemotePath) -AllowFailure
    $lastLine = (($output -split "`r?`n" | Select-Object -Last 1).Trim())
    if ($lastLine -match '^(?<kb>\d+)\s+') {
        return [int64]$matches.kb
    }

    return 0L
}

function Get-CodexPrettyBytes {
    [CmdletBinding()]
    param(
        [int64]$Bytes
    )

    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "{0} B" -f $Bytes
}

function Get-CodexPhoneStorageSummary {
    [CmdletBinding()]
    param(
        [string]$Serial,

        [string[]]$Folders = (Get-CodexPhoneStorageDefaultFolders),

        [string]$OutputDir
    )

    $resolvedSerial = Resolve-CodexPhoneSerial -Serial $Serial
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Join-Path (Get-CodexPhoneStorageRoot) (Get-CodexPhoneTimestamp)
    }

    Ensure-CodexPhoneDirectory -Path $OutputDir | Out-Null

    $rows = foreach ($folder in $Folders) {
        $remotePath = "/sdcard/$folder"
        if (-not (Test-CodexPhoneRemoteExists -Serial $resolvedSerial -RemotePath $remotePath)) {
            continue
        }

        $kilobytes = Get-CodexPhoneFolderKilobytes -Serial $resolvedSerial -RemotePath $remotePath
        $bytes = $kilobytes * 1KB
        [pscustomobject]@{
            Folder = $folder
            RemotePath = $remotePath
            Kilobytes = $kilobytes
            Bytes = $bytes
            PrettySize = Get-CodexPrettyBytes -Bytes $bytes
        }
    }

    $summary = @($rows | Sort-Object Bytes -Descending)
    $summary | Export-Csv -LiteralPath (Join-Path $OutputDir 'folder_summary.csv') -NoTypeInformation -Encoding UTF8
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDir 'folder_summary.json') -Encoding UTF8
    $dfText = Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'df', '-h', '/sdcard') -AllowFailure
    Set-Content -LiteralPath (Join-Path $OutputDir 'storage_df_h.txt') -Value $dfText -Encoding UTF8

    [pscustomobject]@{
        Serial = $resolvedSerial
        OutputDir = $OutputDir
        Summary = $summary
        StorageSnapshot = $dfText
    }
}

function Invoke-CodexPhoneTransfer {
    [CmdletBinding()]
    param(
        [string]$Serial,

        [Parameter(Mandatory = $true)]
        [string]$PhonePath,

        [string]$LocalRoot,

        [switch]$DeleteRemote
    )

    $resolvedSerial = Resolve-CodexPhoneSerial -Serial $Serial
    if ([string]::IsNullOrWhiteSpace($LocalRoot)) {
        $LocalRoot = Get-CodexPhonePullRoot
    }

    Ensure-CodexPhoneDirectory -Path $LocalRoot | Out-Null
    $kind = Get-CodexPhoneRemoteKind -Serial $resolvedSerial -RemotePath $PhonePath
    if ($kind -eq 'missing') {
        throw ("Remote path was not found: {0}" -f $PhonePath)
    }

    $safeName = ($PhonePath.TrimStart('/') -replace '[\\/:*?"<>|]', '_')
    $targetRoot = Join-Path $LocalRoot $safeName
    Ensure-CodexPhoneDirectory -Path $targetRoot | Out-Null

    $pullTarget = if ($kind -eq 'directory') { $targetRoot } else { Split-Path -Parent (Join-Path $targetRoot (Split-Path $PhonePath -Leaf)) }
    Ensure-CodexPhoneDirectory -Path $pullTarget | Out-Null

    Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('pull', $PhonePath, $pullTarget) | Out-Null

    $localPath = if ($kind -eq 'directory') {
        Join-Path $pullTarget (Split-Path $PhonePath -Leaf)
    } else {
        Join-Path $pullTarget (Split-Path $PhonePath -Leaf)
    }

    if (-not (Test-Path -LiteralPath $localPath)) {
        throw ("adb pull completed but expected local output is missing: {0}" -f $localPath)
    }

    if ($DeleteRemote) {
        if ($kind -eq 'directory') {
            Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'rm', '-rf', $PhonePath) | Out-Null
        } else {
            $remoteSize = Get-CodexPhoneRemoteFileSize -Serial $resolvedSerial -RemotePath $PhonePath
            $localSize = (Get-Item -LiteralPath $localPath).Length
            if ($remoteSize -gt 0 -and $localSize -ne $remoteSize) {
                throw ("Local file size does not match remote size for {0}" -f $PhonePath)
            }

            Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'rm', '-f', $PhonePath) | Out-Null
        }
    }

    [pscustomobject]@{
        Serial = $resolvedSerial
        RemotePath = $PhonePath
        Kind = $kind
        LocalPath = $localPath
        DeletedRemote = [bool]$DeleteRemote
    }
}

function Copy-CodexPhonePath {
    [CmdletBinding()]
    param(
        [string]$Serial,

        [Parameter(Mandatory = $true)]
        [string]$PhonePath,

        [string]$LocalRoot
    )

    Invoke-CodexPhoneTransfer -Serial $Serial -PhonePath $PhonePath -LocalRoot $LocalRoot
}

function Move-CodexPhonePath {
    [CmdletBinding()]
    param(
        [string]$Serial,

        [Parameter(Mandatory = $true)]
        [string]$PhonePath,

        [string]$LocalRoot
    )

    Invoke-CodexPhoneTransfer -Serial $Serial -PhonePath $PhonePath -LocalRoot $LocalRoot -DeleteRemote
}

function Start-CodexPhoneMirror {
    [CmdletBinding()]
    param(
        [string]$Serial,

        [switch]$StayAwake,

        [switch]$TurnScreenOff,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ExtraArguments = @()
    )

    $resolvedSerial = Resolve-CodexPhoneSerial -Serial $Serial
    $scrcpyPath = Resolve-CodexScrcpyPath
    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add('-s')
    [void]$arguments.Add($resolvedSerial)
    if ($StayAwake) {
        [void]$arguments.Add('--stay-awake')
    }
    if ($TurnScreenOff) {
        [void]$arguments.Add('--turn-screen-off')
    }
    foreach ($argument in $ExtraArguments) {
        [void]$arguments.Add($argument)
    }

    Start-Process -FilePath $scrcpyPath -ArgumentList $arguments.ToArray() | Out-Null
    [pscustomobject]@{
        Serial = $resolvedSerial
        Command = $scrcpyPath
        Arguments = $arguments.ToArray()
    }
}

function Start-CodexPhoneShizuku {
    [CmdletBinding()]
    param(
        [string]$Serial
    )

    $resolvedSerial = Resolve-CodexPhoneSerial -Serial $Serial
    $usbMode = (Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'getprop', 'sys.usb.config')).Trim()
    if ($usbMode -notmatch 'adb') {
        throw 'The phone is not exposing an adb channel right now. Make sure USB debugging is still enabled.'
    }

    $startResult = Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'sh', '/sdcard/Android/data/moe.shizuku.privileged.api/start.sh')
    if ($startResult -notmatch 'exit with 0') {
        throw ("The Shizuku startup script did not report success.`n{0}" -f $startResult)
    }

    Invoke-CodexAdb -Serial $resolvedSerial -Arguments @('shell', 'monkey', '-p', 'moe.shizuku.privileged.api', '-c', 'android.intent.category.LAUNCHER', '1') -AllowFailure | Out-Null

    [pscustomobject]@{
        Serial = $resolvedSerial
        Status = 'Started'
        Output = $startResult
    }
}

function Get-CodexPhoneApkCatalog {
    [CmdletBinding()]
    param()

    $catalogPath = Get-CodexPhoneApkCatalogPath
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        return @()
    }

    $data = Get-Content -LiteralPath $catalogPath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($data -is [System.Array]) {
        return $data
    }

    return @($data)
}

function Get-CodexImportedPhoneApkEntries {
    [CmdletBinding()]
    param()

    $importsPath = Get-CodexPhoneApkImportsPath
    if (-not (Test-Path -LiteralPath $importsPath)) {
        return @()
    }

    $data = Get-Content -LiteralPath $importsPath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ($data -is [System.Array]) {
        return $data
    }

    return @($data)
}

function Get-CodexPhoneApkInventory {
    [CmdletBinding()]
    param()

    $root = Get-CodexPhoneApkToolsRoot
    $catalogByFile = @{}
    foreach ($item in Get-CodexPhoneApkCatalog) {
        if ($null -ne $item.FileName) {
            $catalogByFile[[string]$item.FileName] = $item
        }
    }

    $importByFile = @{}
    foreach ($item in Get-CodexImportedPhoneApkEntries) {
        if ($null -ne $item.FileName) {
            $importByFile[[string]$item.FileName] = $item
        }
    }

    $localFiles = @(Get-ChildItem -LiteralPath $root -Filter '*.apk' -File -ErrorAction SilentlyContinue)
    $rows = foreach ($file in $localFiles) {
        $catalog = $catalogByFile[$file.Name]
        $import = $importByFile[$file.Name]
        [pscustomobject]@{
            Name = if ($null -ne $catalog -and $null -ne $catalog.Name) { [string]$catalog.Name } else { $file.BaseName }
            FileName = $file.Name
            LocalPath = $file.FullName
            Size = $file.Length
            Sha256 = if ($null -ne $import -and $null -ne $import.Sha256) { [string]$import.Sha256 } else { '' }
            RecommendedUse = if ($null -ne $catalog -and $null -ne $catalog.Purpose) { [string]$catalog.Purpose } else { '' }
            SourceHint = if ($null -ne $catalog -and $null -ne $catalog.SourceHint) { [string]$catalog.SourceHint } else { '' }
            ImportedAt = if ($null -ne $import -and $null -ne $import.ImportedAt) { [string]$import.ImportedAt } else { '' }
        }
    }

    return @($rows | Sort-Object Name, FileName)
}

function Get-CodexPhoneCommonApkCandidatePaths {
    [CmdletBinding()]
    param()

    $desktop = [Environment]::GetFolderPath('Desktop')
    $candidates = @(
        (Join-Path $desktop 'Temp Desktop\android-apk-tools'),
        (Join-Path $desktop 'Temp Desktop\termux-app_v0.118.3_arm64-v8a.apk')
    )

    return @($candidates | Where-Object { Test-Path -LiteralPath $_ })
}

function Import-CodexPhoneApkTools {
    [CmdletBinding()]
    param(
        [string[]]$LiteralPath = @(),

        [switch]$IncludeCommonLocalCandidates
    )

    $sourceItems = New-Object System.Collections.Generic.List[string]
    foreach ($item in $LiteralPath) {
        if (-not [string]::IsNullOrWhiteSpace($item) -and (Test-Path -LiteralPath $item)) {
            [void]$sourceItems.Add((Resolve-Path -LiteralPath $item).Path)
        }
    }

    if ($IncludeCommonLocalCandidates) {
        foreach ($item in Get-CodexPhoneCommonApkCandidatePaths) {
            [void]$sourceItems.Add($item)
        }
    }

    $apkFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($item in @($sourceItems | Select-Object -Unique)) {
        $resolvedItem = Get-Item -LiteralPath $item -ErrorAction Stop
        if ($resolvedItem.PSIsContainer) {
            foreach ($apk in Get-ChildItem -LiteralPath $resolvedItem.FullName -Filter '*.apk' -File -ErrorAction SilentlyContinue) {
                [void]$apkFiles.Add($apk)
            }
        } elseif ($resolvedItem.Extension -ieq '.apk') {
            [void]$apkFiles.Add($resolvedItem)
        }
    }

    if ($apkFiles.Count -eq 0) {
        throw 'No APK files were found to import.'
    }

    $targetRoot = Get-CodexPhoneApkToolsRoot
    $importRecords = New-Object System.Collections.Generic.List[object]
    foreach ($apk in @($apkFiles | Sort-Object FullName -Unique)) {
        $destination = Join-Path $targetRoot $apk.Name
        Copy-Item -LiteralPath $apk.FullName -Destination $destination -Force
        $hash = Get-FileHash -LiteralPath $destination -Algorithm SHA256
        [void]$importRecords.Add([pscustomobject]@{
            FileName = $apk.Name
            LocalPath = $destination
            SourcePath = $apk.FullName
            Size = $apk.Length
            Sha256 = $hash.Hash
            ImportedAt = (Get-Date).ToString('o')
        })
    }

    Ensure-CodexPhoneDirectory -Path (Split-Path -Parent (Get-CodexPhoneApkImportsPath)) | Out-Null
    $importRecords | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-CodexPhoneApkImportsPath) -Encoding UTF8
    return $importRecords.ToArray()
}

function Install-CodexPhoneApk {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [string]$Serial,

        [Parameter(ParameterSetName = 'ByName', Mandatory = $true)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByPath', Mandatory = $true)]
        [string]$ApkPath,

        [switch]$Reinstall,

        [switch]$GrantAllRuntimePermissions
    )

    $resolvedSerial = Resolve-CodexPhoneSerial -Serial $Serial
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $entry = Get-CodexPhoneApkInventory | Where-Object { $_.Name -eq $Name -or $_.FileName -eq $Name } | Select-Object -First 1
        if ($null -eq $entry) {
            throw ("APK '{0}' was not found in toolkit examples. Use phone-apk-list or phone-apk-import first." -f $Name)
        }

        $ApkPath = $entry.LocalPath
    }

    if (-not (Test-Path -LiteralPath $ApkPath)) {
        throw ("APK path was not found: {0}" -f $ApkPath)
    }

    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add('install')
    if ($Reinstall) {
        [void]$arguments.Add('-r')
    }
    if ($GrantAllRuntimePermissions) {
        [void]$arguments.Add('-g')
    }
    [void]$arguments.Add($ApkPath)

    $result = Invoke-CodexAdb -Serial $resolvedSerial -Arguments $arguments.ToArray()
    [pscustomobject]@{
        Serial = $resolvedSerial
        ApkPath = $ApkPath
        Output = $result
    }
}

function Show-CodexPhoneHelp {
    [CmdletBinding()]
    param()

    $lines = @(
        'Codex phone / Android helpers',
        '',
        '  phone-status        show connected phone model, Android version, battery, and storage snapshot',
        '  phone-diag          collect a timestamped adb diagnostics bundle',
        '  phone-noise-audit   audit wakeups, appops, alarms, and background noise for selected packages',
        '  phone-storage-scan  summarize major /sdcard folders by size',
        '  phone-ui-dump       capture the current screenshot plus UI hierarchy XML',
        '  phone-pull          safely pull a phone path into toolkit state',
        '  phone-archive       pull a phone path and then delete the remote original after verification',
        '  phone-mirror        start a scrcpy mirror session',
        '  phone-shizuku-start start Shizuku over adb',
        '  phone-apk-list      list curated / imported APK helper tools under toolkit examples',
        '  phone-apk-import    copy local APK helper tools into toolkit state',
        '  phone-apk-install   install an APK by toolkit name or explicit path',
        '',
        'Examples:',
        '  phone-status',
        '  phone-diag -Samples 2',
        '  phone-ui-dump -OutputDir C:\Exports\phone-ui',
        '  phone-storage-scan',
        '  phone-pull -PhonePath /sdcard/Download',
        '  phone-archive -PhonePath /sdcard/DCIM/Camera/VID_20260426_123456.mp4',
        '  phone-noise-audit -Packages com.tencent.mm,com.zhihu.android',
        '  phone-mirror -StayAwake',
        '  phone-shizuku-start',
        '  phone-apk-import -IncludeCommonLocalCandidates',
        '  phone-apk-install -Name Shizuku -Reinstall'
    )

    Write-Host ([string]::Join("`n", $lines)) -ForegroundColor Cyan
}

Set-CodexPhoneAlias -AliasName 'phone-help' -TargetName 'Show-CodexPhoneHelp'
Set-CodexPhoneAlias -AliasName 'phone-status' -TargetName 'Get-CodexPhoneStatus'
Set-CodexPhoneAlias -AliasName 'phone-diag' -TargetName 'Invoke-CodexPhoneDiagnostics'
Set-CodexPhoneAlias -AliasName 'phone-noise-audit' -TargetName 'Invoke-CodexPhoneNoiseAudit'
Set-CodexPhoneAlias -AliasName 'phone-storage-scan' -TargetName 'Get-CodexPhoneStorageSummary'
Set-CodexPhoneAlias -AliasName 'phone-ui-dump' -TargetName 'Export-CodexPhoneUiDump'
Set-CodexPhoneAlias -AliasName 'phone-pull' -TargetName 'Copy-CodexPhonePath'
Set-CodexPhoneAlias -AliasName 'phone-archive' -TargetName 'Move-CodexPhonePath'
Set-CodexPhoneAlias -AliasName 'phone-mirror' -TargetName 'Start-CodexPhoneMirror'
Set-CodexPhoneAlias -AliasName 'phone-shizuku-start' -TargetName 'Start-CodexPhoneShizuku'
Set-CodexPhoneAlias -AliasName 'phone-apk-list' -TargetName 'Get-CodexPhoneApkInventory'
Set-CodexPhoneAlias -AliasName 'phone-apk-import' -TargetName 'Import-CodexPhoneApkTools'
Set-CodexPhoneAlias -AliasName 'phone-apk-install' -TargetName 'Install-CodexPhoneApk'
