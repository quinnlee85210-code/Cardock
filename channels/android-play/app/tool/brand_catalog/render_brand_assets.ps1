[CmdletBinding()]
param(
    [string]$ChromePath = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$appRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..\..')).Path
$generatedRoot = Join-Path $scriptRoot '.generated'
$layoutPath = Join-Path $generatedRoot 'brand_sprite_layout.json'
$htmlPath = Join-Path $generatedRoot 'brand_sprite.html'
$spritePath = Join-Path $generatedRoot 'brand_sprite.png'
$profileRoot = Join-Path $generatedRoot ("chrome-profile-render-$PID")
$iconRoot = Join-Path $appRoot 'assets\brands\v1\icons'

function Assert-PathWithin {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Parent
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullParent = [IO.Path]::GetFullPath($Parent).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $prefix = $fullParent + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside expected parent: $fullPath"
    }
    return $fullPath
}

if (-not (Test-Path -LiteralPath $ChromePath -PathType Leaf)) {
    throw "Chrome executable not found: $ChromePath"
}
if (-not (Test-Path -LiteralPath $layoutPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $htmlPath -PathType Leaf)) {
    throw 'Run generate_brand_catalog.py prepare before rendering assets.'
}

$generatedRoot = Assert-PathWithin -Path $generatedRoot -Parent $scriptRoot
$iconRoot = Assert-PathWithin -Path $iconRoot -Parent $appRoot
$profileRoot = Assert-PathWithin -Path $profileRoot -Parent $generatedRoot
$spritePath = Assert-PathWithin -Path $spritePath -Parent $generatedRoot
New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null
New-Item -ItemType Directory -Path $iconRoot -Force | Out-Null
New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

$layout = Get-Content -LiteralPath $layoutPath -Raw -Encoding UTF8 |
    ConvertFrom-Json -Depth 16
if ($layout.cellSize -ne 96 -or $layout.entries.Count -ne 600) {
    throw 'Unexpected sprite layout; expected 600 entries at 96 px.'
}

$htmlUri = [Uri]::new((Resolve-Path -LiteralPath $htmlPath).Path).AbsoluteUri
$chromeArguments = @(
    '--headless=new'
    '--disable-gpu'
    '--disable-software-rasterizer'
    '--disable-dev-shm-usage'
    '--no-sandbox'
    '--disable-background-networking'
    '--disable-component-update'
    '--disable-default-apps'
    '--disable-sync'
    '--metrics-recording-only'
    '--no-first-run'
    '--no-default-browser-check'
    '--hide-scrollbars'
    '--force-device-scale-factor=1'
    '--default-background-color=00000000'
    "--user-data-dir=$profileRoot"
    "--window-size=$($layout.width),$($layout.height)"
    "--screenshot=$spritePath"
    $htmlUri
)

$chromeProcess = Start-Process `
    -FilePath $ChromePath `
    -ArgumentList $chromeArguments `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($chromeProcess.ExitCode -ne 0) {
    throw "Chrome sprite render failed with exit code $($chromeProcess.ExitCode)"
}
if (-not (Test-Path -LiteralPath $spritePath -PathType Leaf)) {
    throw 'Chrome did not create the expected sprite PNG.'
}

Add-Type -AssemblyName System.Drawing
$sprite = [Drawing.Bitmap]::FromFile($spritePath)
try {
    if ($sprite.Width -ne $layout.width -or $sprite.Height -ne $layout.height) {
        throw "Unexpected sprite dimensions: $($sprite.Width)x$($sprite.Height)"
    }

    foreach ($oldAsset in Get-ChildItem -LiteralPath $iconRoot -File -Filter '*.png') {
        $oldPath = Assert-PathWithin -Path $oldAsset.FullName -Parent $iconRoot
        Remove-Item -LiteralPath $oldPath -Force
    }

    foreach ($entry in $layout.entries) {
        $brandId = [string]$entry.brandId
        if ($brandId -notmatch '^[a-z0-9][a-z0-9._-]*$') {
            throw "Unsafe brand ID in layout: $brandId"
        }
        $destination = Assert-PathWithin `
            -Path (Join-Path $iconRoot "$brandId.png") `
            -Parent $iconRoot
        $rectangle = [Drawing.Rectangle]::new(
            [int]$entry.x,
            [int]$entry.y,
            [int]$layout.cellSize,
            [int]$layout.cellSize
        )
        $crop = $sprite.Clone(
            $rectangle,
            [Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        try {
            $crop.Save($destination, [Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $crop.Dispose()
        }
    }
}
finally {
    $sprite.Dispose()
}

$assetCount = @(Get-ChildItem -LiteralPath $iconRoot -File -Filter '*.png').Count
if ($assetCount -ne 600) {
    throw "Rendered asset count is $assetCount; expected 600."
}

if (Test-Path -LiteralPath $profileRoot -PathType Container) {
    $profileRoot = Assert-PathWithin -Path (Resolve-Path -LiteralPath $profileRoot).Path -Parent $generatedRoot
    Remove-Item -LiteralPath $profileRoot -Recurse -Force
}

Write-Output "RENDERED_BRAND_ASSETS=$assetCount"
