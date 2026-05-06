${existingCodexPowerPointToolsLoaded} = Get-Variable -Name CodexPowerPointToolsLoaded -Scope Global -ErrorAction SilentlyContinue
if ($null -ne ${existingCodexPowerPointToolsLoaded} -and ${existingCodexPowerPointToolsLoaded}.Value) {
    return
}

$global:CodexPowerPointToolsLoaded = $true

function Ensure-PptDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Release-CodexComObject {
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

function Get-CodexPowerPointToolkitRoot {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Toolkit'
}

function Get-CodexPowerPointStateRoot {
    $root = Join-Path (Get-CodexPowerPointToolkitRoot) 'state\powerpoint'
    Ensure-PptDirectory -Path $root
    return $root
}

function Get-CodexPowerPointAddInRoot {
    $root = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\AddIns'
    Ensure-PptDirectory -Path $root
    return $root
}

function Get-CodexPowerPointRegistryVersion {
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

function Get-CodexPowerPointAddInRegistryRoot {
    $version = Get-CodexPowerPointRegistryVersion
    return "HKCU:\Software\Microsoft\Office\$version\PowerPoint\AddIns"
}

function Get-CodexPowerPointAddInLoadTimesPath {
    $version = Get-CodexPowerPointRegistryVersion
    return "HKCU:\Software\Microsoft\Office\$version\PowerPoint\AddInLoadTimes"
}

function Set-CodexPowerPointAddInRegistryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AddInPath
    )

    $resolvedAddInPath = Resolve-CodexPresentationPath -Path $AddInPath
    $addInName = [IO.Path]::GetFileNameWithoutExtension($resolvedAddInPath)
    $registryRoot = Get-CodexPowerPointAddInRegistryRoot
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

    $loadTimesPath = Get-CodexPowerPointAddInLoadTimesPath
    if (Test-Path -LiteralPath $loadTimesPath) {
        Remove-ItemProperty -LiteralPath $loadTimesPath -Name $resolvedAddInPath -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $loadTimesPath -Name ([IO.Path]::GetFileName($resolvedAddInPath)) -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Name = $addInName
        RegistryPath = $entryPath
        Path = $resolvedAddInPath
        AutoLoad = $true
    }
}

function Get-CodexPowerPointRegistryAddInRows {
    $registryRoot = Get-CodexPowerPointAddInRegistryRoot
    if (-not (Test-Path -LiteralPath $registryRoot)) {
        return @()
    }

    $rows = foreach ($entry in Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue) {
        $values = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $values) {
            continue
        }

        $pathValue = [string]$values.Path
        [pscustomobject]@{
            Name = $entry.PSChildName
            FullName = $pathValue
            Path = $pathValue
            Loaded = $null
            AutoLoad = $values.AutoLoad
            Registered = $true
            Source = 'Registry'
        }
    }

    return @($rows)
}

function Get-CodexPowerPointExamplesRoot {
    $root = Join-Path (Get-CodexPowerPointToolkitRoot) 'examples\powerpoint-addins'
    Ensure-PptDirectory -Path $root
    return $root
}

function Expand-CodexPowerPointAddInPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackagePath
    )

    $resolvedPackagePath = Resolve-CodexPresentationPath -Path $PackagePath
    $packageName = [IO.Path]::GetFileNameWithoutExtension($resolvedPackagePath)
    $extractRoot = Join-Path (Get-CodexPowerPointStateRoot) ("addin-package-{0}-{1}" -f $packageName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Ensure-PptDirectory -Path $extractRoot
    Expand-Archive -LiteralPath $resolvedPackagePath -DestinationPath $extractRoot -Force

    $addInFile = Get-ChildItem -LiteralPath $extractRoot -Recurse -File | Where-Object { $_.Extension -in @('.ppam', '.ppa', '.pptm') } | Select-Object -First 1
    if ($null -eq $addInFile) {
        throw "No PowerPoint add-in file was found inside package: $resolvedPackagePath"
    }

    $supportRoot = Join-Path (Get-CodexPowerPointExamplesRoot) $packageName
    Ensure-PptDirectory -Path $supportRoot
    foreach ($supportFile in Get-ChildItem -LiteralPath $extractRoot -Recurse -File | Where-Object { $_.FullName -ne $addInFile.FullName }) {
        Copy-Item -LiteralPath $supportFile.FullName -Destination (Join-Path $supportRoot $supportFile.Name) -Force
    }

    return [pscustomobject]@{
        AddInPath = $addInFile.FullName
        SupportRoot = $supportRoot
    }
}

function ConvertTo-OfficeRgb {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Color
    )

    $hex = $Color.Trim()
    if ($hex.StartsWith('#')) {
        $hex = $hex.Substring(1)
    }

    if ($hex.Length -eq 3) {
        $hex = ($hex.ToCharArray() | ForEach-Object { "$_$_" }) -join ''
    }

    if ($hex -notmatch '^[0-9A-Fa-f]{6}$') {
        throw "Unsupported color format: $Color"
    }

    $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
    return ($r + (256 * $g) + (65536 * $b))
}

function ConvertTo-PptPoints {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Value,

        [ValidateSet('pt', 'in', 'cm')]
        [string]$Unit = 'pt'
    )

    switch ($Unit) {
        'in' { return ($Value * 72.0) }
        'cm' { return ($Value / 2.54 * 72.0) }
        default { return $Value }
    }
}

