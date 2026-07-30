<#
Replays the frozen snow texture bytes recorded in
`assets/snow_texture_manifest.json`.

This script contains no algorithm. It only materializes the exact reviewed PNGs,
because PNG encoders are not byte-stable across machines. To change a texture,
run `generate_snow_textures.ps1 -FreezeRecipe -WriteManifest`.

Expected hashes come from the manifest rather than constants copied into several
scripts. The manifest is a delivered file, so any change to it moves the
canonical tree hash in `outputs/EnvironmentalWeapons_build_hashes.json`, and the
pixel properties are re-proved from the images by `validate_snow_textures.ps1`.
#>
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $projectRoot 'assets\snow_texture_manifest.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Texture manifest missing: $manifestPath"
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schema -ne 1) { throw "Unsupported manifest schema: $($manifest.schema)" }

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$count = 0
foreach ($property in $manifest.assets.PSObject.Properties) {
    $id = $property.Name
    $entry = $property.Value
    $outputPath = Join-Path $projectRoot ($entry.output -replace '/', '\')
    $recipePath = Join-Path $projectRoot ($entry.recipe -replace '/', '\')

    if (-not (Test-Path -LiteralPath $entry.sourcePath -PathType Leaf)) {
        throw "$id`: vanilla source not found: $($entry.sourcePath)"
    }
    if (-not (Test-Path -LiteralPath $recipePath -PathType Leaf)) {
        throw "$id`: frozen recipe not found: $recipePath"
    }

    $sourceHash = Get-Sha256 $entry.sourcePath
    if ($sourceHash -ne $entry.sourceSha256) {
        throw "$id`: vanilla source hash mismatch. Expected $($entry.sourceSha256), got $sourceHash"
    }
    $recipeHash = Get-Sha256 $recipePath
    if ($recipeHash -ne $entry.outputSha256) {
        throw "$id`: frozen recipe hash mismatch. Expected $($entry.outputSha256), got $recipeHash"
    }

    $outputDirectory = Split-Path -Parent $outputPath
    if (-not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    [IO.File]::WriteAllBytes($outputPath, [IO.File]::ReadAllBytes($recipePath))

    $outputHash = Get-Sha256 $outputPath
    if ($outputHash -ne $entry.outputSha256) {
        throw "$id`: replayed output hash mismatch. Expected $($entry.outputSha256), got $outputHash"
    }

    Write-Host "$id`: PASS ($outputHash)"
    $count++
}

if ($count -eq 0) { throw "Manifest lists no assets" }
Write-Host "replay_snow_textures: PASS ($count assets)"
