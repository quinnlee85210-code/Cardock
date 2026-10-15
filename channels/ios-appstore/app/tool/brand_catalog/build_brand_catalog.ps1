[CmdletBinding()]
param(
    [string]$PythonPath = 'python',
    [string]$ChromePath = 'C:\Program Files\Google\Chrome\Application\chrome.exe',
    [string]$DartPath = '',
    [string]$GeneratedAtUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$appRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..\..')).Path
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $appRoot '..')).Path
$generator = Join-Path $scriptRoot 'generate_brand_catalog.py'
$renderer = Join-Path $scriptRoot 'render_brand_assets.ps1'
$auditor = Join-Path $scriptRoot 'audit_brand_catalog.py'
$parityTool = Join-Path $scriptRoot 'verify_brand_normalization_parity.dart'
$masterManifest = Join-Path $projectRoot 'manifests\cardock-brand-catalog-v1-source.json'
$parityManifest = Join-Path $projectRoot 'manifests\cardock-brand-catalog-v1-normalization-parity.json'

if ([string]::IsNullOrWhiteSpace($DartPath)) {
    $DartPath = Join-Path $projectRoot 'toolchains\flutter\3.44.8\flutter\bin\cache\dart-sdk\bin\dart.exe'
}
if (-not (Test-Path -LiteralPath $DartPath -PathType Leaf)) {
    throw "Project Dart executable not found: $DartPath"
}
if (-not (Test-Path -LiteralPath $parityTool -PathType Leaf)) {
    throw "Normalization parity tool not found: $parityTool"
}

& $PythonPath $generator prepare
if ($LASTEXITCODE -ne 0) {
    throw 'Brand catalog preparation failed.'
}
& $renderer -ChromePath $ChromePath
& $PythonPath $generator finalize --generated-at-utc $GeneratedAtUtc
if ($LASTEXITCODE -ne 0) {
    throw 'Brand catalog finalization failed.'
}

Push-Location -LiteralPath $appRoot
try {
    & $DartPath run $parityTool --master $masterManifest --output $parityManifest
    if ($LASTEXITCODE -ne 0) {
        throw 'Brand normalization runtime/build parity failed.'
    }
}
finally {
    Pop-Location
}

& $PythonPath $auditor
if ($LASTEXITCODE -ne 0) {
    throw 'Brand catalog audit failed.'
}
