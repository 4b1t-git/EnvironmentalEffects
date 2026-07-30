<#
Validates every delivered snow texture against its vanilla source and the
manifest, then checks the Stage 1 wiring.

The pixel assertions are the point: they state what a snow texture must LOOK
like, so a future change is judged on merit rather than on matching a frozen
pixel count. The first shipped attempt satisfied "256x256, alpha unchanged" and
was still invisible in game.
#>
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$modRoot = Join-Path $projectRoot 'mod'
$manifestPath = Join-Path $projectRoot 'assets\snow_texture_manifest.json'
$specPath = Join-Path $PSScriptRoot 'snow_assets.json'
$generatorPath = Join-Path $PSScriptRoot 'generate_snow_textures.ps1'
$replayPath = Join-Path $PSScriptRoot 'replay_snow_textures.ps1'
$modelPath = Join-Path $modRoot '42\media\scripts\models_EnvironmentalWeapons.txt'
$profilePath = Join-Path $modRoot '42\media\lua\shared\EnvironmentalWeapons\EW_Profiles.lua'
$debugPath = Join-Path $modRoot '42\media\lua\client\EnvironmentalWeapons\EW_DebugProbe.lua'

foreach ($file in @($manifestPath, $specPath, $generatorPath, $replayPath,
        $modelPath, $profilePath, $debugPath)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required file missing: $file"
    }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$spec = Get-Content -Raw -LiteralPath $specPath | ConvertFrom-Json
if ($manifest.schema -ne 1) { throw "Unsupported manifest schema: $($manifest.schema)" }

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Every reviewed asset must have produced evidence, and the manifest may not
# carry entries nobody asked for.
$specIds = @($spec.assets | ForEach-Object { $_.id })
$manifestIds = @($manifest.assets.PSObject.Properties | ForEach-Object { $_.Name })
foreach ($id in $specIds) {
    if ($manifestIds -notcontains $id) { throw "Spec asset has no manifest entry: $id" }
}
foreach ($id in $manifestIds) {
    if ($specIds -notcontains $id) { throw "Manifest entry is not in the spec: $id" }
}

$reports = @()