function Resolve-CodexPresentationPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }

    return [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Get-PptSlideLayoutValue {
    param(
        [string]$Layout = 'blank'
    )

    switch ($Layout.ToLowerInvariant()) {
        'title' { return 1 }
        'text' { return 2 }
        'section' { return 33 }
        'title-only' { return 11 }
        default { return 12 }
    }
}

function Get-PptShapeTypeValue {
    param(
        [string]$ShapeType = 'rectangle'
    )

    switch ($ShapeType.ToLowerInvariant()) {
        'rectangle' { return 1 }
        'parallelogram' { return 2 }
        'trapezoid' { return 3 }
        'diamond' { return 4 }
        'roundedrect' { return 5 }
        'roundrect' { return 5 }
        'oval' { return 9 }
        'hexagon' { return 10 }
        'chevron' { return 52 }
        'pentagon' { return 51 }
        'righttriangle' { return 8 }
        'triangle' { return 8 }
        'isoscelestriangle' { return 7 }
        'arrow' { return 13 }
        'leftarrow' { return 34 }
        'rightarrow' { return 33 }
        'uparrow' { return 35 }
        'downarrow' { return 36 }
        'line' { return 1 }
        default { return 1 }
    }
}

function New-CodexPowerPointApplication {
    param(
        [switch]$Visible
    )

    $ppt = $null
    $createdInstance = $false

    try {
        $ppt = [Runtime.InteropServices.Marshal]::GetActiveObject('PowerPoint.Application')
    } catch {
        $ppt = $null
    }

    if ($null -eq $ppt) {
        $ppt = New-Object -ComObject PowerPoint.Application
        $createdInstance = $true
    }

    if ($Visible) {
        try {
            Invoke-CodexPowerPointComAction -Action { $ppt.Visible = -1 } | Out-Null
        } catch {
        }
    }

    return [pscustomobject]@{
        Application = $ppt
        CreatedInstance = $createdInstance
    }
}

function Open-CodexPresentation {
    param(
        [Parameter(Mandatory = $true)]
        $Application,

        [string]$Path,

        [switch]$CreateIfMissing,

        [string]$Layout = 'blank'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($Application.Presentations.Count -gt 0) {
            return [pscustomobject]@{
                Presentation = $Application.ActivePresentation
                CreatedPresentation = $false
                ResolvedPath = $null
            }
        }

        if (-not $CreateIfMissing) {
            throw 'No active PowerPoint presentation is available.'
        }

        $presentation = $Application.Presentations.Add()
        $slide = $presentation.Slides.Add(1, (Get-PptSlideLayoutValue -Layout $Layout))
        while ($presentation.Slides.Count -gt 1) {
            $presentation.Slides($presentation.Slides.Count).Delete()
        }

        return [pscustomobject]@{
            Presentation = $presentation
            CreatedPresentation = $true
            ResolvedPath = $null
        }
    }

    $resolvedPath = Resolve-CodexPresentationPath -Path $Path
    $directory = Split-Path -Parent $resolvedPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        Ensure-PptDirectory -Path $directory
    }

    if (Test-Path -LiteralPath $resolvedPath) {
        $presentation = $Application.Presentations.Open($resolvedPath, $false, $false, $false)
        return [pscustomobject]@{
            Presentation = $presentation
            CreatedPresentation = $false
            ResolvedPath = $resolvedPath
        }
    }

    if (-not $CreateIfMissing) {
        throw "PowerPoint file was not found: $resolvedPath"
    }

    $presentation = $Application.Presentations.Add()
    $slide = $presentation.Slides.Add(1, (Get-PptSlideLayoutValue -Layout $Layout))
    while ($presentation.Slides.Count -gt 1) {
        $presentation.Slides($presentation.Slides.Count).Delete()
    }
    $presentation.SaveAs($resolvedPath)

    return [pscustomobject]@{
        Presentation = $presentation
        CreatedPresentation = $true
        ResolvedPath = $resolvedPath
    }
}

