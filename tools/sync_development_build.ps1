param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# The project holds the toolchain and the deliverable side by side. Only `mod`
# is mirrored, zipped and installed: a player never receives the generator, the
# validators, the tests or the frozen recipes.
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'mod')).TrimEnd('\')
$workspaceRoot = [IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $projectRoot))).TrimEnd('\')
# The mod id is the one name Project Zomboid binds saves to, so it is declared
# once and every derived path, ZIP prefix and identity check reads it from here.
# The id in the Assert-ExactPath calls below is deliberately spelled out rather
# than interpolated: it is the guard that catches an accidental edit of this line.
$modId = 'EnvironmentalEffects'
$canonicalRoot = Join-Path $workspaceRoot "outputs\$modId"
$outputsRoot = Join-Path $workspaceRoot 'outputs'
$zipPath = Join-Path $outputsRoot "$modId.zip"
$hashManifestPath = Join-Path $outputsRoot "${modId}_build_hashes.json"
# Project Zomboid keeps local mods under the current user's profile. Deriving the
# path rather than hard-coding one machine's is what lets anyone who clones this
# repository run the toolchain. USERPROFILE is checked explicitly because an
# empty one would silently produce a root-relative path and install somewhere
# unintended, which is exactly what the guards below exist to prevent.
if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    throw 'USERPROFILE is not set; cannot locate the Project Zomboid mods folder'
}
$installRoot = Join-Path $env:USERPROFILE "Zomboid\mods\$modId"
$expectedId = $modId

function Assert-ExactPath([string]$Actual, [string]$Expected, [string]$Label) {
    $actualFull = [IO.Path]::GetFullPath($Actual).TrimEnd('\')
    $expectedFull = [IO.Path]::GetFullPath($Expected).TrimEnd('\')
    if ($actualFull -ne $expectedFull) {
        throw "$Label path mismatch. Expected '$expectedFull', got '$actualFull'"
    }
}

function Assert-NotReparsePoint([string]$Path, [string]$Label) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label must not be a reparse point: $Path"
        }
    }
}

function Assert-ModId([string]$Root, [bool]$AllowAbsent) {
    if (-not (Test-Path -LiteralPath $Root)) {
        if ($AllowAbsent) { return }
        throw "Required mod tree is absent: $Root"
    }
    $modInfo = Join-Path $Root '42\mod.info'
    if (-not (Test-Path -LiteralPath $modInfo -PathType Leaf)) {
        throw "Refusing tree without 42/mod.info: $Root"
    }
    $content = Get-Content -Raw -LiteralPath $modInfo
    if ($content -notmatch "(?m)^id=$([Regex]::Escape($expectedId))\s*$") {
        throw "Refusing tree with a different mod ID: $Root"
    }
}

function Get-RelativePath([string]$Root, [string]$FullName) {
    return $FullName.Substring($Root.TrimEnd('\').Length + 1)
}

# Version-control metadata is not part of the delivered mod. Git marks .git
# hidden on Windows, so a plain Get-ChildItem happens to skip it, but relying on a
# filesystem attribute for a correctness invariant is not acceptable: enumerate
# through here so the exclusion is explicit and survives -Force or a non-hidden
# .git created by another tool.
$script:ExcludedDirectoryNames = @('.git', '.svn', '.hg')

function Test-ExcludedPath([string]$Root, [string]$FullName) {
    $relative = Get-RelativePath $Root $FullName
    foreach ($segment in $relative.Split([IO.Path]::DirectorySeparatorChar)) {
        if ($script:ExcludedDirectoryNames -contains $segment) { return $true }
    }
    return $false
}

function Get-TreeFiles([string]$Root) {
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Where-Object { -not (Test-ExcludedPath $Root $_.FullName) })
}

function Get-TreeDirectories([string]$Root) {
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Directory -Force |
        Where-Object { -not (Test-ExcludedPath $Root $_.FullName) })
}

