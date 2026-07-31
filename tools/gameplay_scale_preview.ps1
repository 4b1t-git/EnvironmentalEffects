<#
Reduces a contact sheet to the size a weapon actually occupies on screen.

This exists because judging texture work on the full-size contact sheet is
misleading: there a rifle is about 1000 px wide, in game it is closer to 200.
Detail that reads clearly at review size averages away to nothing at play size,
which is how a wetness pass that looked correct on the sheet turned out to be
invisible in a screenshot.

Nothing here is mod content; it writes next to the sheet it was given.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Sheet,
    [Parameter(Mandatory = $true)][string]$Output,
    # Roughly the on-screen width of a long gun in Project Zomboid at default zoom.
    [int]$WeaponWidth = 200
)

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $Sheet -PathType Leaf)) {
    throw "contact sheet not found: $Sheet"
}

$source = [System.Drawing.Bitmap]::new($Sheet)
try {
    $scale = $WeaponWidth / [double]$source.Width
    $width = [Math]::Max(1, [int][Math]::Round($source.Width * $scale))
    $height = [Math]::Max(1, [int][Math]::Round($source.Height * $scale))

    $small = [System.Drawing.Bitmap]::new($width, $height)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($small)
        try {
            # Bilinear, not nearest neighbour: the game filters the texture onto a
            # 3D surface, so averaging is what actually happens to fine detail.
            $graphics.InterpolationMode =
                [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
            $graphics.DrawImage($source, 0, 0, $width, $height)
        }
        finally { $graphics.Dispose() }
        $small.Save($Output, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $small.Dispose() }
}
finally { $source.Dispose() }

Write-Host "gameplay_scale_preview: $Sheet -> $Output ($width x $height, weapon ~$WeaponWidth px)"