function Invoke-CodexPowerPointPresentation {
    param(
        [string]$Path,
        [switch]$CreateIfMissing,
        [switch]$Visible,
        [string]$Layout = 'blank',
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    $session = New-CodexPowerPointApplication -Visible:$Visible
    $ppt = $session.Application
    $opened = $null

    try {
        $opened = Open-CodexPresentation -Application $ppt -Path $Path -CreateIfMissing:$CreateIfMissing -Layout $Layout
        $result = & $Action $ppt $opened.Presentation $opened.ResolvedPath

        if (-not [string]::IsNullOrWhiteSpace($opened.ResolvedPath)) {
            $opened.Presentation.Save()
        }

        return $result
    } finally {
        if ($null -ne $opened -and $null -ne $opened.Presentation) {
            try {
                $opened.Presentation.Close()
            } catch {
            }
            [Runtime.InteropServices.Marshal]::ReleaseComObject($opened.Presentation) | Out-Null
        }

        if ($null -ne $ppt) {
            if ($session.CreatedInstance) {
                try {
                    $ppt.Quit()
                } catch {
                }
            }
            [Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) | Out-Null
        }

        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

function Get-CodexPowerPointSlide {
    param(
        [Parameter(Mandatory = $true)]
        $Presentation,

        [int]$SlideIndex = 1
    )

    if ($SlideIndex -lt 1 -or $SlideIndex -gt $Presentation.Slides.Count) {
        throw "Slide index $SlideIndex is out of range."
    }

    return $Presentation.Slides.Item($SlideIndex)
}

function Get-CodexShapeByReference {
    param(
        [Parameter(Mandatory = $true)]
        $Slide,

        [string]$ShapeName,

        [int]$ShapeIndex
    )

    if (-not [string]::IsNullOrWhiteSpace($ShapeName)) {
        foreach ($shape in @($Slide.Shapes)) {
            if ($shape.Name -eq $ShapeName) {
                return $shape
            }
        }

        throw "Could not find a shape named '$ShapeName' on slide $($Slide.SlideIndex)."
    }

    if ($ShapeIndex -gt 0) {
        if ($ShapeIndex -gt $Slide.Shapes.Count) {
            throw "Shape index $ShapeIndex is out of range on slide $($Slide.SlideIndex)."
        }

        return $Slide.Shapes.Item($ShapeIndex)
    }

    throw 'Specify either -ShapeName or -ShapeIndex.'
}

function Set-CodexShapeStyle {
    param(
        [Parameter(Mandatory = $true)]
        $Shape,

        [string]$FillColor,

        [string]$FillColor2,

        [switch]$Gradient,

        [double]$Transparency = -1,

        [string]$LineColor,

        [double]$LineWeight = -1,

        [string]$FontColor,

        [string]$FontName,

        [double]$FontSize = -1,

        [Nullable[bool]]$Bold = $null,

        [double]$Rotation = [double]::NaN,

        [switch]$Shadow,

        [string]$GlowColor,

        [double]$GlowRadius = -1
    )

    if (-not [string]::IsNullOrWhiteSpace($FillColor)) {
        $Shape.Fill.Visible = -1
        $Shape.Fill.ForeColor.RGB = (ConvertTo-OfficeRgb -Color $FillColor)
        if ($Gradient -and -not [string]::IsNullOrWhiteSpace($FillColor2)) {
            $Shape.Fill.TwoColorGradient(1, 1)
            $Shape.Fill.ForeColor.RGB = (ConvertTo-OfficeRgb -Color $FillColor)
            $Shape.Fill.BackColor.RGB = (ConvertTo-OfficeRgb -Color $FillColor2)
        } else {
            $Shape.Fill.Solid()
        }
    }

    if ($Transparency -ge 0) {
        $Shape.Fill.Transparency = [Math]::Min([Math]::Max($Transparency, 0), 1)
    }

    if (-not [string]::IsNullOrWhiteSpace($LineColor)) {
        $Shape.Line.Visible = -1
        $Shape.Line.ForeColor.RGB = (ConvertTo-OfficeRgb -Color $LineColor)
    }

    if ($LineWeight -ge 0) {
        $Shape.Line.Weight = $LineWeight
    }

    if (-not [double]::IsNaN($Rotation)) {
        $Shape.Rotation = $Rotation
    }

    if ($Shadow) {
        $Shape.Shadow.Visible = -1
    }

    if (-not [string]::IsNullOrWhiteSpace($GlowColor)) {
        $Shape.Glow.Color.RGB = (ConvertTo-OfficeRgb -Color $GlowColor)
    }

    if ($GlowRadius -ge 0) {
        $Shape.Glow.Radius = $GlowRadius
    }

    if ($Shape.HasTextFrame -and $Shape.TextFrame.HasText) {
        $textRange = $Shape.TextFrame.TextRange
        if (-not [string]::IsNullOrWhiteSpace($FontColor)) {
            $textRange.Font.Color.RGB = (ConvertTo-OfficeRgb -Color $FontColor)
        }

        if (-not [string]::IsNullOrWhiteSpace($FontName)) {
            $textRange.Font.Name = $FontName
        }

        if ($FontSize -ge 0) {
            $textRange.Font.Size = $FontSize
        }

        if ($null -ne $Bold) {
            $textRange.Font.Bold = if ($Bold) { -1 } else { 0 }
        }
    }
}

function Get-CodexShapeIds {
    param(
        [Parameter(Mandatory = $true)]
        $Slide,

        [string[]]$ShapeName = @(),

        [int[]]$ShapeIndex = @()
    )

    $ids = New-Object System.Collections.Generic.List[object]
    foreach ($name in $ShapeName) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $shape = Get-CodexShapeByReference -Slide $Slide -ShapeName $name
        [void]$ids.Add($shape.Name)
    }

    foreach ($index in $ShapeIndex) {
        if ($index -le 0) {
            continue
        }

        $shape = Get-CodexShapeByReference -Slide $Slide -ShapeIndex $index
        [void]$ids.Add($shape.Name)
    }

    return @($ids.ToArray())
}

function Get-CodexNullableBoolValue {
    param(
        [bool]$Value,
        [bool]$IsBound
    )

    if ($IsBound) {
        return [Nullable[bool]]$Value
    }

    return [Nullable[bool]]$null
}

function Test-CodexPowerPointRetryableComException {
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception
    )

    if ($Exception.Message -match 'RPC_E_CALL_REJECTED|Call was rejected by callee|The message filter indicated that the application is busy') {
        return $true
    }

    return $Exception.HResult -in @(-2147418111, -2147417846)
}

function Invoke-CodexPowerPointComAction {
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
            if ($attempt -ge $RetryCount -or -not (Test-CodexPowerPointRetryableComException -Exception $_.Exception)) {
                throw
            }

            Start-Sleep -Milliseconds ($RetryDelayMilliseconds * $attempt)
        }
    }
}

function Close-CodexPowerPointApplication {
    param(
        [Parameter(Mandatory = $true)]
        $Application,

        [switch]$Quit
    )

    if ($Quit) {
        try {
            Invoke-CodexPowerPointComAction -Action { $Application.Quit() } | Out-Null
        } catch {
        }
    }

    Release-CodexComObject -Object $Application
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}

function Register-CodexPowerPointAddIn {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AddInPath
    )

    $resolvedAddInPath = Resolve-CodexPresentationPath -Path $AddInPath
    if (-not (Test-Path -LiteralPath $resolvedAddInPath)) {
        throw "PowerPoint add-in was not found: $resolvedAddInPath"
    }

    $registryRegistration = Set-CodexPowerPointAddInRegistryEntry -AddInPath $resolvedAddInPath

    $session = New-CodexPowerPointApplication -Visible
    $ppt = $session.Application
    try {
        Invoke-CodexPowerPointComAction -Action { $ppt.Visible = -1 } | Out-Null
    } catch {
    }
    $addin = $null
    $addIns = $null
    $comWarning = $null

    try {
        try {
            $addIns = Invoke-CodexPowerPointComAction -Action { $ppt.AddIns }
            if ($null -eq $addIns) {
                throw 'PowerPoint AddIns collection was unavailable.'
            }

            $addInCount = Invoke-CodexPowerPointComAction -Action { $addIns.Count }
            for ($index = 1; $index -le $addInCount; $index++) {
                $candidate = Invoke-CodexPowerPointComAction -Action { $addIns.Item($index) }
                try {
                    if ($null -ne $candidate -and $candidate.FullName -and $candidate.FullName.Equals($resolvedAddInPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $addin = $candidate
                        break
                    }
                } finally {
                    if ($null -ne $candidate -and ($null -eq $addin -or -not [object]::ReferenceEquals($candidate, $addin))) {
                        Release-CodexComObject -Object $candidate
                    }
                }
            }

            if ($null -eq $addin) {
                $addin = Invoke-CodexPowerPointComAction -Action { $addIns.Add($resolvedAddInPath) }
            }

            Invoke-CodexPowerPointComAction -Action { $addin.AutoLoad = -1 } | Out-Null
            Invoke-CodexPowerPointComAction -Action { $addin.Loaded = -1 } | Out-Null

            return [pscustomobject]@{
                Name = (Invoke-CodexPowerPointComAction -Action { $addin.Name })
                FullName = (Invoke-CodexPowerPointComAction -Action { $addin.FullName })
                Path = (Invoke-CodexPowerPointComAction -Action { $addin.FullName })
                Loaded = (Invoke-CodexPowerPointComAction -Action { $addin.Loaded })
                AutoLoad = (Invoke-CodexPowerPointComAction -Action { $addin.AutoLoad })
                Registered = (Invoke-CodexPowerPointComAction -Action { $addin.Registered })
                Source = 'PowerPoint+Registry'
            }
        } catch {
            $comWarning = $_.Exception.Message
            return [pscustomobject]@{
                Name = $registryRegistration.Name
                FullName = $resolvedAddInPath
                Path = $resolvedAddInPath
                Loaded = $null
                AutoLoad = -1
                Registered = $true
                Source = 'Registry'
                ComWarning = $comWarning
            }
        }
    } finally {
        Release-CodexComObject -Object $addin
        Release-CodexComObject -Object $addIns
        if ($null -ne $ppt) {
            Close-CodexPowerPointApplication -Application $ppt -Quit:$session.CreatedInstance
        }
    }
}