function Get-TreeRecords([string]$Root) {
    return @(Get-TreeFiles $Root |
        Sort-Object FullName |
        ForEach-Object {
            [ordered]@{
                path = (Get-RelativePath $Root $_.FullName).Replace('\', '/')
                bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
}

function Assert-TreeParity([string]$ExpectedRoot, [string]$ActualRoot, [string]$Label) {
    $expected = Get-TreeRecords $ExpectedRoot
    $actual = Get-TreeRecords $ActualRoot
    if ($expected.Count -ne $actual.Count) {
        throw "$Label file count mismatch: expected $($expected.Count), actual $($actual.Count)"
    }
    $actualByPath = @{}
    foreach ($record in $actual) { $actualByPath[$record.path] = $record.sha256 }
    foreach ($record in $expected) {
        if (-not $actualByPath.ContainsKey($record.path) -or
            $actualByPath[$record.path] -ne $record.sha256) {
            throw "$Label mismatch: $($record.path)"
        }
    }
    Write-Host "$Label`: PASS ($($expected.Count) files)"
}

function Sync-ExactTree([string]$Source, [string]$Destination, [string]$ExpectedDestination) {
    Assert-ExactPath $Destination $ExpectedDestination 'Destination'
    Assert-NotReparsePoint $Destination 'Destination'
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }

    $sourcePaths = @{}
    foreach ($file in Get-TreeFiles $Source) {
        $sourcePaths[(Get-RelativePath $Source $file.FullName)] = $true
    }
    foreach ($file in Get-TreeFiles $Destination) {
        $relative = Get-RelativePath $Destination $file.FullName
        if (-not $sourcePaths.ContainsKey($relative)) {
            $resolved = [IO.Path]::GetFullPath($file.FullName)
            if (-not $resolved.StartsWith($Destination.TrimEnd('\') + '\')) {
                throw "Refusing out-of-tree deletion: $resolved"
            }
            Remove-Item -LiteralPath $resolved -Force
        }
    }
    foreach ($directory in Get-TreeDirectories $Source | Sort-Object FullName) {
        $relative = Get-RelativePath $Source $directory.FullName
        $targetDirectory = Join-Path $Destination $relative
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory | Out-Null
        }
    }
    foreach ($file in Get-TreeFiles $Source) {
        $relative = Get-RelativePath $Source $file.FullName
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $Destination $relative) -Force
    }
    foreach ($directory in Get-TreeDirectories $Destination |
        Sort-Object { $_.FullName.Length } -Descending) {
        if (-not (Get-ChildItem -LiteralPath $directory.FullName -Force)) {
            Remove-Item -LiteralPath $directory.FullName
        }
    }
}

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Executable $($Arguments -join ' ')"
    }
}

# Validation runs once, against the project, because the toolchain only exists
# there. The canonical and installed trees are then proved byte-identical to the
# validated source, which is a stronger statement than re-running the same checks
# against copies of it -- and three times faster.
function Invoke-ProjectValidation([bool]$Regenerate) {
    Push-Location -LiteralPath $projectRoot
    try {
        if ($Regenerate) {
            Invoke-Checked 'powershell.exe' @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', 'tools/replay_snow_textures.ps1')
        }
        Invoke-Checked 'powershell.exe' @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', 'tools/validate_snow_textures.ps1')
        # First, because it is the cheapest and the one whose failure is
        # invisible in game: an unbalanced block does not throw, it stops the
        # mod loading at all. The pure-logic tests below exercise a JavaScript
        # mirror of the simulation, not the shipped Lua, so nothing else here
        # reads those files.
        Invoke-Checked 'node' @('tools/check_lua_blocks.js')
        Invoke-Checked 'node' @('tests/pure_logic_test.js')
        Invoke-Checked 'node' @('tools/validate.js')
    }
    finally {
        Pop-Location
    }
}

function New-SafeZip {
    $temporary = "$zipPath.new"
    if (Test-Path -LiteralPath $temporary) {
        throw "Refusing stale temporary ZIP: $temporary"
    }
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew)
    $archive = [IO.Compression.ZipArchive]::new(
        $stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($file in Get-TreeFiles $canonicalRoot |
            Sort-Object FullName) {
            $relative = (Get-RelativePath $canonicalRoot $file.FullName).Replace('\', '/')
            $entry = $archive.CreateEntry(
                "$modId/$relative",
                [IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            $fileStream = [IO.File]::OpenRead($file.FullName)
            try { $fileStream.CopyTo($entryStream) }
            finally { $fileStream.Dispose(); $entryStream.Dispose() }
        }
    }
    finally {
        $archive.Dispose()
        $stream.Dispose()
    }
    Move-Item -LiteralPath $temporary -Destination $zipPath -Force
}

function Assert-ZipParity {
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        throw "ZIP is absent: $zipPath"
    }
    $expected = Get-TreeRecords $canonicalRoot
    $expectedByPath = @{}
    foreach ($record in $expected) { $expectedByPath[$record.path] = $record.sha256 }
    $seen = @{}
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName
            if ($name.StartsWith('/') -or $name -match '^[A-Za-z]:' -or
                ($name -split '/') -contains '..' -or
                -not $name.StartsWith("$modId/")) {
                throw "Unsafe ZIP entry: $name"
            }
            $relative = $name.Substring("$modId/".Length)
            if (-not $expectedByPath.ContainsKey($relative)) {
                throw "Unexpected ZIP entry: $name"
            }
            $entryStream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hashBytes = $sha.ComputeHash($entryStream) }
            finally { $sha.Dispose(); $entryStream.Dispose() }
            $hash = ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
            if ($hash -ne $expectedByPath[$relative]) {
                throw "ZIP content mismatch: $name"
            }
            $seen[$relative] = $true
        }
    }
    finally {
        $archive.Dispose()
    }
    if ($seen.Count -ne $expected.Count) {
        throw "ZIP file count mismatch: expected $($expected.Count), actual $($seen.Count)"
    }
    Write-Host "zip_parity: PASS ($($seen.Count) entries)"
}

