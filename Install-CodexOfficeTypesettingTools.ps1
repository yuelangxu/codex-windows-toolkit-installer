[CmdletBinding()]
param(
    [string]$ToolkitRoot,
    [string]$InstallScope = 'Auto',
    [switch]$SkipLibreOfficeExtensions,
    [switch]$SkipPowerPointAddIn,
    [switch]$SkipNpmPackages
)

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'common.ps1')

$context = Get-ToolkitContext -ToolkitRoot $ToolkitRoot
$resolvedScope = Resolve-PreferredInstallScope -InstallScope $InstallScope

function Invoke-OfficeTypesettingProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @()
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -WindowStyle Hidden
    return $process.ExitCode
}

function Invoke-OfficeTypesettingWingetInstall {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Package
    )

    $state = Get-PackageState -Package $Package
    if ($state.Installed) {
        Write-Note ("Skipping {0}; already installed." -f $Package.DisplayName)
        return
    }

    Write-Host ("Installing {0} ({1})" -f $Package.DisplayName, $Package.Id) -ForegroundColor Yellow

    $arguments = @(
        'install',
        '-e',
        '--id', $Package.Id,
        '--source', 'winget',
        '--disable-interactivity',
        '--accept-source-agreements',
        '--accept-package-agreements'
    )

    $packageScope = if ($Package.ContainsKey('Scope')) { [string]$Package.Scope } else { $resolvedScope }
    if (-not [string]::IsNullOrWhiteSpace($packageScope) -and $packageScope -notin @('default', 'none')) {
        $arguments += @('--scope', $packageScope)
    }

    $wingetPath = Find-CommandPath -Name 'winget'
    $wingetExitCode = Invoke-OfficeTypesettingProcess -FilePath $wingetPath -ArgumentList $arguments
    if ($wingetExitCode -ne 0) {
        $postInstallState = Get-PackageState -Package $Package
        if ($postInstallState.Installed) {
            Write-Warning ("winget returned a non-zero exit code for {0}, but the package is now detectable. Continuing." -f $Package.DisplayName)
            return
        }

        throw "winget failed while installing $($Package.Id)."
    }
}

function Install-OfficeTypesettingNpmPackages {
    if ($SkipNpmPackages) {
        Write-Note 'Skipping Office typesetting npm global packages by request.'
        return
    }

    if (-not (Test-CommandAvailable -Name 'npm')) {
        Write-Warning 'npm is not available, so Marp CLI cannot be installed. Install Node.js, then rerun this script.'
        return
    }

    foreach ($package in $script:Manifest.OfficeTypesettingNpmGlobalPackages) {
        $missingCommands = @($package.Commands | Where-Object { -not (Test-CommandAvailable -Name $_) })
        if ($missingCommands.Count -eq 0) {
            Write-Note ("Skipping {0}; commands already available." -f $package.DisplayName)
            continue
        }

        Write-Host ("Installing npm package {0} ({1})" -f $package.DisplayName, $package.Package) -ForegroundColor Yellow
        $npmExitCode = Invoke-OfficeTypesettingProcess -FilePath 'npm.cmd' -ArgumentList @('install', '-g', $package.Package)
        if ($npmExitCode -ne 0) {
            throw "npm failed while installing $($package.Package)."
        }
    }
}

function Get-OfficeTypesettingDownloadRoot {
    $localProgramsRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs'
    $officeTypesettingRoot = Join-Path $localProgramsRoot 'OfficeTypesettingTools'
    Ensure-Directory -Path $officeTypesettingRoot

    $downloadRoot = Join-Path $officeTypesettingRoot 'downloads'
    Ensure-Directory -Path $downloadRoot
    return $downloadRoot
}

function Get-OfficeTypesettingStateRoot {
    $localProgramsRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs'
    $officeTypesettingRoot = Join-Path $localProgramsRoot 'OfficeTypesettingTools'
    Ensure-Directory -Path $officeTypesettingRoot

    $stateRoot = Join-Path $officeTypesettingRoot 'state'
    Ensure-Directory -Path $stateRoot
    return $stateRoot
}

