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
    $pathParts = @($userPath, $machinePath, $env:Path) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $env:Path = [string]::Join(';', $pathParts)
}

function Register-PowerPointAddInForAutoLoad {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AddInPath
    )

    $ppt = $null
    $addin = $null
    $createdInstance = $false

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

        $ppt.Visible = -1
        foreach ($candidate in @($ppt.AddIns)) {
            if ($candidate.FullName -eq $AddInPath -or $candidate.Name -like 'IguanaTex*') {
                $addin = $candidate
                break
            }
        }

        if ($null -eq $addin) {
            $addin = $ppt.AddIns.Add($AddInPath)
        }

        # AutoLoad is the durable setting: it also marks the add-in as registered.
        $addin.AutoLoad = -1
        $addin.Loaded = -1
    } finally {
        if ($null -ne $addin) {
            [Runtime.InteropServices.Marshal]::ReleaseComObject($addin) | Out-Null
        }

        if ($null -ne $ppt) {
            if ($createdInstance) {
                $ppt.Quit()
            }

            [Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) | Out-Null
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
    Copy-Item -LiteralPath $downloadPath -Destination $installedPath -Force
    Unblock-File -LiteralPath $installedPath -ErrorAction SilentlyContinue

    $trustedLocation = 'HKCU:\Software\Microsoft\Office\16.0\PowerPoint\Security\Trusted Locations\Location99'
    New-Item -Path $trustedLocation -Force | Out-Null
    New-ItemProperty -Path $trustedLocation -Name Path -Value ($addInRoot + '\') -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $trustedLocation -Name AllowSubfolders -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $trustedLocation -Name Description -Value 'Codex Office typesetting add-ins' -PropertyType String -Force | Out-Null

    try {
        Register-PowerPointAddInForAutoLoad -AddInPath $installedPath
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
Install-LibreOfficeLatexExtensions

Write-Host 'Office typesetting tool pass completed.' -ForegroundColor Green