function Get-TreeHash($Records) {
    $text = ($Records | ForEach-Object { "$($_.path)|$($_.sha256)" }) -join "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) }
    finally { $sha.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

# Read from the canonical texture manifest rather than restating hashes here,
# so a texture change touches one file instead of several scripts.
function Get-TextureSummary {
    # The texture manifest is produced evidence about the build, not mod content,
    # so it lives with the toolchain rather than being shipped to players.
    $manifestFile = Join-Path $projectRoot 'assets\snow_texture_manifest.json'
    if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
        throw "Texture manifest is absent: $manifestFile"
    }
    $textureManifest = Get-Content -Raw -LiteralPath $manifestFile | ConvertFrom-Json
    $summary = [ordered]@{}
    foreach ($property in $textureManifest.assets.PSObject.Properties) {
        $summary[$property.Name] = [ordered]@{
            fullType = $property.Value.fullType
            stage = $property.Value.stage
            sourceSha256 = $property.Value.sourceSha256
            meshSha256 = $property.Value.meshSha256
            derivativeSha256 = $property.Value.outputSha256
        }
    }
    if ($summary.Count -eq 0) { throw 'Canonical texture manifest lists no assets' }
    return $summary
}

function Write-BuildHashes {
    $records = Get-TreeRecords $canonicalRoot
    $zipArchive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try { $entryCount = $zipArchive.Entries.Count }
    finally { $zipArchive.Dispose() }
    $manifest = [ordered]@{
        artifact = $modId
        build = 'development-test'
        debug = $true
        target = 'Project Zomboid 42.20 single-player'
        canonicalTreeSha256 = Get-TreeHash $records
        canonicalFileCount = $records.Count
        zip = [ordered]@{
            path = "$modId.zip"
            bytes = (Get-Item -LiteralPath $zipPath).Length
            sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            entryCount = $entryCount
            safeEntries = $true
        }
        textures = Get-TextureSummary
        releaseRightsReview = 'pending'
        files = $records
    }
    [IO.File]::WriteAllText(
        $hashManifestPath,
        ($manifest | ConvertTo-Json -Depth 6) + "`n",
        [Text.UTF8Encoding]::new($false))
}

function Assert-BuildHashes {
    if (-not (Test-Path -LiteralPath $hashManifestPath -PathType Leaf)) {
        throw "Build hash manifest is absent: $hashManifestPath"
    }
    $manifest = Get-Content -Raw -LiteralPath $hashManifestPath | ConvertFrom-Json
    $records = Get-TreeRecords $canonicalRoot
    $treeHash = Get-TreeHash $records
    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($manifest.canonicalTreeSha256 -ne $treeHash -or
        $manifest.canonicalFileCount -ne $records.Count -or
        $manifest.zip.sha256 -ne $zipHash) {
        throw 'External build hash manifest is stale'
    }
    Write-Host "hash_manifest: PASS"
    Write-Host "tree_sha256=$treeHash"
    Write-Host "zip_sha256=$zipHash"
}

Assert-ExactPath $sourceRoot (Join-Path $workspaceRoot 'work\EnvironmentalWeapons\mod') 'Source'
Assert-ExactPath $canonicalRoot (Join-Path $workspaceRoot 'outputs\EnvironmentalEffects') 'Canonical'
Assert-ExactPath $installRoot (Join-Path $env:USERPROFILE 'Zomboid\mods\EnvironmentalEffects') 'Install'
Assert-NotReparsePoint $sourceRoot 'Source'
Assert-NotReparsePoint $canonicalRoot 'Canonical'
Assert-NotReparsePoint $installRoot 'Install'
Assert-ModId $sourceRoot $false
Assert-ModId $canonicalRoot $false
Assert-ModId $installRoot $false

if ($Apply) {
    Write-Host 'mode=APPLY'
    Invoke-ProjectValidation $true
    Sync-ExactTree $sourceRoot $canonicalRoot $canonicalRoot
    Assert-TreeParity $sourceRoot $canonicalRoot 'work_output_parity'
    New-SafeZip
    Assert-ZipParity
    Write-BuildHashes
    Sync-ExactTree $canonicalRoot $installRoot $installRoot
}
else {
    Write-Host 'mode=DRY_RUN'
    Invoke-ProjectValidation $false
}

Assert-TreeParity $sourceRoot $canonicalRoot 'work_output_parity'
Assert-TreeParity $canonicalRoot $installRoot 'output_install_parity'
Assert-ZipParity
Assert-BuildHashes
Write-Host 'continuation_workflow: PASS'