function Get-LibreOfficeExtensionSuppressMarker {
    Join-Path (Get-OfficeTypesettingStateRoot) 'libreoffice-extensions.suppressed'
}

function Test-LibreOfficeExtensionInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExtensionLeafName
    )

    $appData = [Environment]::GetFolderPath('ApplicationData')
    $patterns = @(
        (Join-Path $appData ("LibreOffice\4\user\uno_packages\cache\uno_packages\*\{0}" -f $ExtensionLeafName)),
        (Join-Path $appData ("LibreOffice\4\user\extensions\tmp\extensions\*\{0}" -f $ExtensionLeafName))
    )

    foreach ($pattern in $patterns) {
        $match = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $match) {
            return $true
        }
    }

    return $false
}

function Sync-OfficeTypesettingProcessPath {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $segments = New-Object System.Collections.Generic.List[string]
    foreach ($pathValue in @($userPath, $machinePath, $env:Path)) {
        if ([string]::IsNullOrWhiteSpace($pathValue)) {
            continue
        }

        foreach ($segment in ($pathValue -split ';')) {
            $trimmedSegment = $segment.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmedSegment)) {
                continue
            }

            if (-not $segments.Contains($trimmedSegment)) {
                [void]$segments.Add($trimmedSegment)
            }
        }
    }

    $env:Path = [string]::Join(';', $segments)
}

function Copy-OfficeFileWithLockTolerance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [string]$DisplayName = 'file'
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        $sourceItem = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
        $destinationItem = Get-Item -LiteralPath $DestinationPath -ErrorAction SilentlyContinue
        if ($null -ne $destinationItem -and $destinationItem.Length -eq $sourceItem.Length) {
            Write-Note ("Skipping {0}; destination already exists with matching size at {1}" -f $DisplayName, $DestinationPath)
            return
        }
    }

    try {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    } catch [System.IO.IOException] {
        if (Test-Path -LiteralPath $DestinationPath) {
            Write-Warning ("{0} is currently in use, but an existing copy is already present at {1}. Keeping the existing file." -f $DisplayName, $DestinationPath)
            return
        }

        throw
    }
}

function Release-PowerPointComObject {
    param(
        $Object
    )

    if ($null -eq $Object) {
        return
    }

    if ([Runtime.InteropServices.Marshal]::IsComObject($Object)) {
        [Runtime.InteropServices.Marshal]::ReleaseComObject($Object) | Out-Null
    }
}

function Test-PowerPointRetryableComException {
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception
    )

    if ($Exception.Message -match 'RPC_E_CALL_REJECTED|Call was rejected by callee|The message filter indicated that the application is busy') {
        return $true
    }

    return $Exception.HResult -in @(-2147418111, -2147417846)
}

function Invoke-PowerPointComAction {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,

        [int]$RetryCount = 8,

        [int]$RetryDelayMilliseconds = 350
    )

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            return & $Action
        } catch {
            if ($attempt -ge $RetryCount -or -not (Test-PowerPointRetryableComException -Exception $_.Exception)) {
                throw
            }

            Start-Sleep -Milliseconds ($RetryDelayMilliseconds * $attempt)
        }
    }
}

function Close-PowerPointComInstance {
    param(
        [Parameter(Mandatory = $true)]
        $Application,

        [switch]$Quit
    )

    if ($Quit) {
        try {
            Invoke-PowerPointComAction -Action { $Application.Quit() } | Out-Null
        } catch {
        }
    }

    Release-PowerPointComObject -Object $Application
}

function Get-PowerPointRegistryVersion {
    $defaultVersion = '16.0'
    $officeRoot = 'HKCU:\Software\Microsoft\Office'
    if (-not (Test-Path -LiteralPath $officeRoot)) {
        return $defaultVersion
    }

    $versions = Get-ChildItem -LiteralPath $officeRoot -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d+\.\d+$' } |
        Sort-Object { [version]$_.PSChildName } -Descending
    if ($versions) {
        return $versions[0].PSChildName
    }

    return $defaultVersion
}