function ppt-new {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [double]$Width = 13.333,

        [double]$Height = 7.5,

        [ValidateSet('pt', 'in', 'cm')]
        [string]$Unit = 'in',

        [string]$Layout = 'blank',

        [switch]$Visible
    )

    Invoke-CodexPowerPointPresentation -Path $Path -CreateIfMissing -Visible:$Visible -Layout $Layout -Action {
        param($ppt, $pres, $resolvedPath)

        $pres.PageSetup.SlideWidth = ConvertTo-PptPoints -Value $Width -Unit $Unit
        $pres.PageSetup.SlideHeight = ConvertTo-PptPoints -Value $Height -Unit $Unit

        [pscustomobject]@{
            Path = $resolvedPath
            Slides = $pres.Slides.Count
            SlideWidth = $pres.PageSetup.SlideWidth
            SlideHeight = $pres.PageSetup.SlideHeight
        }
    }
}

function ppt-slide-size {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [double]$Width,

        [Parameter(Mandatory = $true)]
        [double]$Height,

        [ValidateSet('pt', 'in', 'cm')]
        [string]$Unit = 'in'
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        $pres.PageSetup.SlideWidth = ConvertTo-PptPoints -Value $Width -Unit $Unit
        $pres.PageSetup.SlideHeight = ConvertTo-PptPoints -Value $Height -Unit $Unit
        [pscustomobject]@{
            Path = $resolvedPath
            SlideWidth = $pres.PageSetup.SlideWidth
            SlideHeight = $pres.PageSetup.SlideHeight
        }
    }
}

function ppt-add-slide {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [string]$Layout = 'blank',

        [int]$InsertAt = 0
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        $index = if ($InsertAt -gt 0) { $InsertAt } else { $pres.Slides.Count + 1 }
        $slide = $pres.Slides.Add($index, (Get-PptSlideLayoutValue -Layout $Layout))
        [pscustomobject]@{
            Path = $resolvedPath
            SlideIndex = $slide.SlideIndex
            Layout = $Layout
        }
    }
}

function ppt-add-textbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [int]$SlideIndex = 1,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [double]$Left,
        [double]$Top,
        [double]$Width,
        [double]$Height,

        [ValidateSet('pt', 'in', 'cm')]
        [string]$Unit = 'in',

        [string]$Name,

        [string]$FontName,

        [double]$FontSize = -1,

        [string]$FontColor,

        [switch]$Bold
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        $slide = Get-CodexPowerPointSlide -Presentation $pres -SlideIndex $SlideIndex
        $shape = $slide.Shapes.AddTextbox(1,
            (ConvertTo-PptPoints -Value $Left -Unit $Unit),
            (ConvertTo-PptPoints -Value $Top -Unit $Unit),
            (ConvertTo-PptPoints -Value $Width -Unit $Unit),
            (ConvertTo-PptPoints -Value $Height -Unit $Unit))

        if (-not [string]::IsNullOrWhiteSpace($Name)) {
            $shape.Name = $Name
        }

        $shape.TextFrame.TextRange.Text = $Text
        $boldValue = Get-CodexNullableBoolValue -Value $Bold.IsPresent -IsBound $PSBoundParameters.ContainsKey('Bold')
        Set-CodexShapeStyle -Shape $shape -FontName $FontName -FontSize $FontSize -FontColor $FontColor -Bold:$boldValue

        [pscustomobject]@{
            Path = $resolvedPath
            SlideIndex = $slide.SlideIndex
            ShapeName = $shape.Name
            ShapeId = $shape.Id
        }
    }
}

function ppt-add-shape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [int]$SlideIndex = 1,

        [string]$ShapeType = 'rectangle',

        [double]$Left,
        [double]$Top,
        [double]$Width,
        [double]$Height,

        [ValidateSet('pt', 'in', 'cm')]
        [string]$Unit = 'in',

        [string]$Name,

        [string]$Text,

        [string]$FillColor,

        [string]$FillColor2,

        [switch]$Gradient,

        [string]$LineColor,

        [double]$LineWeight = -1,

        [string]$FontColor,

        [double]$FontSize = -1,

        [switch]$Bold
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        $slide = Get-CodexPowerPointSlide -Presentation $pres -SlideIndex $SlideIndex
        $shape = $slide.Shapes.AddShape(
            (Get-PptShapeTypeValue -ShapeType $ShapeType),
            (ConvertTo-PptPoints -Value $Left -Unit $Unit),
            (ConvertTo-PptPoints -Value $Top -Unit $Unit),
            (ConvertTo-PptPoints -Value $Width -Unit $Unit),
            (ConvertTo-PptPoints -Value $Height -Unit $Unit))

        if (-not [string]::IsNullOrWhiteSpace($Name)) {
            $shape.Name = $Name
        }

        if (-not [string]::IsNullOrWhiteSpace($Text)) {
            $shape.TextFrame.TextRange.Text = $Text
        }

        $boldValue = Get-CodexNullableBoolValue -Value $Bold.IsPresent -IsBound $PSBoundParameters.ContainsKey('Bold')
        Set-CodexShapeStyle -Shape $shape -FillColor $FillColor -FillColor2 $FillColor2 -Gradient:$Gradient -LineColor $LineColor -LineWeight $LineWeight -FontColor $FontColor -FontSize $FontSize -Bold:$boldValue

        [pscustomobject]@{
            Path = $resolvedPath
            SlideIndex = $slide.SlideIndex
            ShapeName = $shape.Name
            ShapeId = $shape.Id
            ShapeType = $ShapeType
        }
    }
}

