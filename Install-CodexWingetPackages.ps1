[CmdletBinding()]
param(
    [string]$InstallScope = 'Auto',
    [switch]$IncludeOptionalPackages
)

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'common.ps1')

if (-not (Test-CommandAvailable -Name 'winget')) {
    throw 'winget is not available in PATH. Install App Installer / winget first, then rerun the toolkit installer.'
}

$resolvedScope = Resolve-PreferredInstallScope -InstallScope $InstallScope

Write-Section "Installing winget packages ($resolvedScope scope)"

$packages = @($script:Manifest.WingetPackages)
if ($IncludeOptionalPackages) {
    $packages += $script:Manifest.OptionalWingetPackages
}

foreach ($package in $packages) {
    $state = Get-PackageState -Package $package
    if ($state.Installed) {
        Write-Note ("Skipping {0}; already installed." -f $package.DisplayName)
        continue
    }

    Write-Host ("Installing {0} ({1})" -f $package.DisplayName, $package.Id) -ForegroundColor Yellow
    $arguments = @(
        'install',
        '-e',
        '--id', $package.Id,
        '--source', 'winget',
        '--disable-interactivity',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--scope', $resolvedScope
    )

    & winget @arguments
    if ($LASTEXITCODE -ne 0) {
        $postInstallState = Get-PackageState -Package $package
        if ($postInstallState.Installed) {
            Write-Warning ("winget returned a non-zero exit code for {0}, but the package is now detectable. Continuing." -f $package.DisplayName)
            continue
        }

        throw "winget failed while installing $($package.Id)."
    }
}

Write-Host 'Winget package pass completed.' -ForegroundColor Green