function Get-PowerPointAddInRegistryRoot {
    $version = Get-PowerPointRegistryVersion
    return "HKCU:\Software\Microsoft\Office\$version\PowerPoint\AddIns"
}

function Get-PowerPointAddInLoadTimesPath {
    $version = Get-PowerPointRegistryVersion
    return "HKCU:\Software\Microsoft\Office\$version\PowerPoint\AddInLoadTimes"
}

function Set-PowerPointAddInRegistryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AddInPath
    )

    $resolvedAddInPath = [IO.Path]::GetFullPath($AddInPath)
    $addInName = [IO.Path]::GetFileNameWithoutExtension($resolvedAddInPath)
    $registryRoot = Get-PowerPointAddInRegistryRoot
    $entryPath = Join-Path $registryRoot $addInName

    if (-not (Test-Path -LiteralPath $registryRoot)) {
        New-Item -Path $registryRoot -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $entryPath)) {
        New-Item -Path $entryPath -Force | Out-Null
    }

    Set-ItemProperty -LiteralPath $entryPath -Name '(default)' -Value $addInName -Force
    Set-ItemProperty -LiteralPath $entryPath -Name 'Path' -Value $resolvedAddInPath -Force
    Set-ItemProperty -LiteralPath $entryPath -Name 'AutoLoad' -Value 1 -Type DWord -Force

    $loadTimesPath = Get-PowerPointAddInLoadTimesPath
    if (Test-Path -LiteralPath $loadTimesPath) {
        Remove-ItemProperty -LiteralPath $loadTimesPath -Name $resolvedAddInPath -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $loadTimesPath -Name ([IO.Path]::GetFileName($resolvedAddInPath)) -ErrorAction SilentlyContinue
    }
}

