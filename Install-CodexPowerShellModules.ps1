[CmdletBinding()]
param()

. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'common.ps1')

if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
    throw 'Install-Module is not available. Update PowerShellGet / PackageManagement and rerun the toolkit installer.'
}

Write-Section 'Installing PowerShell modules'

try {
    $gallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
    if ($null -ne $gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    }
} catch {
    Write-Warning ("Unable to set PSGallery trust policy automatically: {0}" -f $_.Exception.Message)
}

try {
    if (-not (Get-PackageProvider -Name 'NuGet' -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name 'NuGet' -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force | Out-Null
    }
} catch {
    Write-Warning ("NuGet provider bootstrap was skipped: {0}" -f $_.Exception.Message)
}

foreach ($module in $script:Manifest.PowerShellModules) {
    $state = Get-PowerShellModuleState -Module $module
    if ($state.Installed) {
        Write-Note ("Skipping {0}; already installed ({1})." -f $module.DisplayName, $state.Detail)
        continue
    }

    Write-Host ("Installing PowerShell module {0}" -f $module.DisplayName) -ForegroundColor Yellow
    $installParameters = @{
        Name = $module.Name
        Scope = 'CurrentUser'
        Repository = 'PSGallery'
        Force = $true
        AllowClobber = $true
    }

    if ((Get-Command Install-Module).Parameters.ContainsKey('AcceptLicense')) {
        $installParameters.AcceptLicense = $true
    }

    Install-Module @installParameters
}

Write-Host 'PowerShell module pass completed.' -ForegroundColor Green
