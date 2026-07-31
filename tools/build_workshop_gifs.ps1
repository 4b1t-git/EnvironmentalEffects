<#
Converts the promo clips to GIFs that fit Steam's limits.

Two outputs, with different jobs and therefore different budgets:

  preview.gif   the Workshop item thumbnail. Steam caps this at 1 MB, and an
                animated preview has to be uploaded through SteamCMD because the
                in-game uploader re-encodes it to a still.
  page.gif      shown in the description body, where the cap is far looser, so
                this one is allowed to keep more detail.

GIF is a 256-colour format with no interframe compression worth the name, so
size is driven by resolution x frames x palette. Rather than guess a setting and
hope, this walks a ladder from best to worst and stops at the first rung that
fits, then reports which rung it used -- so it is obvious how much headroom was
left and what was given up.

Every conversion is two-pass: palettegen builds a palette from the whole clip,
paletteuse applies it with dithering. Single-pass GIF encoding uses a generic
216-colour web palette and looks far worse at the same size.

Nothing here touches the mod. It reads two files and writes two.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PageSource,
    [Parameter(Mandatory = $true)][string]$ThumbSource,
    [Parameter(Mandatory = $true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'

foreach ($f in @($PageSource, $ThumbSource)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "source not found: $f" }
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# width, fps, colours. Ordered best first; the first one that fits wins.
$LADDER = @(
    @{ w = 640; fps = 20; colors = 256 },
    @{ w = 600; fps = 18; colors = 256 },
    @{ w = 560; fps = 15; colors = 224 },
    @{ w = 480; fps = 15; colors = 192 },
    @{ w = 480; fps = 12; colors = 160 },
    @{ w = 420; fps = 12; colors = 128 },
    @{ w = 380; fps = 10; colors = 128 },
    @{ w = 320; fps = 10; colors = 96 },
    @{ w = 280; fps = 8;  colors = 64 }
)

function Convert-ToGif {
    param(
        [string]$Source, [string]$Target, [long]$MaxBytes, [string]$Label,
        # ffmpeg crop expression, e.g. "960:540:560:200". Applied BEFORE the
        # scale, which is the whole point: the clips are 1920x1080 with black
        # letterbox bars and the weapon fills a small part of the frame, so
        # scaling the full frame down to a thumbnail spends most of its pixels
        # on empty snow. Cropping to the action first means the same byte
        # budget buys roughly twice the detail on the thing being advertised.
        [string]$Crop = ""
    )

    Write-Host "=== $Label ==="
    Write-Host ("  source: {0:N1} MB{1}" -f ((Get-Item -LiteralPath $Source).Length / 1MB),
        $(if ($Crop) { "  crop $Crop" } else { "" }))

    $palette = Join-Path $env:TEMP ("ew_palette_" + [Guid]::NewGuid().ToString('N') + ".png")
    try {
        foreach ($rung in $LADDER) {
            $cropStep = if ($Crop) { "crop=$Crop," } else { "" }
            $scale = "fps=$($rung.fps),${cropStep}scale=$($rung.w):-1:flags=lanczos"

            # Pass one: a palette derived from the actual frames.
            & ffmpeg -y -v error -i $Source `
                -vf "$scale,palettegen=max_colors=$($rung.colors):stats_mode=diff" `
                $palette 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "palettegen failed for $Label" }

            # Pass two: apply it. bayer dithering keeps flat areas from banding
            # without the file-size explosion floyd_steinberg causes in GIF,
            # because ordered dithering produces far more repeatable rows.
            & ffmpeg -y -v error -i $Source -i $palette `
                -lavfi "$scale [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=3" `
                -loop 0 $Target 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "paletteuse failed for $Label" }

            $size = (Get-Item -LiteralPath $Target).Length
            $fits = $size -le $MaxBytes
            Write-Host ("  {0}px {1}fps {2}col -> {3:N2} MB {4}" -f `
                $rung.w, $rung.fps, $rung.colors, ($size / 1MB), $(if ($fits) { 'FITS' } else { 'too big' }))
            if ($fits) {
                Write-Host ("  wrote {0} ({1:N0} bytes, {2:N0} under the {3:N0} limit)" -f `
                    $Target, $size, ($MaxBytes - $size), $MaxBytes)
                return
            }
        }
        throw "$Label did not fit under $MaxBytes bytes at any setting on the ladder"
    }
    finally {
        if (Test-Path -LiteralPath $palette) { Remove-Item -LiteralPath $palette -Force }
    }
}

# 1 MB exactly is the documented Workshop preview cap; leave a little room so a
# byte-count difference on Steam's side cannot reject it.
#
# SQUARE, because the Workshop card is square: a 16:9 preview gets letterboxed
# into it with black bars above and below, which is what the first version did.
# Both previews that are known to display correctly -- WarmUp's and the official
# ModTemplate's -- are 256x256.
#
# 760x760 centred on the character at x 935 and the rifle at y 555. A tighter
# square than the full frame height on purpose: fewer pixels to encode buys a
# higher rung on the ladder, so the subject ends up both larger in frame AND
# sharper, rather than trading one for the other.
Convert-ToGif -Source $ThumbSource -Target (Join-Path $OutDir 'preview.gif') `
    -MaxBytes 990KB -Label 'thumbnail (preview.gif)' -Crop '760:760:555:180'

# 2 MB, not 4. The earlier figure was assumed; Steam states the real one when it
# rejects the upload: "Las imágenes de previsualización no pueden superar los
# 2 MB". Images attached to the description body go through the same cap as the
# preview -- looser than the item thumbnail's 1 MB, but nothing like 4.
#
# Only the letterbox comes off; this one keeps the wide shot, since the
# description shows it large.
Convert-ToGif -Source $PageSource -Target (Join-Path $OutDir 'page.gif') `
    -MaxBytes 1900KB -Label 'description (page.gif)' -Crop '1920:1000:0:40'