function ppt-add-image {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [int]$SlideIndex = 1,

        [Parameter(Mandatory = $true)]
        [string]$ImagePath,

        [double]$Left,
        [double]$Top,
        [double]$Width,
        [double]$Height,

        [ValidateSet('pt', 'in', 'cm')]
        [string]$Unit = 'in',

        [string]$Name,

        [string]$TransparentColor
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        $slide = Get-CodexPowerPointSlide -Presentation $pres -SlideIndex $SlideIndex
        $resolvedImagePath = Resolve-CodexPresentationPath -Path $ImagePath
        if (-not (Test-Path -LiteralPath $resolvedImagePath)) {
            throw "Image file was not found: $resolvedImagePath"
        }

        $shape = $slide.Shapes.AddPicture(
            $resolvedImagePath,
            $false,
            $true,
            (ConvertTo-PptPoints -Value $Left -Unit $Unit),
            (ConvertTo-PptPoints -Value $Top -Unit $Unit),
            (ConvertTo-PptPoints -Value $Width -Unit $Unit),
            (ConvertTo-PptPoints -Value $Height -Unit $Unit))

        if (-not [string]::IsNullOrWhiteSpace($Name)) {
            $shape.Name = $Name
        }

        if (-not [string]::IsNullOrWhiteSpace($TransparentColor)) {
            $shape.PictureFormat.TransparencyColor = (ConvertTo-OfficeRgb -Color $TransparentColor)
            $shape.PictureFormat.TransparentBackground = -1
        }

        [pscustomobject]@{
            Path = $resolvedPath
            SlideIndex = $slide.SlideIndex
            ShapeName = $shape.Name
            ShapeId = $shape.Id
            ImagePath = $resolvedImagePath
        }
    }
}

function ppt-style-shape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [int]$SlideIndex = 1,

        [string]$ShapeName,

        [int]$ShapeIndex,

        [string]$FillColor,

        [string]$FillColor2,

        [switch]$Gradient,

        [double]$Transparency = -1,

        [string]$LineColor,

        [double]$LineWeight = -1,

        [string]$FontColor,

        [string]$FontName,

        [double]$FontSize = -1,

        [switch]$Bold,

        [double]$Rotation = [double]::NaN,

        [switch]$Shadow,

        [string]$GlowColor,

        [double]$GlowRadius = -1
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        $slide = Get-CodexPowerPointSlide -Presentation $pres -SlideIndex $SlideIndex
        $shape = Get-CodexShapeByReference -Slide $slide -ShapeName $ShapeName -ShapeIndex $ShapeIndex
        $boldValue = Get-CodexNullableBoolValue -Value $Bold.IsPresent -IsBound $PSBoundParameters.ContainsKey('Bold')
        Set-CodexShapeStyle -Shape $shape -FillColor $FillColor -FillColor2 $FillColor2 -Gradient:$Gradient -Transparency $Transparency -LineColor $LineColor -LineWeight $LineWeight -FontColor $FontColor -FontName $FontName -FontSize $FontSize -Bold:$boldValue -Rotation $Rotation -Shadow:$Shadow -GlowColor $GlowColor -GlowRadius $GlowRadius

        [pscustomobject]@{
            Path = $resolvedPath
            SlideIndex = $slide.SlideIndex
            ShapeName = $shape.Name
        }
    }
}

function ppt-shapes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [int]$SlideIndex = 1
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        $slide = Get-CodexPowerPointSlide -Presentation $pres -SlideIndex $SlideIndex
        foreach ($shape in @($slide.Shapes)) {
            [pscustomobject]@{
                SlideIndex = $slide.SlideIndex
                ShapeIndex = $shape.ZOrderPosition
                Name = $shape.Name
                Id = $shape.Id
                Type = $shape.Type
                Left = [Math]::Round($shape.Left, 2)
                Top = [Math]::Round($shape.Top, 2)
                Width = [Math]::Round($shape.Width, 2)
                Height = [Math]::Round($shape.Height, 2)
                HasText = [bool]($shape.HasTextFrame -and $shape.TextFrame.HasText)
            }
        }
    }
}