foreach ($property in $manifest.assets.PSObject.Properties) {
    $id = $property.Name
    $entry = $property.Value
    # output is relative to the mod root because it ships; recipe is relative to
    # the project root because a frozen recipe is tooling data and never ships.
    $outputPath = Join-Path $modRoot ($entry.output -replace '/', '\')
    $recipePath = Join-Path $projectRoot ($entry.recipe -replace '/', '\')

    foreach ($file in @($entry.sourcePath, $outputPath, $recipePath)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "$id`: required file missing: $file"
        }
    }

    $sourceHash = Get-Sha256 $entry.sourcePath
    $outputHash = Get-Sha256 $outputPath
    $recipeHash = Get-Sha256 $recipePath
    if ($sourceHash -ne $entry.sourceSha256) { throw "$id`: source hash mismatch: $sourceHash" }
    if ($outputHash -ne $entry.outputSha256) { throw "$id`: output hash mismatch: $outputHash" }
    if ($recipeHash -ne $entry.outputSha256) { throw "$id`: recipe hash mismatch: $recipeHash" }

    $sourceBitmap = [System.Drawing.Bitmap]::new($entry.sourcePath)
    $outputBitmap = [System.Drawing.Bitmap]::new($outputPath)
    try {
        if ($sourceBitmap.Width -ne 256 -or $sourceBitmap.Height -ne 256) {
            throw "$id`: source dimensions are not 256x256"
        }
        if ($outputBitmap.Width -ne 256 -or $outputBitmap.Height -ne 256) {
            throw "$id`: output dimensions are not 256x256"
        }

        $opaquePixels = 0
        $transparentPixels = 0
        $changedRgbPixels = 0
        # A core needs BOTH tests, and each one alone is provably insufficient.
        #
        # Absolute luma alone is not portable. It is safe on the Hunting Rifle only
        # because that art peaks at luma 149, but D_E_Pistol has 8203 vanilla texels
        # already at or above 190 and DoubleBarrelShotgun has 344, so a faint
        # dusting there would be counted as solid snow and the brightness assertion
        # would pass with no snow present. 1911_Pistol peaks at 189.0, one level
        # from tripping, which shows how thin that margin is.
        #
        # Lift alone is not sufficient either: it cannot separate a full drift over
        # dark metal from a faint fleck over dark metal.
        #
        # Requiring both means a genuine drift core registers (bright result, large
        # rise), a dusting does not (small rise), and vanilla that was already snow
        # bright does not (no rise) -- correctly, because snow there is invisible
        # anyway and must not count toward "the snow reads clearly".
        $coreTexels = 0
        $coreLumaSum = 0.0
        $coreSatSum = 0.0
        $dustingTexels = 0
        $coreLumaFloor = 190
        $coreLiftFloor = 25
        $dustingLift = 20

        for ($y = 0; $y -lt 256; $y++) {
            for ($x = 0; $x -lt 256; $x++) {
                $sourcePixel = $sourceBitmap.GetPixel($x, $y)
                $outputPixel = $outputBitmap.GetPixel($x, $y)
                if ($outputPixel.A -eq 255) { $opaquePixels++ } else { $transparentPixels++ }
                if ($sourcePixel.R -ne $outputPixel.R -or
                    $sourcePixel.G -ne $outputPixel.G -or
                    $sourcePixel.B -ne $outputPixel.B) {
                    $changedRgbPixels++
                    $sourceLuma = 0.299 * $sourcePixel.R + 0.587 * $sourcePixel.G + 0.114 * $sourcePixel.B
                    $outputLuma = 0.299 * $outputPixel.R + 0.587 * $outputPixel.G + 0.114 * $outputPixel.B
                    $lift = $outputLuma - $sourceLuma
                    if ($outputLuma -ge $coreLumaFloor -and $lift -ge $coreLiftFloor) {
                        $coreTexels++
                        $coreLumaSum += $outputLuma
                        $maxChannel = [Math]::Max($outputPixel.R, [Math]::Max($outputPixel.G, $outputPixel.B))
                        $minChannel = [Math]::Min($outputPixel.R, [Math]::Min($outputPixel.G, $outputPixel.B))
                        if ($maxChannel -gt 0) {
                            $coreSatSum += (($maxChannel - $minChannel) / $maxChannel)
                        }
                    }
                    elseif ($lift -ge $dustingLift) {
                        $dustingTexels++
                    }
                }
            }
        }
    }
    finally {
        $sourceBitmap.Dispose()
        $outputBitmap.Dispose()
    }

    $coverage = [Math]::Round(($changedRgbPixels / 65536.0) * 100, 4)
    $coreLuma = if ($coreTexels -gt 0) { [Math]::Round($coreLumaSum / $coreTexels, 2) } else { 0 }
    $coreSat = if ($coreTexels -gt 0) { [Math]::Round($coreSatSum / $coreTexels, 4) } else { 1 }

    # The vanilla sources are RGB PNGs with no alpha channel, so "alpha is
    # unchanged" proves nothing. What matters is that no transparency appears,
    # which would punch holes in the rendered weapon.
    if ($transparentPixels -ne 0) { throw "$id`: introduces transparency on $transparentPixels pixels" }
    if ($opaquePixels -ne 65536) { throw "$id`: opaque pixel count mismatch: $opaquePixels" }

    # Deliberately no per-stage coverage band. Stage 1 is a dusting and stage 4
    # is nearly buried, so any fixed band would either reject a valid stage or
    # wave through a broken one. The progression is checked for monotonicity
    # after this loop instead, which is the property that actually matters.
    if ($coverage -lt 8 -or $coverage -gt 55) { throw "$id`: coverage implausible: $coverage%" }

    # These encode why the first asset was invisible at gameplay zoom: it was
    # mid-grey and brown rather than neutral white.
    if ($coreTexels -lt 3000) { throw "$id`: too little solid snow: $coreTexels core texels" }
    if ($coreLuma -lt 205) { throw "$id`: snow core is too dark to read: $coreLuma" }
    if ($coreSat -gt 0.06) { throw "$id`: snow core is tinted rather than neutral: $coreSat" }

    # Placement is a mesh-space property proved at generation time and recorded.
    # Cross-checking the record against an independent pixel measurement is what
    # stops a doctored manifest from passing.
    #
    # Density, not share: even a buried weapon holds less on a vertical flank
    # than on a horizontal surface, so this survives every stage, whereas a fixed
    # share floor confuses "heavily covered" with "mask in the wrong place".
    if ($entry.densityRatio -lt 1.3) {
        throw "$id`: up-facing snow is not denser than flank snow: $($entry.densityRatio)"
    }
    if ($entry.upShare -lt 0.45) {
        throw "$id`: snow is not concentrated on up-facing surfaces: $($entry.upShare)"
    }
    # Some flank snow must exist, or the weapon looks bare seen edge-on.
    if ($entry.upShare -gt 0.98) {
        throw "$id`: no flank snow at all: upShare $($entry.upShare)"
    }
    if ($entry.changedTexels -ne $changedRgbPixels) {
        throw "$id`: manifest changedTexels $($entry.changedTexels) != measured $changedRgbPixels"
    }
    if ([Math]::Abs($entry.coreSnowLuma - $coreLuma) -gt 12) {
        throw "$id`: manifest coreSnowLuma $($entry.coreSnowLuma) disagrees with measured $coreLuma"
    }

    $reports += [PSCustomObject][ordered]@{
        Asset = $id
        FullType = $entry.fullType
        Stage = [int]$entry.stage
        OutputPath = $outputPath
        SourcePath = $entry.sourcePath
        OutputSha256 = $outputHash
        CoveragePercent = $coverage
        CoreTexels = $coreTexels
        CoreSnowLuma = $coreLuma
        CoreSnowSaturation = $coreSat
        FlankDustingTexels = $dustingTexels
        UpFacingShare = $entry.upShare
        DensityRatio = $entry.densityRatio
    }
}

# Snow accumulates; it never retreats. Consecutive stages of one weapon must
# cover strictly more, and no texel may lose its snow as the stage rises. A stage
# that moved snow somewhere else instead of adding to it would pop visibly in
# game the moment a threshold is crossed.
#
# Nesting is checked on the SNOW MASK (texels meaningfully brightened against
# vanilla), not on raw luma. Drifts cast a short shadow onto the bare surface at
# their foot, so some texels are legitimately darker than vanilla, and as drifts
# grow those shadow bands move. Raw-luma monotonicity would flag that as a defect.
foreach ($group in $reports | Group-Object FullType) {
    $ordered = @($group.Group | Sort-Object Stage)
    for ($i = 1; $i -lt $ordered.Count; $i++) {
        $previous = $ordered[$i - 1]
        $current = $ordered[$i]
        if ($current.CoveragePercent -le $previous.CoveragePercent) {
            throw "$($group.Name): stage $($current.Stage) coverage $($current.CoveragePercent)% does not exceed stage $($previous.Stage) coverage $($previous.CoveragePercent)%"
        }

        $vanilla = [System.Drawing.Bitmap]::new($previous.SourcePath)
        $earlier = [System.Drawing.Bitmap]::new($previous.OutputPath)
        $later = [System.Drawing.Bitmap]::new($current.OutputPath)
        try {
            $retreats = 0
            $snowLift = 20
            for ($y = 0; $y -lt 256; $y++) {
                for ($x = 0; $x -lt 256; $x++) {
                    $v = $vanilla.GetPixel($x, $y)
                    $a = $earlier.GetPixel($x, $y)
                    $b = $later.GetPixel($x, $y)
                    $lumaV = 0.299 * $v.R + 0.587 * $v.G + 0.114 * $v.B
                    $lumaA = 0.299 * $a.R + 0.587 * $a.G + 0.114 * $a.B
                    $lumaB = 0.299 * $b.R + 0.587 * $b.G + 0.114 * $b.B
                    $snowedEarlier = ($lumaA - $lumaV) -ge $snowLift
                    $snowedLater = ($lumaB - $lumaV) -ge $snowLift
                    if ($snowedEarlier -and -not $snowedLater) { $retreats++ }
                }
            }
        }
        finally {
            $vanilla.Dispose()
            $earlier.Dispose()
            $later.Dispose()
        }
        if ($retreats -gt 0) {
            throw "$($group.Name): stage $($current.Stage) lost snow that stage $($previous.Stage) had, on $retreats texels; snow must only grow"
        }
        Write-Host "progression $($group.Name) stage $($previous.Stage)->$($current.Stage): PASS (nested, +$([Math]::Round($current.CoveragePercent - $previous.CoveragePercent, 2))% coverage)"
    }
}

$models = Get-Content -Raw -LiteralPath $modelPath
$profile = Get-Content -Raw -LiteralPath $profilePath
$debugProbe = Get-Content -Raw -LiteralPath $debugPath

# Every delivered texture must be reachable: registered on a model and selected
# by a stage. An orphan texture ships bytes the game never loads.
$stageModelNames = @{ 1 = 'EW_HuntingRifle_SnowLight'; 2 = 'EW_HuntingRifle_SnowMedium';
    3 = 'EW_HuntingRifle_SnowHeavy'; 4 = 'EW_HuntingRifle_SnowFull' }
foreach ($report in $reports) {
    $textureName = [IO.Path]::GetFileNameWithoutExtension($report.OutputPath)
    if (-not $models.Contains("texture = weapons/firearm/$textureName")) {
        throw "Texture is not registered on any model: $textureName"
    }
    $modelName = $stageModelNames[$report.Stage]
    if (-not $modelName) { throw "No model name mapped for stage $($report.Stage)" }
    if (-not $models.Contains("model $modelName")) {
        throw "Model missing for stage $($report.Stage): $modelName"
    }
    if (-not $profile.Contains("equippedModel = `"$modelName`"")) {
        throw "Profile does not select $modelName for stage $($report.Stage)"
    }
}
if (-not $models.Contains('mesh = weapons/firearm/MSR788_Rifle')) {
    throw 'Vanilla mesh reference missing'
}
if ($models.Contains('model EW_HuntingRifle_SnowLight_World')) {
    throw 'Legacy world model is still registered'
}
# Firearms must never carry a WorldStaticModel: it forces the generic atlas
# branch and stands the dropped rifle upright.
$worldNilCount = ([regex]::Matches($profile, 'worldModel\s*=\s*nil')).Count
if ($worldNilCount -lt 5) {
    throw "All five stage slots must leave worldModel nil; found $worldNilCount"
}
if ($profile -match 'worldModel\s*=\s*"') {
    throw 'A stage sets a world model; firearms must use the HandWeapon fallback'
}
if (-not $debugProbe.Contains('if not Config.DEBUG then return end')) {
    throw 'Debug probe is not fail-closed'
}
if ($debugProbe -match 'setCondition|setCurrentAmmoCount|setAmmo|setMagazine|setRoundChambered|setName|setFavorite') {
    throw 'Debug probe mutates protected item state'
}

$reports | Format-List
Write-Host "validate_snow_textures: PASS ($($reports.Count) assets, model/profile/debug PASS)"
