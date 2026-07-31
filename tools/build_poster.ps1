<#
Builds the mod's poster.png and the Workshop preview.png from a real render.

Both images are composed from tools/preview_snow_textures.js output, so what
they show is the actual shipped texture on the actual mesh rather than artwork
promising something the mod does not do.

The source sheet is two rows of 1000x150: vanilla on top, the snowed derivative
below. Both images stack a crop of each, so the before/after is the whole
message and needs no text.

Nothing here is mod logic; it writes two files and exits.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Sheet,
    [Parameter(Mandatory = $true)][string]$Poster,
    [Parameter(Mandatory = $true)][string]$Preview
)

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $Sheet -PathType Leaf)) { throw "sheet not found: $Sheet" }

# Measured off the sheet rather than assumed: it is 1000x300 with a two-pixel
# yellow separator at y=0 and again at y=150, so the rows start at 2 and 152 and
# are 148 tall. Cropping at multiples of 150 lands on the separator and puts a
# yellow line through the middle of the poster.
#
# The weapon occupies x 172..828. This takes the receiver and stock, where the
# effect reads most clearly; the muzzle end is mostly background.
$CropX = 480; $CropW = 360
$RowY = @(2, 152); $RowH = 148

function New-Composite([int]$size, [string]$outPath) {
    $src = [System.Drawing.Bitmap]::new($Sheet)
    try {
        $out = [System.Drawing.Bitmap]::new($size, $size)
        try {
            $g = [System.Drawing.Graphics]::FromImage($out)
            try {
                $g.InterpolationMode =
                    [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.Clear([System.Drawing.Color]::FromArgb(255, 26, 30, 36))

                # Each row keeps the crop's aspect ratio, and the pair is centred
                # vertically with a gap, so neither is stretched.
                $rowW = $size
                $rowH = [int][Math]::Round($RowH * ($size / [double]$CropW))
                $gap = [int]($size * 0.06)
                $top = [int](($size - (2 * $rowH + $gap)) / 2)

                for ($r = 0; $r -lt 2; $r++) {
                    $srcRect = [System.Drawing.Rectangle]::new(
                        $CropX, $RowY[$r], $CropW, $RowH)
                    $dstY = $top + $r * ($rowH + $gap)
                    $dstRect = [System.Drawing.Rectangle]::new(0, $dstY, $rowW, $rowH)
                    $g.DrawImage($src, $dstRect, $srcRect, 'Pixel')
                }
            }
            finally { $g.Dispose() }

            $dir = Split-Path -Parent $outPath
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $out.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Host ("build_poster: {0} ({1}x{1})" -f $outPath, $size)
        }
        finally { $out.Dispose() }
    }
    finally { $src.Dispose() }
}

# 256 is what the in-game mod list shows; the Workshop card wants something
# larger and is not constrained to a square, but square is safe everywhere.
New-Composite 256 $Poster
New-Composite 512 $Preview