function ppt-arrange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [int]$SlideIndex = 1,

        [ValidateSet('align-left', 'align-center', 'align-right', 'align-top', 'align-middle', 'align-bottom', 'distribute-h', 'distribute-v', 'bring-front', 'send-back', 'group')]
        [string]$Action,

        [string[]]$ShapeName = @(),

        [int[]]$ShapeIndex = @()
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        $slide = Get-CodexPowerPointSlide -Presentation $pres -SlideIndex $SlideIndex
        $shapeIds = Get-CodexShapeIds -Slide $slide -ShapeName $ShapeName -ShapeIndex $ShapeIndex
        if ($shapeIds.Count -eq 0) {
            throw 'Specify at least one shape via -ShapeName or -ShapeIndex.'
        }

        $shapes = @()
        foreach ($id in $shapeIds) {
            $shapes += Get-CodexShapeByReference -Slide $slide -ShapeName $id
        }

        switch ($Action) {
            'align-left' {
                $target = ($shapes | Measure-Object Left -Minimum).Minimum
                foreach ($shape in $shapes) { $shape.Left = $target }
            }
            'align-center' {
                $target = (($shapes | Measure-Object { $_.Left + ($_.Width / 2) } -Average).Average)
                foreach ($shape in $shapes) { $shape.Left = $target - ($shape.Width / 2) }
            }
            'align-right' {
                $target = ($shapes | ForEach-Object { $_.Left + $_.Width } | Measure-Object -Maximum).Maximum
                foreach ($shape in $shapes) { $shape.Left = $target - $shape.Width }
            }
            'align-top' {
                $target = ($shapes | Measure-Object Top -Minimum).Minimum
                foreach ($shape in $shapes) { $shape.Top = $target }
            }
            'align-middle' {
                $target = (($shapes | Measure-Object { $_.Top + ($_.Height / 2) } -Average).Average)
                foreach ($shape in $shapes) { $shape.Top = $target - ($shape.Height / 2) }
            }
            'align-bottom' {
                $target = ($shapes | ForEach-Object { $_.Top + $_.Height } | Measure-Object -Maximum).Maximum
                foreach ($shape in $shapes) { $shape.Top = $target - $shape.Height }
            }
            'distribute-h' {
                if ($shapes.Count -lt 3) {
                    throw 'Horizontal distribution needs at least three shapes.'
                }
                $ordered = @($shapes | Sort-Object Left)
                $leftEdge = $ordered[0].Left
                $rightEdge = $ordered[-1].Left
                $totalWidth = (@($ordered | Select-Object -Skip 1 | Select-Object -SkipLast 1 | Measure-Object Width -Sum).Sum)
                $step = (($rightEdge - $leftEdge) - $totalWidth) / ($ordered.Count - 1)
                $cursor = $leftEdge
                for ($i = 1; $i -lt $ordered.Count - 1; $i++) {
                    $cursor += $step
                    $ordered[$i].Left = $cursor
                    $cursor += $ordered[$i].Width
                }
            }
            'distribute-v' {
                if ($shapes.Count -lt 3) {
                    throw 'Vertical distribution needs at least three shapes.'
                }
                $ordered = @($shapes | Sort-Object Top)
                $topEdge = $ordered[0].Top
                $bottomEdge = $ordered[-1].Top
                $totalHeight = (@($ordered | Select-Object -Skip 1 | Select-Object -SkipLast 1 | Measure-Object Height -Sum).Sum)
                $step = (($bottomEdge - $topEdge) - $totalHeight) / ($ordered.Count - 1)
                $cursor = $topEdge
                for ($i = 1; $i -lt $ordered.Count - 1; $i++) {
                    $cursor += $step
                    $ordered[$i].Top = $cursor
                    $cursor += $ordered[$i].Height
                }
            }
            'bring-front' {
                foreach ($shape in $shapes) { $shape.ZOrder(0) }
            }
            'send-back' {
                foreach ($shape in $shapes) { $shape.ZOrder(1) }
            }
            'group' {
                $range = $slide.Shapes.Range([object[]]$shapeIds)
                $grouped = $range.Group()
                return [pscustomobject]@{
                    Path = $resolvedPath
                    SlideIndex = $slide.SlideIndex
                    ShapeName = $grouped.Name
                }
            }
        }

        [pscustomobject]@{
            Path = $resolvedPath
            SlideIndex = $slide.SlideIndex
            Action = $Action
            ShapeCount = $shapes.Count
        }
    }
}

function ppt-remove-bg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [int]$SlideIndex = 1,

        [string]$ShapeName,

        [int]$ShapeIndex,

        [Parameter(Mandatory = $true)]
        [string]$TransparentColor
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        $slide = Get-CodexPowerPointSlide -Presentation $pres -SlideIndex $SlideIndex
        $shape = Get-CodexShapeByReference -Slide $slide -ShapeName $ShapeName -ShapeIndex $ShapeIndex
        $shape.PictureFormat.TransparencyColor = (ConvertTo-OfficeRgb -Color $TransparentColor)
        $shape.PictureFormat.TransparentBackground = -1

        [pscustomobject]@{
            Path = $resolvedPath
            SlideIndex = $slide.SlideIndex
            ShapeName = $shape.Name
            TransparentColor = $TransparentColor
        }
    }
}

function ppt-export {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [ValidateSet('pdf', 'png', 'jpg')]
        [string]$Format = 'pdf',

        [string]$OutputPath
    )

    Invoke-CodexPowerPointPresentation -Path $Path -Action {
        param($ppt, $pres, $resolvedPath)

        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            switch ($Format) {
                'pdf' { $OutputPath = [IO.Path]::ChangeExtension($resolvedPath, '.pdf') }
                default { $OutputPath = (Join-Path ([IO.Path]::GetDirectoryName($resolvedPath)) ([IO.Path]::GetFileNameWithoutExtension($resolvedPath) + "-$Format")) }
            }
        } else {
            $OutputPath = Resolve-CodexPresentationPath -Path $OutputPath
        }

        switch ($Format) {
            'pdf' {
                $pres.SaveAs($OutputPath, 32)
            }
            'png' {
                Ensure-PptDirectory -Path $OutputPath
                foreach ($slide in @($pres.Slides)) {
                    $target = Join-Path $OutputPath ("slide-{0:D3}.png" -f $slide.SlideIndex)
                    $slide.Export($target, 'PNG')
                }
            }
            'jpg' {
                Ensure-PptDirectory -Path $OutputPath
                foreach ($slide in @($pres.Slides)) {
                    $target = Join-Path $OutputPath ("slide-{0:D3}.jpg" -f $slide.SlideIndex)
                    $slide.Export($target, 'JPG')
                }
            }
        }

        [pscustomobject]@{
            Path = $resolvedPath
            Format = $Format
            OutputPath = $OutputPath
        }
    }
}

