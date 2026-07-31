<#
Assembles the Steam Workshop upload folder from the validated mod tree.

Layout matches the maintainer's other published mod rather than the official
template, because that is the one known to have uploaded successfully:

    <Workshop>\<Title>\
        workshop.txt
        preview.png
        contents\mods\<mod id>\42\mod.info
                                  \poster.png
                                  \media\...

The template ships `Contents` capitalised and no `42` version folder; WarmUp uses
lowercase `contents` and puts everything under `42`, which is what Build 42
actually wants. Following the working example.

Source is the CANONICAL output tree, never the working tree, so what is uploaded
is byte-for-byte what the validators passed and the hash manifest recorded. It
refuses to run if the two have drifted.

Destructive only inside the target folder, and only for a folder it recognises
as a previous build of this same mod.
#>
[CmdletBinding()]
param(
    [string]$Title = "WeatherEffects",
    [string]$ModId = "WeatherEffects",
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)

$canonical = Join-Path $repoRoot "outputs\$ModId"
$workRoot = Join-Path $projectRoot 'mod'
$workshopSource = Join-Path $projectRoot 'workshop'

foreach ($required in @($canonical, $workRoot, $workshopSource)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "missing: $required" }
}

# The canonical tree is the deliverable; the working tree is only its source.
# Uploading from `mod/` would let an unsynced edit reach Steam without ever
# passing a validator.
$workFiles = Get-ChildItem $workRoot -Recurse -File
$drift = 0
foreach ($f in $workFiles) {
    $rel = $f.FullName.Substring((Resolve-Path $workRoot).Path.Length + 1)
    $target = Join-Path $canonical $rel
    if (-not (Test-Path -LiteralPath $target)) { $drift++; continue }
    if ((Get-FileHash $f.FullName -Algorithm SHA256).Hash -ne
        (Get-FileHash $target -Algorithm SHA256).Hash) { $drift++ }
}
if ($drift -gt 0) {
    throw "$drift file(s) differ between work and canonical trees. Run sync_development_build.ps1 -Apply first."
}
Write-Host "source: canonical tree matches work tree ($($workFiles.Count) files)"

$workshopRoot = Join-Path $env:USERPROFILE 'Zomboid\Workshop'
$target = Join-Path $workshopRoot $Title
$contents = Join-Path $target "contents\mods\$ModId"

if (-not $Apply) {
    Write-Host "DRY RUN. Would write:"
    Write-Host "  $target\workshop.txt"
    Write-Host "  $target\preview.png"
    Write-Host "  $contents\42\..."
    Write-Host "Re-run with -Apply."
    return
}

# Only ever remove a folder that is already a build of THIS mod, so a typo in
# -Title cannot delete somebody else's workshop item.
if (Test-Path -LiteralPath $target) {
    $marker = Join-Path $contents '42\mod.info'
    if (-not (Test-Path -LiteralPath $marker)) {
        throw "$target exists but does not contain $ModId. Refusing to touch it."
    }
    $existingId = (Select-String -LiteralPath $marker -Pattern '^id=(.+)$').Matches[0].Groups[1].Value.Trim()
    if ($existingId -ne $ModId) {
        throw "$target holds mod id '$existingId', not '$ModId'. Refusing to touch it."
    }
    Remove-Item -LiteralPath $target -Recurse -Force
    Write-Host "replaced previous package"
}

New-Item -ItemType Directory -Path $contents -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $canonical '42') -Destination $contents -Recurse -Force
Copy-Item -LiteralPath (Join-Path $workshopSource 'workshop.txt') -Destination $target -Force

$preview = Join-Path (Split-Path -Parent $projectRoot) 'EnvironmentalWeapons-preview\preview.png'
if (-not (Test-Path -LiteralPath $preview)) { throw "preview.png not found: $preview" }
Copy-Item -LiteralPath $preview -Destination (Join-Path $target 'preview.png') -Force

# Prove the copy, rather than trusting Copy-Item.
$copied = Get-ChildItem (Join-Path $contents '42') -Recurse -File
$bad = 0
foreach ($f in $copied) {
    $rel = $f.FullName.Substring((Join-Path $contents '42').Length + 1)
    $src = Join-Path (Join-Path $canonical '42') $rel
    if ((Get-FileHash $src -Algorithm SHA256).Hash -ne
        (Get-FileHash $f.FullName -Algorithm SHA256).Hash) { $bad++ }
}
if ($bad -gt 0) { throw "$bad file(s) copied incorrectly" }

Write-Host "workshop package: PASS ($($copied.Count) mod files verified byte-for-byte)"
Write-Host "  $target"