function Register-PowerPointAddInForAutoLoad {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AddInPath
    )

    $resolvedAddInPath = [IO.Path]::GetFullPath($AddInPath)
    Set-PowerPointAddInRegistryEntry -AddInPath $resolvedAddInPath

    $ppt = $null
    $addin = $null
    $addIns = $null
    $createdInstance = $false
    $comWarning = $null

    try {
        try {
            try {
                $ppt = [Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
            } catch {
                $ppt = $null
            }

            if ($null -eq $ppt) {
                $ppt = New-Object -ComObject PowerPoint.Application
                $createdInstance = $true
            }

            try {
                Invoke-PowerPointComAction -Action { $ppt.Visible = -1 } | Out-Null
            } catch {
            }
            $addIns = Invoke-PowerPointComAction -Action { $ppt.AddIns }
            if ($null -eq $addIns) {
                throw 'PowerPoint AddIns collection was unavailable.'
            }

            $addInCount = Invoke-PowerPointComAction -Action { $addIns.Count }
            for ($index = 1; $index -le $addInCount; $index++) {
                $candidate = Invoke-PowerPointComAction -Action { $addIns.Item($index) }
                try {
                    if ($null -ne $candidate -and $candidate.FullName -and $candidate.FullName.Equals($resolvedAddInPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $addin = $candidate
                        break
                    }
                } finally {
                    if ($null -ne $candidate -and ($null -eq $addin -or -not [object]::ReferenceEquals($candidate, $addin))) {
                        Release-PowerPointComObject -Object $candidate
                    }
                }
            }

            if ($null -eq $addin) {
                $addin = Invoke-PowerPointComAction -Action { $addIns.Add($resolvedAddInPath) }
            }

            # AutoLoad is the durable setting: it also marks the add-in as registered.
            Invoke-PowerPointComAction -Action { $addin.AutoLoad = -1 } | Out-Null
            Invoke-PowerPointComAction -Action { $addin.Loaded = -1 } | Out-Null
        } catch {
            $comWarning = $_.Exception.Message
        }
    } finally {
        Release-PowerPointComObject -Object $addin
        Release-PowerPointComObject -Object $addIns

        if ($null -ne $ppt) {
            Close-PowerPointComInstance -Application $ppt -Quit:$createdInstance
        }
    }

    return [pscustomobject]@{
        Path = $resolvedAddInPath
        RegistryAutoLoad = $true
        ComWarning = $comWarning
    }
}

function Install-BrightSlidePowerPointAddIn {
    $targetPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\AddIns\BrightCarbon\BrightSlide\BrightSlide.ppam'
    if (-not (Test-Path -LiteralPath $targetPath)) {
        $downloadRoot = Get-OfficeTypesettingDownloadRoot
        $installerPath = Join-Path $downloadRoot 'Setup_BrightSlide_1.1.1.exe'
        Invoke-WebRequest -Uri 'https://brightcarbon.com/assets/BrightSlide/Windows/Setup_BrightSlide_1.1.1.exe?v=1' -OutFile $installerPath -Headers @{ 'User-Agent' = 'Codex-Windows-Toolkit' }
        Unblock-File -LiteralPath $installerPath -ErrorAction SilentlyContinue
        $installerExitCode = Invoke-OfficeTypesettingProcess -FilePath $installerPath -ArgumentList @('/VERYSILENT', '/NORESTART', '/SP-')
        if ($installerExitCode -ne 0 -and -not (Test-Path -LiteralPath $targetPath)) {
            Write-Warning ("BrightSlide installer returned {0} and the add-in was not detected at {1}." -f $installerExitCode, $targetPath)
            return
        }
    }

    if (Test-Path -LiteralPath $targetPath) {
        try {
            $registration = Register-PowerPointAddInForAutoLoad -AddInPath $targetPath
            if ($registration.ComWarning) {
                Write-Note ("BrightSlide registry fallback is active; PowerPoint COM warm-up still reported: {0}" -f $registration.ComWarning)
            }
            Write-Note ("BrightSlide registered for PowerPoint auto-load at {0}" -f $targetPath)
        } catch {
            Write-Warning ("BrightSlide was installed but PowerPoint auto-load registration was skipped: {0}" -f $_.Exception.Message)
        }
    }
}

function Install-InstrumentaPowerPointAddIn {
    $targetPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\AddIns\InstrumentaPowerpointToolbar.ppam'
    if (-not (Test-Path -LiteralPath $targetPath)) {
        $downloadRoot = Get-OfficeTypesettingDownloadRoot
        $downloadPath = Join-Path $downloadRoot 'InstrumentaPowerpointToolbar.ppam'
        Invoke-WebRequest -Uri 'https://github.com/iappyx/Instrumenta/releases/download/1.66/InstrumentaPowerpointToolbar.ppam' -OutFile $downloadPath -Headers @{ 'User-Agent' = 'Codex-Windows-Toolkit' }
        Unblock-File -LiteralPath $downloadPath -ErrorAction SilentlyContinue
        Copy-OfficeFileWithLockTolerance -SourcePath $downloadPath -DestinationPath $targetPath -DisplayName 'Instrumenta add-in'
    }

    try {
        $registration = Register-PowerPointAddInForAutoLoad -AddInPath $targetPath
        if ($registration.ComWarning) {
            Write-Note ("Instrumenta registry fallback is active; PowerPoint COM warm-up still reported: {0}" -f $registration.ComWarning)
        }
        Write-Note ("Instrumenta registered for PowerPoint auto-load at {0}" -f $targetPath)
    } catch {
        Write-Warning ("Instrumenta was copied, but PowerPoint auto-load registration was skipped: {0}" -f $_.Exception.Message)
    }
}

function Install-ThorPowerPointAddIn {
    $targetPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\AddIns\PPTools\THOR\THOR.PPAM'
    if (-not (Test-Path -LiteralPath $targetPath)) {
        $downloadRoot = Get-OfficeTypesettingDownloadRoot
        $msiPath = Join-Path $downloadRoot 'THOR_Setup.msi'
        Invoke-WebRequest -Uri 'https://www.pptools.com/free/THOR_Setup.msi' -OutFile $msiPath -Headers @{ 'User-Agent' = 'Codex-Windows-Toolkit' }
        $msiExitCode = Invoke-OfficeTypesettingProcess -FilePath 'msiexec.exe' -ArgumentList @('/i', $msiPath, '/qn', '/norestart')
        if ($msiExitCode -ne 0 -and -not (Test-Path -LiteralPath $targetPath)) {
            Write-Warning ("THOR MSI returned {0} and the add-in was not detected at {1}." -f $msiExitCode, $targetPath)
            return
        }
    }

    if (Test-Path -LiteralPath $targetPath) {
        try {
            $registration = Register-PowerPointAddInForAutoLoad -AddInPath $targetPath
            if ($registration.ComWarning) {
                Write-Note ("THOR registry fallback is active; PowerPoint COM warm-up still reported: {0}" -f $registration.ComWarning)
            }
            Write-Note ("THOR registered for PowerPoint auto-load at {0}" -f $targetPath)
        } catch {
            Write-Warning ("THOR was installed but PowerPoint auto-load registration was skipped: {0}" -f $_.Exception.Message)
        }
    }
}

function Install-PowerUpKitPowerPointAddIn {
    $addInRoot = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\AddIns'
    Ensure-Directory -Path $addInRoot
    $targetPath = Join-Path $addInRoot 'PowerUpKit_v1_9_2.ppam'
    $officeExamplesRoot = Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\OfficeTypesettingTools') 'examples\powerupkit'
    Ensure-Directory -Path $officeExamplesRoot

    if (-not (Test-Path -LiteralPath $targetPath)) {
        $downloadRoot = Get-OfficeTypesettingDownloadRoot
        $zipPath = Join-Path $downloadRoot 'PowerUpKit_latest.zip'
        $extractRoot = Join-Path $downloadRoot 'PowerUpKit_latest'
        Invoke-WebRequest -Uri 'https://powerupkit.com//public/download/PowerUpKit_v1.9.2.zip' -OutFile $zipPath -Headers @{ 'User-Agent' = 'Codex-Windows-Toolkit' }
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force
        }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
        $ppam = Get-ChildItem -LiteralPath $extractRoot -Recurse -File -Filter '*.ppam' | Select-Object -First 1
        if ($null -eq $ppam) {
            Write-Warning 'Power Up Kit archive was downloaded, but no .ppam file was found inside it.'
            return
        }

        Copy-OfficeFileWithLockTolerance -SourcePath $ppam.FullName -DestinationPath $targetPath -DisplayName 'Power Up Kit add-in'
        Unblock-File -LiteralPath $targetPath -ErrorAction SilentlyContinue

        $favoriteDeck = Get-ChildItem -LiteralPath $extractRoot -Recurse -File | Where-Object { $_.Name -like '*Favorite*.pptx' } | Select-Object -First 1
        if ($null -ne $favoriteDeck) {
            Copy-Item -LiteralPath $favoriteDeck.FullName -Destination (Join-Path $officeExamplesRoot $favoriteDeck.Name) -Force
        }
    }

    if (Test-Path -LiteralPath $targetPath) {
        try {
            $registration = Register-PowerPointAddInForAutoLoad -AddInPath $targetPath
            if ($registration.ComWarning) {
                Write-Note ("Power Up Kit registry fallback is active; PowerPoint COM warm-up still reported: {0}" -f $registration.ComWarning)
            }
            Write-Note ("Power Up Kit registered for PowerPoint auto-load at {0}" -f $targetPath)
        } catch {
            Write-Warning ("Power Up Kit was installed but PowerPoint auto-load registration was skipped: {0}" -f $_.Exception.Message)
        }
    }
}