function ppt-spec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SpecPath
    )

    $resolvedSpecPath = Resolve-CodexPresentationPath -Path $SpecPath
    $spec = Get-Content -LiteralPath $resolvedSpecPath -Raw | ConvertFrom-Json -Depth 100
    $presentationNode = if ($spec.PSObject.Properties['presentation']) { $spec.presentation } else { $spec }
    $presentationPath =
        if ($presentationNode.PSObject.Properties['path'] -and $presentationNode.path) { [string]$presentationNode.path }
        elseif ($presentationNode.PSObject.Properties['presentationPath'] -and $presentationNode.presentationPath) { [string]$presentationNode.presentationPath }
        elseif ($spec.PSObject.Properties['presentationPath'] -and $spec.presentationPath) { [string]$spec.presentationPath }
        else { throw 'presentation.path or presentationPath is required in the spec.' }
    $unit =
        if ($presentationNode.PSObject.Properties['unit'] -and $presentationNode.unit) { [string]$presentationNode.unit }
        elseif ($spec.PSObject.Properties['unit'] -and $spec.unit) { [string]$spec.unit }
        else { 'in' }
    $layout =
        if ($presentationNode.PSObject.Properties['layout'] -and $presentationNode.layout) { [string]$presentationNode.layout }
        elseif ($spec.PSObject.Properties['layout'] -and $spec.layout) { [string]$spec.layout }
        else { 'blank' }

    Invoke-CodexPowerPointPresentation -Path $presentationPath -CreateIfMissing -Layout $layout -Action {
        param($ppt, $pres, $resolvedPath)

        $specWidth =
            if ($presentationNode.PSObject.Properties['width'] -and $presentationNode.width) { [double]$presentationNode.width }
            elseif ($spec.PSObject.Properties['width'] -and $spec.width) { [double]$spec.width }
            else { $null }
        $specHeight =
            if ($presentationNode.PSObject.Properties['height'] -and $presentationNode.height) { [double]$presentationNode.height }
            elseif ($spec.PSObject.Properties['height'] -and $spec.height) { [double]$spec.height }
            else { $null }

        if ($null -ne $specWidth -and $null -ne $specHeight) {
            $pres.PageSetup.SlideWidth = ConvertTo-PptPoints -Value $specWidth -Unit $unit
            $pres.PageSetup.SlideHeight = ConvertTo-PptPoints -Value $specHeight -Unit $unit
        }

        $slideResults = New-Object System.Collections.Generic.List[object]
        $targetSlides = @($spec.slides)

        for ($slideOrdinal = 0; $slideOrdinal -lt $targetSlides.Count; $slideOrdinal++) {
            $slideSpec = $targetSlides[$slideOrdinal]
            $slideLayout = if ($slideSpec.layout) { [string]$slideSpec.layout } else { 'blank' }
            $slideIndex = $slideOrdinal + 1
            if ($slideIndex -le $pres.Slides.Count) {
                $slide = $pres.Slides.Item($slideIndex)
            } else {
                $slide = $pres.Slides.Add($slideIndex, (Get-PptSlideLayoutValue -Layout $slideLayout))
            }

            if ($slideSpec.backgroundColor) {
                $slide.Background.Fill.ForeColor.RGB = (ConvertTo-OfficeRgb -Color ([string]$slideSpec.backgroundColor))
                $slide.Background.Fill.Solid()
            }

            foreach ($element in @($slideSpec.elements)) {
                $elementUnit = if ($element.unit) { [string]$element.unit } else { $unit }
                switch ([string]$element.type) {
                    'textbox' {
                        $shape = $slide.Shapes.AddTextbox(1,
                            (ConvertTo-PptPoints -Value ([double]$element.left) -Unit $elementUnit),
                            (ConvertTo-PptPoints -Value ([double]$element.top) -Unit $elementUnit),
                            (ConvertTo-PptPoints -Value ([double]$element.width) -Unit $elementUnit),
                            (ConvertTo-PptPoints -Value ([double]$element.height) -Unit $elementUnit))
                        if ($element.name) { $shape.Name = [string]$element.name }
                        $shape.TextFrame.TextRange.Text = [string]$element.text
                        Set-CodexShapeStyle -Shape $shape `
                            -FontName ([string]$element.fontName) `
                            -FontSize $(if ($element.fontSize) { [double]$element.fontSize } else { -1 }) `
                            -FontColor ([string]$element.fontColor) `
                            -Bold:([Nullable[bool]]$(if ($null -ne $element.bold) { [bool]$element.bold } else { $null }))
                    }
                    'shape' {
                        $shape = $slide.Shapes.AddShape(
                            (Get-PptShapeTypeValue -ShapeType ([string]$element.shape)),
                            (ConvertTo-PptPoints -Value ([double]$element.left) -Unit $elementUnit),
                            (ConvertTo-PptPoints -Value ([double]$element.top) -Unit $elementUnit),
                            (ConvertTo-PptPoints -Value ([double]$element.width) -Unit $elementUnit),
                            (ConvertTo-PptPoints -Value ([double]$element.height) -Unit $elementUnit))
                        if ($element.name) { $shape.Name = [string]$element.name }
                        if ($element.text) { $shape.TextFrame.TextRange.Text = [string]$element.text }
                        Set-CodexShapeStyle -Shape $shape `
                            -FillColor ([string]$element.fillColor) `
                            -FillColor2 ([string]$element.fillColor2) `
                            -Gradient:$([bool]$element.gradient) `
                            -LineColor ([string]$element.lineColor) `
                            -LineWeight $(if ($element.lineWeight) { [double]$element.lineWeight } else { -1 }) `
                            -FontColor ([string]$element.fontColor) `
                            -FontName ([string]$element.fontName) `
                            -FontSize $(if ($element.fontSize) { [double]$element.fontSize } else { -1 }) `
                            -Bold:([Nullable[bool]]$(if ($null -ne $element.bold) { [bool]$element.bold } else { $null })) `
                            -Rotation $(if ($element.rotation) { [double]$element.rotation } else { [double]::NaN }) `
                            -Shadow:$([bool]$element.shadow) `
                            -GlowColor ([string]$element.glowColor) `
                            -GlowRadius $(if ($element.glowRadius) { [double]$element.glowRadius } else { -1 })
                    }
                    'image' {
                        $imagePath = Resolve-CodexPresentationPath -Path ([string]$element.imagePath)
                        $shape = $slide.Shapes.AddPicture(
                            $imagePath,
                            $false,
                            $true,
                            (ConvertTo-PptPoints -Value ([double]$element.left) -Unit $elementUnit),
                            (ConvertTo-PptPoints -Value ([double]$element.top) -Unit $elementUnit),
                            (ConvertTo-PptPoints -Value ([double]$element.width) -Unit $elementUnit),
                            (ConvertTo-PptPoints -Value ([double]$element.height) -Unit $elementUnit))
                        if ($element.name) { $shape.Name = [string]$element.name }
                        if ($element.transparentColor) {
                            $shape.PictureFormat.TransparencyColor = (ConvertTo-OfficeRgb -Color ([string]$element.transparentColor))
                            $shape.PictureFormat.TransparentBackground = -1
                        }
                    }
                }
            }

            [void]$slideResults.Add([pscustomobject]@{
                SlideIndex = $slide.SlideIndex
                ElementCount = @($slideSpec.elements).Count
            })
        }

        while ($pres.Slides.Count -gt $targetSlides.Count) {
            $pres.Slides.Item($pres.Slides.Count).Delete()
        }

        [pscustomobject]@{
            Path = $resolvedPath
            SlideCount = $pres.Slides.Count
            Slides = @($slideResults.ToArray())
        }
    }
}

function ppt-addin-install {
    [CmdletBinding(DefaultParameterSetName = 'SourcePath')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'SourcePath', Position = 0)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true, ParameterSetName = 'SourceUrl', Position = 0)]
        [string]$SourceUrl,

        [string]$Name,

        [switch]$NoAutoLoad
    )

    $addInRoot = Get-CodexPowerPointAddInRoot
    if ($PSCmdlet.ParameterSetName -eq 'SourceUrl') {
        $fileName = if ($Name) {
            $Name
        } else {
            [IO.Path]::GetFileName(([Uri]$SourceUrl).AbsolutePath)
        }

        if ([string]::IsNullOrWhiteSpace([IO.Path]::GetExtension($fileName))) {
            $fileName += '.ppam'
        }

        $downloadPath = Join-Path (Get-CodexPowerPointStateRoot) $fileName
        Invoke-WebRequest -Uri $SourceUrl -OutFile $downloadPath -Headers @{ 'User-Agent' = 'Codex-Windows-Toolkit' }
        $resolvedSourcePath = $downloadPath
    } else {
        $resolvedSourcePath = Resolve-CodexPresentationPath -Path $SourcePath
        if (-not (Test-Path -LiteralPath $resolvedSourcePath)) {
            throw "PowerPoint add-in source was not found: $resolvedSourcePath"
        }
    }

    $packageExtension = [IO.Path]::GetExtension($resolvedSourcePath)
    if ($packageExtension -ieq '.zip') {
        $package = Expand-CodexPowerPointAddInPackage -PackagePath $resolvedSourcePath
        $resolvedSourcePath = $package.AddInPath
    }

    $fileName = if ($Name) {
        if ([string]::IsNullOrWhiteSpace([IO.Path]::GetExtension($Name))) { "$Name$([IO.Path]::GetExtension($resolvedSourcePath))" } else { $Name }
    } else {
        [IO.Path]::GetFileName($resolvedSourcePath)
    }

    $destinationPath = Join-Path $addInRoot $fileName
    Copy-Item -LiteralPath $resolvedSourcePath -Destination $destinationPath -Force

    if ($NoAutoLoad) {
        return [pscustomobject]@{
            Path = $destinationPath
            AutoLoad = $false
        }
    }

    Register-CodexPowerPointAddIn -AddInPath $destinationPath
}

function ppt-addin-register {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    Register-CodexPowerPointAddIn -AddInPath $Path
}

function ppt-addin-list {
    [CmdletBinding()]
    param()

    $addInRoot = Get-CodexPowerPointAddInRoot
    $diskAddIns = @(Get-ChildItem -LiteralPath $addInRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.ppam', '.ppa', '.pptm') })

    $session = New-CodexPowerPointApplication -Visible
    $ppt = $session.Application
    try {
        Invoke-CodexPowerPointComAction -Action { $ppt.Visible = -1 } | Out-Null
    } catch {
    }
    $rows = New-Object System.Collections.Generic.List[object]
    $addIns = $null

    try {
        try {
            $addIns = Invoke-CodexPowerPointComAction -Action { $ppt.AddIns }
            if ($null -ne $addIns) {
                $addInCount = Invoke-CodexPowerPointComAction -Action { $addIns.Count }
                for ($index = 1; $index -le $addInCount; $index++) {
                    $addin = Invoke-CodexPowerPointComAction -Action { $addIns.Item($index) }
                    try {
                        $fullName = Invoke-CodexPowerPointComAction -Action { $addin.FullName }
                        $name = Invoke-CodexPowerPointComAction -Action { $addin.Name }
                        if ([string]::IsNullOrWhiteSpace($fullName) -and [string]::IsNullOrWhiteSpace($name)) {
                            continue
                        }

                        [void]$rows.Add([pscustomobject]@{
                            Name = $name
                            FullName = $fullName
                            Path = $fullName
                            Loaded = (Invoke-CodexPowerPointComAction -Action { $addin.Loaded })
                            AutoLoad = (Invoke-CodexPowerPointComAction -Action { $addin.AutoLoad })
                            Registered = (Invoke-CodexPowerPointComAction -Action { $addin.Registered })
                            Source = 'PowerPoint'
                        })
                    } finally {
                        Release-CodexComObject -Object $addin
                    }
                }
            }
        } catch {
        }
    } finally {
        Release-CodexComObject -Object $addIns
        if ($null -ne $ppt) {
            Close-CodexPowerPointApplication -Application $ppt -Quit:$session.CreatedInstance
        }
    }

    foreach ($file in $diskAddIns) {
        if (-not ($rows | Where-Object FullName -eq $file.FullName)) {
            [void]$rows.Add([pscustomobject]@{
                Name = $file.BaseName
                FullName = $file.FullName
                Path = $file.FullName
                Loaded = $null
                AutoLoad = $null
                Registered = $null
                Source = 'Disk'
            })
        }
    }

    foreach ($registryRow in Get-CodexPowerPointRegistryAddInRows) {
        $existingRow = $rows | Where-Object {
            ($_.FullName -and $registryRow.FullName -and $_.FullName.Equals($registryRow.FullName, [System.StringComparison]::OrdinalIgnoreCase)) -or
            ($_.Name -and $registryRow.Name -and $_.Name.Equals($registryRow.Name, [System.StringComparison]::OrdinalIgnoreCase))
        } | Select-Object -First 1

        if ($null -ne $existingRow) {
            if ($null -eq $existingRow.AutoLoad -and $null -ne $registryRow.AutoLoad) {
                $existingRow.AutoLoad = $registryRow.AutoLoad
            }

            if ($null -eq $existingRow.Registered -and $null -ne $registryRow.Registered) {
                $existingRow.Registered = $registryRow.Registered
            }

            if (($existingRow.Source -eq 'Disk') -and $registryRow.Registered) {
                $existingRow.Source = 'Disk+Registry'
            }
        } else {
            [void]$rows.Add($registryRow)
        }
    }

    $rows
}
