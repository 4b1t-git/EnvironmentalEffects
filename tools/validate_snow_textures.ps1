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
        $alphaChanged = 0
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
                if ($sourcePixel.A -ne $outputPixel.A) { $alphaChanged++ }
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

    # Alpha must come through untouched. Most vanilla firearm textures are RGB,
    # where this is trivially true, but PumpAction_Shotgun and M9_Pistol are RGBA
    # with a few hundred semi-transparent edge texels: forcing those opaque
    # hardened antialiased edges. The invariant is "we do not touch alpha", not
    # "there is no alpha".
    if ($alphaChanged -ne 0) { throw "$id`: alpha differs from the source on $alphaChanged pixels" }

    # Coverage is measured against the area the weapon actually occupies in its
    # atlas, not against the whole 256x256. Atlas utilization varies enormously
    # between weapons -- T_Carabine owns 11261 texels against M16's 35158 -- so an
    # absolute band is really a measure of how big the weapon is, and it rejected
    # a perfectly good T_Carabine at 5.3% of atlas that was 31% of its own area.
    #
    # This is a sanity rail, not a quality gate: the real checks are core share,
    # density ratio, and the stage-to-stage nesting proof below. Values above 100
    # are expected, because changed texels include the bleed into gutter space
    # while the denominator counts owned surface only.
    # Wetness is a different phenomenon and gets different assertions. Snow must
    # be bright, neutral and concentrated on up-facing surfaces; water must be
    # darker or shinier than what it sits on and reaches everywhere, so none of
    # the snow rails below apply to it. The pixel-level guarantees that DO apply
    # to both -- exact hashes, dimensions and untouched alpha -- were already
    # asserted above this point.
    $mode = if ($entry.PSObject.Properties['mode']) { [string]$entry.mode } else { 'snow' }
    if ($mode -eq 'wet') {
        if ($changedRgbPixels -le 0) { throw "$id`: wet texture changed no pixels" }
        if ([double]$entry.relativeLumaShift -le 0) {
            throw "$id`: wet texture records no shift from vanilla: $($entry.relativeLumaShift)"
        }
        if ([double]$entry.coreWetSaturation -le 0) {
            throw "$id`: wet texture lost all colour: $($entry.coreWetSaturation)"
        }
        if ([double]$entry.coreTexels -le 0) { throw "$id`: wet texture has no wetted core" }
        # Same shape as the snow report on purpose: everything downstream -- the
        # progression pass and the model/profile cross-check -- iterates one list.
        $reports += [PSCustomObject][ordered]@{
            Asset = $id
            FullType = $entry.fullType
            Stage = [int]$entry.stage
            Mode = 'wet'
            OutputPath = $outputPath
            SourcePath = $entry.sourcePath
            OutputSha256 = $outputHash
            CoveragePercent = [double]$entry.coveragePercent
            ChangedRgbPixels = $changedRgbPixels
        }
        continue
    }

    $ownedTexels = [double]$entry.upFacingTexels + [double]$entry.flankEligibleTexels
    if ($ownedTexels -le 0) { throw "$id`: manifest reports no owned surface" }
    $ownedCoverage = [Math]::Round(100 * $changedRgbPixels / $ownedTexels, 1)
    if ($ownedCoverage -lt 20 -or $ownedCoverage -gt 130) {
        throw "$id`: coverage implausible: $ownedCoverage% of the weapon's own atlas area"
    }

    # These encode why the first asset was invisible at gameplay zoom: it was
    # mid-grey and brown rather than neutral white.
    # Relative, not absolute. An absolute count is a property of how much atlas a
    # weapon occupies, not of whether its snow is solid: JS14 has 4255 up-facing
    # texels against the Hunting Rifle's 13313, so a floor tuned on the rifle
    # rejected a perfectly good JS14 texture. What matters is that the snow is
    # mostly solid rather than all soft fringe.
    $coreShare = if ($changedRgbPixels -gt 0) { $coreTexels / $changedRgbPixels } else { 0 }
    if ($coreTexels -lt 200) { throw "$id`: essentially no solid snow: $coreTexels core texels" }
    if ($coreShare -lt 0.25) {
        throw "$id`: snow is mostly soft fringe: $([Math]::Round(100 * $coreShare, 1))% of changed texels are cores"
    }
    if ($coreLuma -lt 205) { throw "$id`: snow core is too dark to read: $coreLuma" }
    # Loose bound only. This pass identifies cores by absolute luma plus lift,
    # which is a proxy: the generator knows the actual alpha and reports 0.012 to
    # 0.019 across all assets, while this proxy admits bright flank dust over pale
    # wood and drifts to 0.06 on some weapons. The strict neutrality guarantee is
    # asserted against the generator's own figure, in tools/validate.js and below;
    # this catches a texture that has gone obviously colourful.
    if ($coreSat -gt 0.12) { throw "$id`: snow core is badly tinted: $coreSat" }
    if ($entry.coreSnowSaturation -gt 0.06) {
        throw "$id`: recorded core saturation is tinted rather than neutral: $($entry.coreSnowSaturation)"
    }

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
    # Cross-check, not an invariant. The generator counts against the pixels GDI+
    # hands it, and this counts against the source file read independently. Those
    # agree exactly on the RGB sources but differ by a few hundred texels on the
    # RGBA ones (PumpAction_Shotgun, M9_Pistol), because a 1:1 GDI+ transfer of an
    # image with an alpha channel is not bit-exact. The real invariants -- hash
    # match, placement, brightness, stage nesting -- are unaffected, so this stays
    # a sanity bound rather than being tightened into a false exactness claim.
    $countDrift = [Math]::Abs($entry.changedTexels - $changedRgbPixels)
    if ($countDrift -gt 400) {
        throw "$id`: manifest changedTexels $($entry.changedTexels) differs from measured $changedRgbPixels by $countDrift"
    }
    if ([Math]::Abs($entry.coreSnowLuma - $coreLuma) -gt 12) {
        throw "$id`: manifest coreSnowLuma $($entry.coreSnowLuma) disagrees with measured $coreLuma"
    }

    $reports += [PSCustomObject][ordered]@{
        Asset = $id
        FullType = $entry.fullType
        Stage = [int]$entry.stage
        Mode = 'snow'
        OutputPath = $outputPath
        SourcePath = $entry.sourcePath
        OutputSha256 = $outputHash
        CoveragePercent = $coverage
        OwnedCoveragePercent = $ownedCoverage
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
#
# Snow and wet are two separate progressions on one axis, so they are grouped
# and ordered independently. Sorting a weapon's stages -3..4 as one run compared
# the most soaked texture against the least snowed one, which is not a
# progression at all -- and on the wet side -3 is the DEEPEST level, so the
# sequence has to run on magnitude rather than on signed value.
#
# Only the snow side proves texel nesting. Water does not accumulate as a
# growing mask: it darkens and lifts what is already there, so a texel can
# legitimately move in either direction between levels.
foreach ($group in $reports | Group-Object { "$($_.FullType)|$($_.Mode)" }) {
    $ordered = @($group.Group | Sort-Object { [Math]::Abs($_.Stage) })
    if ($ordered[0].Mode -eq 'wet') {
        for ($i = 1; $i -lt $ordered.Count; $i++) {
            $previous = $ordered[$i - 1]
            $current = $ordered[$i]
            if ($current.ChangedRgbPixels -lt $previous.ChangedRgbPixels) {
                throw "$($group.Name): wet level $($current.Stage) touches fewer texels than $($previous.Stage)"
            }
            Write-Host "progression $($group.Name) stage $($previous.Stage)->$($current.Stage): PASS (wet, $($current.ChangedRgbPixels) texels)"
        }
        continue
    }
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
# by a stage. An orphan texture ships bytes the game never loads. Model names come
# from the spec rather than a table here, so adding a weapon does not require
# editing this validator.
$specById = @{}
foreach ($asset in $spec.assets) { $specById[$asset.id] = $asset }

foreach ($report in $reports) {
    $asset = $specById[$report.Asset]
    if (-not $asset) { throw "No spec entry for $($report.Asset)" }
    $textureName = [IO.Path]::GetFileNameWithoutExtension($report.OutputPath)
    if (-not $models.Contains("texture = weapons/firearm/$textureName")) {
        throw "Texture is not registered on any model: $textureName"
    }
    if (-not $asset.modelName) { throw "$($report.Asset): spec has no modelName" }
    if (-not $models.Contains("model $($asset.modelName)")) {
        throw "Model missing for $($report.Asset): $($asset.modelName)"
    }
    if (-not $profile.Contains("equippedModel = `"$($asset.modelName)`"")) {
        throw "Profile does not select $($asset.modelName) for stage $($report.Stage)"
    }
}
if ($models.Contains('model EW_HuntingRifle_SnowLight_World')) {
    throw 'Legacy world model is still registered'
}
# Firearms must never carry a WorldStaticModel: it forces the generic atlas
# branch and stands the dropped weapon upright. Five slots per profiled weapon.
$weaponCount = @($spec.assets | ForEach-Object { $_.fullType } | Sort-Object -Unique).Count
$worldNilCount = ([regex]::Matches($profile, 'worldModel\s*=\s*nil')).Count
if ($worldNilCount -lt (5 * $weaponCount)) {
    throw "Expected $(5 * $weaponCount) worldModel=nil slots for $weaponCount weapons; found $worldNilCount"
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