function Install-IguanaTexPowerPointAddIn {
    if ($SkipPowerPointAddIn) {
        Write-Note 'Skipping IguanaTex PowerPoint add-in by request.'
        return
    }

    $downloadRoot = Get-OfficeTypesettingDownloadRoot
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Jonathan-LeRoux/IguanaTex/releases/latest' -Headers @{ 'User-Agent' = 'Codex-Windows-Toolkit' }
    $ppamAsset = $release.assets | Where-Object { $_.name -like '*.ppam' } | Select-Object -First 1
    if ($null -eq $ppamAsset) {
        throw 'Could not find an IguanaTex .ppam asset in the latest release.'
    }

    $downloadPath = Join-Path $downloadRoot $ppamAsset.name
    Invoke-WebRequest -Uri $ppamAsset.browser_download_url -OutFile $downloadPath -Headers @{ 'User-Agent' = 'Codex-Windows-Toolkit' }
    Unblock-File -LiteralPath $downloadPath -ErrorAction SilentlyContinue

    $addInRoot = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\AddIns'
    Ensure-Directory -Path $addInRoot
    $installedPath = Join-Path $addInRoot $ppamAsset.name
    Copy-OfficeFileWithLockTolerance -SourcePath $downloadPath -DestinationPath $installedPath -DisplayName 'IguanaTex add-in'
    Unblock-File -LiteralPath $installedPath -ErrorAction SilentlyContinue

    $trustedLocation = 'HKCU:\Software\Microsoft\Office\16.0\PowerPoint\Security\Trusted Locations\Location99'
    New-Item -Path $trustedLocation -Force | Out-Null
    New-ItemProperty -Path $trustedLocation -Name Path -Value ($addInRoot + '\') -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $trustedLocation -Name AllowSubfolders -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $trustedLocation -Name Description -Value 'Codex Office typesetting add-ins' -PropertyType String -Force | Out-Null

    try {
        $registration = Register-PowerPointAddInForAutoLoad -AddInPath $installedPath
        if ($registration.ComWarning) {
            Write-Note ("IguanaTex registry fallback is active; PowerPoint COM warm-up still reported: {0}" -f $registration.ComWarning)
        }
    } catch {
        Write-Warning ("IguanaTex was copied and trusted, but durable PowerPoint auto-load registration was skipped: {0}" -f $_.Exception.Message)
    }
    Write-Note ("IguanaTex installed at {0}" -f $installedPath)
}

function Install-LibreOfficeLatexExtensions {
    if ($SkipLibreOfficeExtensions) {
        Write-Note 'Skipping LibreOffice LaTeX extensions by request.'
        return
    }

    $suppressMarker = Get-LibreOfficeExtensionSuppressMarker
    if (Test-Path -LiteralPath $suppressMarker) {
        Write-Warning ("Skipping LibreOffice extension registration because a previous unopkg failure was recorded at {0}. Remove that file if you want to retry." -f $suppressMarker)
        return
    }

    if (Test-LibreOfficeExtensionInstalled -ExtensionLeafName 'TexMaths.oxt') {
        Write-Note 'TexMaths is already detectable in the LibreOffice user profile; skipping repeated extension registration.'
        return
    }

    $unopkg = Find-CommandPath -Name 'unopkg'
    $unopkgCandidates = @(
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'LibreOffice\program\unopkg.com'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'LibreOffice\program\unopkg.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'LibreOffice\program\unopkg.com'),
        (Join-Path ${env:ProgramFiles(x86)} 'LibreOffice\program\unopkg.exe')
    )
    if ([string]::IsNullOrWhiteSpace($unopkg)) {
        foreach ($candidate in $unopkgCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
                $unopkg = $candidate
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($unopkg)) {
        Write-Warning 'LibreOffice unopkg was not found; skipping TexMaths and Writer2LaTeX extension registration.'
        return
    }

    $downloadRoot = Get-OfficeTypesettingDownloadRoot
    $texMathsPath = Join-Path $downloadRoot 'TexMaths.oxt'
    Invoke-WebRequest -Uri 'https://sourceforge.net/projects/texmaths/files/latest/download' -OutFile $texMathsPath -UserAgent 'Codex-Windows-Toolkit'
    Unblock-File -LiteralPath $texMathsPath -ErrorAction SilentlyContinue
    $texMathsExitCode = Invoke-OfficeTypesettingProcess -FilePath $unopkg -ArgumentList @('add', '--force', $texMathsPath)
    if ($texMathsExitCode -ne 0) {
        if (Test-LibreOfficeExtensionInstalled -ExtensionLeafName 'TexMaths.oxt') {
            Write-Warning 'unopkg returned a non-zero exit code for TexMaths, but the extension is now detectable. Continuing.'
        } else {
            Set-Content -LiteralPath $suppressMarker -Value ("TexMaths install failed via unopkg at {0}" -f (Get-Date).ToString('s')) -Encoding UTF8
            Write-Warning ("unopkg failed while installing TexMaths. Future runs will skip LibreOffice extension registration until you remove {0}." -f $suppressMarker)
            return
        }
    }

    $writerZip = Join-Path $downloadRoot 'writer2latex161.zip'
    $writerExtractRoot = Join-Path $downloadRoot 'writer2latex161'
    Invoke-WebRequest -Uri 'https://downloads.sourceforge.net/project/writer2latex/writer2latex/Writer2LaTeX%201.6/writer2latex161.zip' -OutFile $writerZip -UserAgent 'Codex-Windows-Toolkit'
    if (Test-Path -LiteralPath $writerExtractRoot) {
        Remove-Item -LiteralPath $writerExtractRoot -Recurse -Force
    }
    Expand-Archive -LiteralPath $writerZip -DestinationPath $writerExtractRoot -Force
    $writerRoot = Join-Path $writerExtractRoot 'writer2latex16'

    foreach ($extension in @('writer2latex.oxt', 'w2lconfig.oxt')) {
        $extensionPath = Join-Path $writerRoot $extension
        if (Test-Path -LiteralPath $extensionPath) {
            $writerExitCode = Invoke-OfficeTypesettingProcess -FilePath $unopkg -ArgumentList @('add', '--force', $extensionPath)
            if ($writerExitCode -ne 0) {
                if (Test-LibreOfficeExtensionInstalled -ExtensionLeafName $extension) {
                    Write-Warning ("unopkg returned a non-zero exit code for {0}, but the extension is now detectable. Continuing." -f $extension)
                } else {
                    Write-Warning ("unopkg failed while installing {0}; continuing because Writer2LaTeX support is optional for the main PPT / textbook workflow." -f $extension)
                }
            }
        }
    }

    Write-Note 'TexMaths and Writer2LaTeX LibreOffice extensions are registered.'
}

function Initialize-MiKTeXForOfficeTypesetting {
    if (Test-CommandAvailable -Name 'initexmf') {
        try {
            initexmf --set-config-value='[MPM]AutoInstall=1' | Out-Null
        } catch {
            Write-Warning ("MiKTeX initexmf auto-install configuration was skipped: {0}" -f $_.Exception.Message)
        }
    }

    if (Test-CommandAvailable -Name 'miktex') {
        try {
            miktex packages update | Out-Null
            miktex packages check-update | Out-Null
        } catch {
            Write-Warning ("MiKTeX package refresh was skipped: {0}" -f $_.Exception.Message)
        }
    }
}

Write-Section 'Installing Office typesetting tools'

if (-not (Test-CommandAvailable -Name 'winget')) {
    throw 'winget is not available in PATH. Install App Installer / winget first, then rerun the toolkit installer.'
}

foreach ($package in $script:Manifest.OfficeTypesettingWingetPackages) {
    Invoke-OfficeTypesettingWingetInstall -Package $package
    Sync-OfficeTypesettingProcessPath
}

Sync-OfficeTypesettingProcessPath
Install-OfficeTypesettingNpmPackages
Initialize-MiKTeXForOfficeTypesetting
Install-IguanaTexPowerPointAddIn
Install-BrightSlidePowerPointAddIn
Install-InstrumentaPowerPointAddIn
Install-ThorPowerPointAddIn
Install-PowerUpKitPowerPointAddIn
Install-LibreOfficeLatexExtensions

Write-Host 'Office typesetting tool pass completed.' -ForegroundColor Green
