<#
Generates every snow texture listed in `tools/snow_assets.json`.

This file holds the mask algorithm. `replay_snow_textures.ps1` only materializes
the frozen bytes this script produced, because PNG encoders are not byte-stable
across machines.

Snow placement is driven by the vanilla mesh, not by uniform texture-space noise:
each texel inherits the interpolated surface normal of the triangle that owns it,
and snow settles only where that normal points up. Roughly 65% of a rifle atlas
maps to the vertical flanks, so a uniform mask spends most of its budget on
surfaces snow cannot hold. A second, much weaker pass dusts sparse flecks on the
flanks so the weapon is not bare when seen edge-on; undersides stay clear.

Usage:
  -FreezeRecipe    write the frozen .seed next to each texture and record hashes
  -WriteManifest   rewrite assets/snow_texture_manifest.json
  -Only <id>       restrict to one asset id
  -PreviewRoot     write to this directory instead of the delivered paths

An asset whose spec has "visuallyVerified": false is generated into the preview
root and never frozen. No cheap geometric test recovers a mesh's up sign
reliably, so a render must be looked at before an asset ships.

Dependencies: Windows PowerShell and System.Drawing. No package install, Node,
Sharp, or Python.
#>
param(
    [string]$Only,
    [string]$PreviewRoot,
    [switch]$FreezeRecipe,
    [switch]$WriteManifest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Drawing

# The project holds the toolchain; `mod` holds only what ships to the game.
# Asset `output` paths are relative to the mod root, `recipe` paths to the
# project root, because a frozen recipe is tooling data and never ships.
$projectRoot = Split-Path -Parent $PSScriptRoot
$modRoot = Join-Path $projectRoot 'mod'
$specPath = Join-Path $PSScriptRoot 'snow_assets.json'
$manifestPath = Join-Path $projectRoot 'assets\snow_texture_manifest.json'

if (-not (Test-Path -LiteralPath $specPath -PathType Leaf)) {
    throw "Asset spec missing: $specPath"
}
$spec = Get-Content -Raw -LiteralPath $specPath | ConvertFrom-Json
if ($spec.schema -ne 1) { throw "Unsupported spec schema: $($spec.schema)" }

Add-Type -TypeDefinition @'
using System;
using System.Globalization;

public static class EwSnowMask
{
    public const int Size = 256;
    const int Super = 4;                 // supersample factor for the normal buffer
    const int SuperSize = Size * Super;

    const uint Seed = 0x45574C31;        // "EWL1"

    // Snow only holds on surfaces pointing up. Partial values between these
    // bounds give the shoulders a whisper instead of a hard decal edge.
    const double UpLow = 0.15;
    const double UpHigh = 0.72;

    // Three octaves, not four. The fourth sat at 3.2 texels per cycle, which is
    // the atlas Nyquist limit, so it aliased into speckle instead of adding shape.
    const int NoiseOctaves = 3;
    const double NoiseFloor = 0.45;
    const double NoiseGain = 1.10;
    const double MaxAlpha = 0.95;
    const double UpFacingThreshold = 0.34;

    // A barrel is a cylinder, and on a cylinder the set of points at a given
    // surface angle is a circle, which unwraps to a STRAIGHT LINE in UV. So a
    // purely smooth up-facing gate cuts the barrel with a ruler-straight snow
    // edge, while irregular geometry like a stock gets a natural boundary for
    // free. Multiplying by noise does not help: it scales the value but leaves
    // the iso-line where it was. The boundary itself has to be perturbed, so
    // jitter is added to the up value BEFORE the gate.
    //
    // Applied to the gate only. Thickness taper and every placement statistic
    // keep using the true surface value, so this changes where snow ends, not
    // what the mask claims about it.
    // Expressed in TEXELS of boundary displacement, not in units of the up value,
    // and multiplied by the local gradient to get there. A fixed value jitter
    // moves the edge by jitter/gradient, so the same number produced 0.7 texels on
    // the Hunting Rifle (gradient 0.296) and 1.7 on the M16 (gradient 0.121) --
    // both invisible, and inconsistent between weapons. Scaling by the gradient
    // makes the displacement the same everywhere and bounds it to a real distance
    // along the surface instead of an arbitrary change in surface angle.
    const double BoundaryRaggedness = 5.0;   // texels, peak displacement
    const double UpJitterScale = 2.2;        // relative to noiseBase
    const uint UpJitterSeed = 0x3C7B;

    // A texel whose steepest owning normal points further down than this is an
    // underside and never receives the flank dusting.
    const double FlankMinRawUp = -0.10;
    const double FlankNoiseScale = 2.6;      // finer than the top drifts
    const uint FlankSeedOffset = 0x5D1F;

    // Near-neutral, faintly cool snow. Saturation stays well under 0.05 so it
    // reads as snow rather than the grey-brown wash an overlay produces.
    const double SnowLuma = 236.0;
    const double SnowR = 0.982, SnowG = 0.993, SnowB = 1.0;
    const int GutterDilation = 2;        // texels of bleed into unused atlas space

    // Thin snow is translucent, thick snow is opaque. At a flat 0.10 the snow was
    // near-flat paint and roughly half the wood grain and machining under a heavy
    // drift was lost, which reads as the weapon losing resolution. At a flat 0.42
    // the substrate ghosted through even deep drifts and the snow looked stained
    // brown. Scaling the bleed down as the drift thickens gives both: grain shows
    // through a dusting, and deep snow gets its detail from crest, shadow and
    // crystals instead of from the surface underneath.
    const double DetailBleed = 0.45;
    const double SubstrateHiding = 0.55;

    // Snow thins as a surface tilts away from horizontal, so alpha scales with
    // upness instead of only being gated by it. Floor keeps thin cover visible.
    const double ThicknessFloor = 0.55;

    // Snow packs into recesses. The vanilla texture already paints crevices
    // darker than their surroundings (bolt, trigger guard, sight base, swivels),
    // so relative local darkness is a serviceable ambient-occlusion proxy.
    const double CreviceBoost = 0.55;
    const double CreviceRange = 26.0;    // luma below local average that counts as full recess
    const int CreviceBlurRadius = 4;

    // Metal conducts cold away faster than wood, so frost takes hold there first.
    // Vanilla metal is dark and desaturated; the stock is saturated brown.
    const double MetalBoost = 0.28;
    const double MetalSaturationCutoff = 0.34;

    // Crevice and metal affinity multiply, and on a revolver cylinder both max
    // out: the flutes read as deep recesses and the steel is dark and
    // desaturated, so that one part reached nearly 2x affinity and swallowed the
    // whole snow budget while the frame and grip stayed bare. The boosts are meant
    // to bias where snow settles first, not to let one component win outright.
    const double AffinityCeiling = 1.35;

    // A drift has a lit crest and drops a short shadow onto the bare surface it
    // sits on. This is what makes snow read as resting ON the weapon rather than
    // painted onto it, and it is the largest gain in apparent detail.
    const double CrestGain = 16.0;       // luma added along the lit crest
    const double CrestEdgeLow = 0.05;    // alpha gradient that starts counting as an edge
    const double CrestEdgeHigh = 0.35;
    const double ShadowStrength = 0.20;  // fraction of luma removed at the foot
    const double ShadowCool = 0.06;      // shadow leans blue: damp snow, not grey dirt
    const double ShadowAlphaCeiling = 0.12;  // only bare-ish texels take a shadow
    const double ShadowNeighbourFloor = 0.55;

    // Crystals catching light. Kept very sparse on purpose: a single-texel
    // highlight is sub-pixel at gameplay zoom and shimmers if overused.
    const double SparkleDensity = 0.012;
    const double SparkleGain = 15.0;
    const double SparkleNoiseScale = 5.5;
    const uint SparkleSeedOffset = 0x9E37;

    // Reset per asset by ParseMesh; the batch loop is strictly sequential.
    static double[][] _v, _n, _t;
    static int[][] _f;

    static string Inv(double value, int decimals)
    {
        return value.ToString("F" + decimals, CultureInfo.InvariantCulture);
    }

    static double NextNumber(string s, ref int i)
    {
        while (i < s.Length)
        {
            char c = s[i];
            bool starts = char.IsDigit(c)
                || (c == '-' && i + 1 < s.Length && (char.IsDigit(s[i + 1]) || s[i + 1] == '.'))
                || (c == '.' && i + 1 < s.Length && char.IsDigit(s[i + 1]));
            if (starts) break;
            i++;
        }
        if (i >= s.Length) throw new Exception("unexpected end of mesh while reading a number");
        int start = i;
        if (s[i] == '-') i++;
        while (i < s.Length)
        {
            char c = s[i];
            if (char.IsDigit(c) || c == '.') { i++; continue; }
            if ((c == 'e' || c == 'E') && i + 1 < s.Length) { i++; continue; }
            if ((c == '-' || c == '+') && (s[i - 1] == 'e' || s[i - 1] == 'E')) { i++; continue; }
            break;
        }
        return double.Parse(s.Substring(start, i - start), CultureInfo.InvariantCulture);
    }

    static double[][] ReadTuples(string s, ref int i, int count, int arity)
    {
        var outv = new double[count][];
        for (int k = 0; k < count; k++)
        {
            var tuple = new double[arity];
            for (int a = 0; a < arity; a++) tuple[a] = NextNumber(s, ref i);
            outv[k] = tuple;
        }
        return outv;
    }

    static int[][] ReadFaces(string s, ref int i, int count)
    {
        var outv = new int[count][];
        for (int k = 0; k < count; k++)
        {
            int n = (int)NextNumber(s, ref i);
            if (n < 3 || n > 32) throw new Exception("implausible face arity " + n);
            var idx = new int[n];
            for (int a = 0; a < n; a++) idx[a] = (int)NextNumber(s, ref i);
            outv[k] = idx;
        }
        return outv;
    }

    static int BlockBody(string s, string marker, int from)
    {
        int at = s.IndexOf(marker, from, StringComparison.Ordinal);
        if (at < 0) throw new Exception("mesh block not found: " + marker);
        int brace = s.IndexOf('{', at);
        if (brace < 0) throw new Exception("unterminated mesh block: " + marker);
        return brace + 1;                // skip digits inside names such as "c1"
    }

    // A .x file opens with `template <Name> { ... }` declarations that reuse the
    // data block names and carry GUIDs full of hex digits. Parsing those as
    // geometry yields nonsense, so find the first non-template occurrence.
    static int FindDataBlock(string s, string marker)
    {
        int at = 0;
        while (true)
        {
            at = s.IndexOf(marker, at, StringComparison.Ordinal);
            if (at < 0) throw new Exception("data block not found: " + marker);
            int back = at - 1;
            while (back >= 0 && char.IsWhiteSpace(s[back])) back--;
            bool isTemplate = back >= 7
                && string.Compare(s, back - 7, "template", 0, 8, StringComparison.Ordinal) == 0;
            if (!isTemplate) return at;
            at += marker.Length;
        }
    }

    public static string ParseMesh(string text)
    {
        int frameAt = FindDataBlock(text, "Frame ");

        int i = BlockBody(text, "Mesh ", frameAt);
        int vertexCount = (int)NextNumber(text, ref i);
        _v = ReadTuples(text, ref i, vertexCount, 3);
        int faceCount = (int)NextNumber(text, ref i);
        _f = ReadFaces(text, ref i, faceCount);

        i = BlockBody(text, "MeshNormals", frameAt);
        int normalCount = (int)NextNumber(text, ref i);
        _n = ReadTuples(text, ref i, normalCount, 3);
        int normalFaceCount = (int)NextNumber(text, ref i);
        var normalFaces = ReadFaces(text, ref i, normalFaceCount);

        i = BlockBody(text, "MeshTextureCoords", frameAt);
        int uvCount = (int)NextNumber(text, ref i);
        _t = ReadTuples(text, ref i, uvCount, 2);

        // This generator indexes normals and UVs with the vertex index, which is
        // only valid for a 1:1 indexed mesh. Prove it instead of assuming it.
        if (normalCount != vertexCount || uvCount != vertexCount)
            throw new Exception("mesh is not 1:1 indexed: verts=" + vertexCount
                + " normals=" + normalCount + " uvs=" + uvCount);
        if (normalFaceCount != faceCount)
            throw new Exception("normal face count differs from vertex face count");
        for (int k = 0; k < faceCount; k++)
        {
            if (normalFaces[k].Length != _f[k].Length)
                throw new Exception("normal face arity differs at face " + k);
            for (int a = 0; a < _f[k].Length; a++)
                if (normalFaces[k][a] != _f[k][a])
                    throw new Exception("normal indices differ from vertex indices at face " + k);
        }

        // Catch a misaligned parse loudly rather than emitting a nonsense mask.
        foreach (var v in _v)
            for (int a = 0; a < 3; a++)
                if (double.IsNaN(v[a]) || Math.Abs(v[a]) > 100.0)
                    throw new Exception("implausible vertex coordinate " + v[a]);
        foreach (var t in _t)
            for (int a = 0; a < 2; a++)
                if (double.IsNaN(t[a]) || t[a] < -0.5 || t[a] > 1.5)
                    throw new Exception("texture coordinate outside the atlas: " + t[a]);
        foreach (var face in _f)
            foreach (int idx in face)
                if (idx < 0 || idx >= vertexCount)
                    throw new Exception("face references vertex " + idx + " of " + vertexCount);

        return "vertices=" + vertexCount + " faces=" + faceCount;
    }

    // Recovers which way is DOWN from the geometry, and it works on handguns as
    // well as long guns.
    //
    // A weapon's grip or stock is the largest mass sticking off the bore line, and
    // it points down: a pistol's grip hangs below the slide, a rifle's stock sits
    // below the barrel. So take the bore as the median height through the middle
    // of the length axis, measure how far mass reaches either way, and the bigger
    // reach is the grip side.
    //
    // Measured on ten vanilla meshes it splits cleanly: all six handguns put the
    // grip at +Z (so +Z is down for them), every long gun puts it at -Z. Two
    // earlier heuristics -- "up-facing area exceeds down-facing area" and "centroid
    // below mid-height" -- failed on exactly these cases, which is why the axis was
    // being confirmed by eye. This one is checked against the spec on every run.
    public static int InferUpSign(string meshText)
    {
        ParseMesh(meshText);
        double loY = double.MaxValue, hiY = double.MinValue;
        foreach (var v in _v) { if (v[1] < loY) loY = v[1]; if (v[1] > hiY) hiY = v[1]; }

        var middle = new System.Collections.Generic.List<double>();
        foreach (var v in _v)
        {
            double t = (v[1] - loY) / (hiY - loY);
            if (t > 0.35 && t < 0.75) middle.Add(v[2]);
        }
        if (middle.Count == 0) return 0;
        middle.Sort();
        double bore = middle[middle.Count / 2];

        double reachPositive = 0, reachNegative = 0;
        foreach (var v in _v)
        {
            double d = v[2] - bore;
            if (d > reachPositive) reachPositive = d;
            if (-d > reachNegative) reachNegative = -d;
        }
        // Too close to call: refuse rather than guess.
        double ratio = Math.Max(reachPositive, reachNegative)
            / Math.Max(1e-9, Math.Min(reachPositive, reachNegative));
        if (ratio < 1.25) return 0;
        return reachPositive > reachNegative ? -1 : +1;   // grip side is down
    }

    // Reports the geometry an operator needs in order to sanity-check the axis
    // choice for a new mesh.
    public static string DescribeAxes(string meshText)
    {
        ParseMesh(meshText);
        var lo = new double[] { double.MaxValue, double.MaxValue, double.MaxValue };
        var hi = new double[] { double.MinValue, double.MinValue, double.MinValue };
        foreach (var v in _v)
            for (int k = 0; k < 3; k++)
            {
                if (v[k] < lo[k]) lo[k] = v[k];
                if (v[k] > hi[k]) hi[k] = v[k];
            }
        int lengthAxis = 0;
        for (int k = 1; k < 3; k++)
            if ((hi[k] - lo[k]) > (hi[lengthAxis] - lo[lengthAxis])) lengthAxis = k;
        return "extentX=" + Inv(hi[0] - lo[0], 4)
            + ";extentY=" + Inv(hi[1] - lo[1], 4)
            + ";extentZ=" + Inv(hi[2] - lo[2], 4)
            + ";longestAxis=" + "XYZ"[lengthAxis];
    }

    static double SmoothStep(double x, double lo, double hi)
    {
        if (hi <= lo) return x >= hi ? 1.0 : 0.0;
        double t = (x - lo) / (hi - lo);
        if (t <= 0) return 0.0;
        if (t >= 1) return 1.0;
        return t * t * (3.0 - 2.0 * t);
    }

    static double Hash2(int x, int y, uint seed)
    {
        uint h = (uint)(x * 374761393) + (uint)(y * 668265263) + seed;
        h = (h ^ (h >> 13)) * 1274126177u;
        h ^= h >> 16;
        return (h & 0xFFFFFF) / (double)0xFFFFFF;
    }

    static double ValueNoise(double x, double y, uint seed)
    {
        int xi = (int)Math.Floor(x), yi = (int)Math.Floor(y);
        double tx = x - xi, ty = y - yi;
        double sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
        double a = Hash2(xi, yi, seed), b = Hash2(xi + 1, yi, seed);
        double c = Hash2(xi, yi + 1, seed), d = Hash2(xi + 1, yi + 1, seed);
        double top = a + (b - a) * sx;
        double bottom = c + (d - c) * sx;
        return top + (bottom - top) * sy;
    }

    static double Fbm(double x, double y, uint seedOffset)
    {
        // frequency ratio 2.07 rather than 2.0 so octaves do not align on a grid
        double sum = 0, amp = 1, norm = 0, freq = 1;
        for (int o = 0; o < NoiseOctaves; o++)
        {
            sum += amp * ValueNoise(x * freq, y * freq, Seed + seedOffset + (uint)(o * 7919));
            norm += amp;
            amp *= 0.5;
            freq *= 2.07;
        }
        return sum / norm;
    }

    static double[] ProjectUv(int index, bool flipV)
    {
        double u = _t[index][0];
        double v = flipV ? 1.0 - _t[index][1] : _t[index][1];
        return new double[] { u * SuperSize, v * SuperSize };
    }

    // Rasterizes the mesh into a per-texel "how far up does this surface face"
    // buffer, the raw signed dot, and a mask of atlas space triangles own.
    static void BuildUpness(int upAxis, int upSign, bool flipV,
        out double[] upness, out double[] used, out double[] rawUp)
    {
        var superUp = new float[SuperSize * SuperSize];
        var superRaw = new float[SuperSize * SuperSize];
        var superUsed = new bool[SuperSize * SuperSize];
        for (int o = 0; o < superRaw.Length; o++) superRaw[o] = -2f;

        foreach (var face in _f)
        {
            for (int t = 1; t + 1 < face.Length; t++)
            {
                int i0 = face[0], i1 = face[t], i2 = face[t + 1];
                double[] p0 = ProjectUv(i0, flipV), p1 = ProjectUv(i1, flipV), p2 = ProjectUv(i2, flipV);

                double det = (p1[0] - p0[0]) * (p2[1] - p0[1]) - (p2[0] - p0[0]) * (p1[1] - p0[1]);
                if (Math.Abs(det) < 1e-12) continue;

                int minX = (int)Math.Max(0, Math.Floor(Math.Min(p0[0], Math.Min(p1[0], p2[0]))));
                int maxX = (int)Math.Min(SuperSize - 1, Math.Ceiling(Math.Max(p0[0], Math.Max(p1[0], p2[0]))));
                int minY = (int)Math.Max(0, Math.Floor(Math.Min(p0[1], Math.Min(p1[1], p2[1]))));
                int maxY = (int)Math.Min(SuperSize - 1, Math.Ceiling(Math.Max(p0[1], Math.Max(p1[1], p2[1]))));

                for (int y = minY; y <= maxY; y++)
                {
                    for (int x = minX; x <= maxX; x++)
                    {
                        double px = x + 0.5, py = y + 0.5;
                        double w0 = ((p1[0] - px) * (p2[1] - py) - (p2[0] - px) * (p1[1] - py)) / det;
                        double w1 = ((p2[0] - px) * (p0[1] - py) - (p0[0] - px) * (p2[1] - py)) / det;
                        double w2 = 1.0 - w0 - w1;
                        if (w0 < 0 || w1 < 0 || w2 < 0) continue;

                        double nx = w0 * _n[i0][0] + w1 * _n[i1][0] + w2 * _n[i2][0];
                        double ny = w0 * _n[i0][1] + w1 * _n[i1][1] + w2 * _n[i2][1];
                        double nz = w0 * _n[i0][2] + w1 * _n[i1][2] + w2 * _n[i2][2];
                        double len = Math.Sqrt(nx * nx + ny * ny + nz * nz);
                        if (len < 1e-9) continue;
                        double component = upAxis == 0 ? nx : (upAxis == 1 ? ny : nz);
                        double up = upSign * component / len;

                        int o = y * SuperSize + x;
                        superUsed[o] = true;
                        // Overlapping islands: the more upward-facing owner wins.
                        float value = (float)SmoothStep(up, UpLow, UpHigh);
                        if (value > superUp[o]) superUp[o] = value;
                        if ((float)up > superRaw[o]) superRaw[o] = (float)up;
                    }
                }
            }
        }

        upness = new double[Size * Size];
        used = new double[Size * Size];
        rawUp = new double[Size * Size];
        for (int y = 0; y < Size; y++)
        {
            for (int x = 0; x < Size; x++)
            {
                double sum = 0, raw = -2;
                int cover = 0;
                for (int sy = 0; sy < Super; sy++)
                {
                    for (int sx = 0; sx < Super; sx++)
                    {
                        int o = (y * Super + sy) * SuperSize + (x * Super + sx);
                        if (!superUsed[o]) continue;
                        sum += superUp[o];
                        cover++;
                        if (superRaw[o] > raw) raw = superRaw[o];
                    }
                }
                int target = y * Size + x;
                // Normalize by the subsamples a triangle actually owns. Dividing by
                // the full subsample count diluted every texel sitting on a UV
                // island edge: 11.5% of owned texels on the Hunting Rifle, by up to
                // 16x, which pushed them under the up-facing threshold and made
                // snow visibly retreat along the seams.
                upness[target] = cover > 0 ? sum / cover : 0;
                used[target] = cover / (double)(Super * Super);
                rawUp[target] = cover > 0 ? raw : -2;   // -2 marks unowned space
            }
        }
    }

    // Per-texel description of the vanilla surface, derived from the source pixels
    // alone: how deep a recess a texel sits in, and how metallic it looks.
    public class Surface
    {
        public double[] Luma;
        public double[] Crevice;
        public double[] Metalness;
    }

    // `used` is required: the local average a texel is compared against must be
    // built from surface only. Atlas space no triangle owns holds unrelated pixels
    // (on the Hunting Rifle they average luma 69 against the surface's 62), so
    // including them inflated the apparent recess depth within the blur radius of
    // every UV seam and packed snow along the seams for no physical reason.
    static Surface AnalyseSurface(byte[] bgra, double[] used)
    {
        var luma = new double[Size * Size];
        var metalness = new double[Size * Size];
        for (int o = 0; o < Size * Size; o++)
        {
            int b = bgra[o * 4], g = bgra[o * 4 + 1], r = bgra[o * 4 + 2];
            luma[o] = 0.299 * r + 0.587 * g + 0.114 * b;
            int mx = Math.Max(r, Math.Max(g, b));
            int mn = Math.Min(r, Math.Min(g, b));
            double sat = mx > 0 ? (mx - mn) / (double)mx : 0;
            double t = sat / MetalSaturationCutoff;
            if (t > 1) t = 1;
            metalness[o] = 1.0 - t;
        }

        // Separable box blur over owned texels only. Weight and value are carried
        // separately so the second pass can still divide by the true owned count.
        var horizontalValue = new double[Size * Size];
        var horizontalWeight = new double[Size * Size];
        for (int y = 0; y < Size; y++)
        {
            for (int x = 0; x < Size; x++)
            {
                double sum = 0, weight = 0;
                for (int dx = -CreviceBlurRadius; dx <= CreviceBlurRadius; dx++)
                {
                    int nx = x + dx;
                    if (nx < 0 || nx >= Size) continue;
                    int n = y * Size + nx;
                    if (used[n] <= 0) continue;
                    sum += luma[n];
                    weight += 1;
                }
                horizontalValue[y * Size + x] = sum;
                horizontalWeight[y * Size + x] = weight;
            }
        }

        var crevice = new double[Size * Size];
        for (int y = 0; y < Size; y++)
        {
            for (int x = 0; x < Size; x++)
            {
                int o = y * Size + x;
                if (used[o] <= 0) continue;   // gutter has no recess to speak of
                double sum = 0, weight = 0;
                for (int dy = -CreviceBlurRadius; dy <= CreviceBlurRadius; dy++)
                {
                    int ny = y + dy;
                    if (ny < 0 || ny >= Size) continue;
                    sum += horizontalValue[ny * Size + x];
                    weight += horizontalWeight[ny * Size + x];
                }
                if (weight <= 0) continue;
                double depth = ((sum / weight) - luma[o]) / CreviceRange;
                if (depth < 0) depth = 0;
                if (depth > 1) depth = 1;
                crevice[o] = depth;
            }
        }

        return new Surface { Luma = luma, Crevice = crevice, Metalness = metalness };
    }

    public class SnowMask
    {
        public double[] Alpha;
        public double[] Upness;
        public double[] Used;
        public string MeshInfo;
        public double Threshold;
        public int UpFacingTexels;
        public double FlankThreshold;
        public int FlankTexels;
    }

    // The surface analysis needs the coverage mask, and the mask needs the mesh, so
    // the order is fixed: parse, rasterize coverage, analyse surface, then build.
    static SnowMask BuildMask(string meshText, byte[] bgra, out Surface surface,
        int upAxis, int upSign, bool flipV,
        double targetUpCoverage, double noiseBase, double edgeSoftness,
        double flankCoverage, double flankMaxAlpha)
    {
        string meshInfo = ParseMesh(meshText);
        double[] upness, used, rawUp;
        BuildUpness(upAxis, upSign, flipV, out upness, out used, out rawUp);
        surface = AnalyseSurface(bgra, used);

        var field = new double[Size * Size];
        int upFacing = 0;
        for (int y = 0; y < Size; y++)
        {
            for (int x = 0; x < Size; x++)
            {
                int o = y * Size + x;
                if (upness[o] >= UpFacingThreshold) upFacing++;
                double n = Fbm((x + 0.5) / Size * noiseBase, (y + 0.5) / Size * noiseBase, 0);

                // Ragged the boundary, so a cylindrical barrel does not get a
                // straight snow line. Stage-independent, so nesting still holds.
                //
                // The local gradient converts the requested texel displacement
                // into the equivalent change in up value, so the edge wanders by
                // the same distance no matter how sharply the surface turns.
                int left = x > 0 ? o - 1 : o;
                int right = x < Size - 1 ? o + 1 : o;
                int above = y > 0 ? o - Size : o;
                int below = y < Size - 1 ? o + Size : o;
                double gx = (upness[right] - upness[left]) / 2.0;
                double gy = (upness[below] - upness[above]) / 2.0;
                double gradient = Math.Sqrt(gx * gx + gy * gy);

                double jitter = (Fbm((x + 0.5) / Size * noiseBase * UpJitterScale,
                    (y + 0.5) / Size * noiseBase * UpJitterScale, UpJitterSeed) - 0.5)
                    * 2.0 * BoundaryRaggedness * gradient;
                double gatedUp = upness[o] + jitter;
                if (gatedUp < 0) gatedUp = 0;
                if (gatedUp > 1) gatedUp = 1;

                // Recesses and cold metal reach the threshold sooner, so snow takes
                // hold in the crevices and on the barrel before the bare stock does.
                double affinity = (1.0 + CreviceBoost * surface.Crevice[o])
                    * (1.0 + MetalBoost * surface.Metalness[o]);
                if (affinity > AffinityCeiling) affinity = AffinityCeiling;
                field[o] = gatedUp * (NoiseFloor + NoiseGain * n) * affinity;
            }
        }
        if (upFacing == 0) throw new Exception("no up-facing texels found; the axis is wrong");

        // Bisect the drift threshold so coverage of up-facing area is reproducible
        // rather than a hand-tuned constant that drifts with any parameter change.
        double lo = 0.0, hi = 2.0, threshold = 0.5;
        for (int iter = 0; iter < 60; iter++)
        {
            threshold = 0.5 * (lo + hi);
            int hit = 0;
            for (int o = 0; o < field.Length; o++)
            {
                if (upness[o] < UpFacingThreshold) continue;
                if (SmoothStep(field[o], threshold, threshold + edgeSoftness) > 0.5) hit++;
            }
            if ((double)hit / upFacing > targetUpCoverage) lo = threshold; else hi = threshold;
        }

        var alpha = new double[Size * Size];
        for (int o = 0; o < field.Length; o++)
        {
            if (used[o] <= 0) continue;
            // Thickness follows inclination: a drift on a tilting surface is
            // thinner than the same drift on a level one, so it tapers around the
            // barrel's curve instead of cutting off in a hard band.
            double thickness = ThicknessFloor + (1.0 - ThicknessFloor) * upness[o];
            alpha[o] = MaxAlpha * thickness
                * SmoothStep(field[o], threshold, threshold + edgeSoftness);
        }

        // Flank dusting: fine flecks on the near-vertical sides, so the weapon is
        // not bare seen edge-on. Its own field, threshold and alpha cap, so later
        // stages can grow top drifts and flank cover apart.
        var flankField = new double[Size * Size];
        int flankTexels = 0;
        for (int y = 0; y < Size; y++)
        {
            for (int x = 0; x < Size; x++)
            {
                int o = y * Size + x;
                flankField[o] = -1;
                if (used[o] <= 0) continue;
                if (upness[o] >= UpFacingThreshold) continue;   // already drifted
                if (rawUp[o] < FlankMinRawUp) continue;         // underside stays clear
                flankTexels++;
                flankField[o] = Fbm((x + 0.5) / Size * noiseBase * FlankNoiseScale,
                    (y + 0.5) / Size * noiseBase * FlankNoiseScale, FlankSeedOffset);
            }
        }

        double flankThreshold = 1.0;
        if (flankTexels > 0 && flankCoverage > 0)
        {
            double flo = 0.0, fhi = 1.0;
            for (int iter = 0; iter < 60; iter++)
            {
                flankThreshold = 0.5 * (flo + fhi);
                int hit = 0;
                for (int o = 0; o < flankField.Length; o++)
                {
                    if (flankField[o] < 0) continue;
                    if (SmoothStep(flankField[o], flankThreshold, flankThreshold + edgeSoftness) > 0.5) hit++;
                }
                if ((double)hit / flankTexels > flankCoverage) flo = flankThreshold; else fhi = flankThreshold;
            }
            for (int o = 0; o < flankField.Length; o++)
            {
                if (flankField[o] < 0) continue;
                double dust = flankMaxAlpha
                    * SmoothStep(flankField[o], flankThreshold, flankThreshold + edgeSoftness);
                if (dust > alpha[o]) alpha[o] = dust;
            }
        }

        // Bleed into atlas space no triangle owns, so bilinear filtering at island
        // borders cannot sample bare wood and ring the snow with a dark halo.
        //
        // Single pass, sampling only texels a triangle owns, within a fixed
        // radius. An earlier version iterated passes and skipped any texel whose
        // alpha was already above zero, which chained gutter onto gutter and made
        // the result path-dependent: a minuscule, invisible alpha was enough to
        // block the fill, and which texels had one changed with the stage. Snow
        // then vanished from a few seam texels as a later stage was generated.
        // Reading owned texels only makes this monotone in the owned mask.
        var dilated = (double[])alpha.Clone();
        for (int y = 0; y < Size; y++)
        {
            for (int x = 0; x < Size; x++)
            {
                int o = y * Size + x;
                if (used[o] > 0) continue;
                double best = 0;
                for (int dy = -GutterDilation; dy <= GutterDilation; dy++)
                {
                    for (int dx = -GutterDilation; dx <= GutterDilation; dx++)
                    {
                        int nx2 = x + dx, ny2 = y + dy;
                        if (nx2 < 0 || ny2 < 0 || nx2 >= Size || ny2 >= Size) continue;
                        int n = ny2 * Size + nx2;
                        if (used[n] <= 0) continue;
                        if (alpha[n] > best) best = alpha[n];
                    }
                }
                if (best > dilated[o]) dilated[o] = best;
            }
        }
        alpha = dilated;

        return new SnowMask {
            Alpha = alpha,
            Upness = upness,
            Used = used,
            MeshInfo = meshInfo,
            Threshold = threshold,
            UpFacingTexels = upFacing,
            FlankThreshold = flankThreshold,
            FlankTexels = flankTexels
        };
    }

    // Composites the snow over the vanilla pixels. bgra is modified in place.
    public static string Composite(byte[] bgra, string meshText,
        int upAxis, int upSign, bool flipV,
        double targetUpCoverage, double noiseBase, double edgeSoftness,
        double flankCoverage, double flankMaxAlpha)
    {
        Surface surface;
        SnowMask mask = BuildMask(meshText, bgra, out surface, upAxis, upSign, flipV,
            targetUpCoverage, noiseBase, edgeSoftness, flankCoverage, flankMaxAlpha);
        double[] alpha = mask.Alpha;
        double[] upness = mask.Upness;
        double[] used = mask.Used;

        double lumaSum = 0;
        for (int o = 0; o < Size * Size; o++) lumaSum += surface.Luma[o];
        double meanLuma = lumaSum / (Size * Size);

        // Sparkle threshold is calibrated, not guessed: an fbm sum rarely reaches
        // a hand-picked high value, so a literal cutoff silently produced almost
        // no crystals at all.
        var sparkleField = new double[Size * Size];
        int sparkleEligible = 0;
        for (int o = 0; o < Size * Size; o++)
        {
            sparkleField[o] = -1;
            if (alpha[o] < 0.6) continue;
            sparkleEligible++;
            sparkleField[o] = Fbm((o % Size + 0.5) / Size * noiseBase * SparkleNoiseScale,
                (o / Size + 0.5) / Size * noiseBase * SparkleNoiseScale, SparkleSeedOffset);
        }
        double sparkleThreshold = 2.0;
        if (sparkleEligible > 0 && SparkleDensity > 0)
        {
            double slo = 0.0, shi = 1.0;
            for (int iter = 0; iter < 50; iter++)
            {
                sparkleThreshold = 0.5 * (slo + shi);
                int hit = 0;
                for (int o = 0; o < sparkleField.Length; o++)
                {
                    if (sparkleField[o] < 0) continue;
                    if (sparkleField[o] >= sparkleThreshold) hit++;
                }
                if ((double)hit / sparkleEligible > SparkleDensity) slo = sparkleThreshold;
                else shi = sparkleThreshold;
            }
        }

        // Gradient magnitude of the alpha field locates drift borders, and the
        // strongest neighbour tells a bare texel whether a drift looms over it.
        var edgeStrength = new double[Size * Size];
        var neighbourPeak = new double[Size * Size];
        for (int y = 0; y < Size; y++)
        {
            for (int x = 0; x < Size; x++)
            {
                int o = y * Size + x;
                int left = x > 0 ? o - 1 : o;
                int right = x < Size - 1 ? o + 1 : o;
                int up = y > 0 ? o - Size : o;
                int down = y < Size - 1 ? o + Size : o;
                double gx = alpha[right] - alpha[left];
                double gy = alpha[down] - alpha[up];
                edgeStrength[o] = Math.Sqrt(gx * gx + gy * gy);
                double peak = 0;
                for (int dy = -1; dy <= 1; dy++)
                {
                    for (int dx = -1; dx <= 1; dx++)
                    {
                        int nx = x + dx, ny = y + dy;
                        if (nx < 0 || ny < 0 || nx >= Size || ny >= Size) continue;
                        double candidate = alpha[ny * Size + nx];
                        if (candidate > peak) peak = candidate;
                    }
                }
                neighbourPeak[o] = peak;
            }
        }

        int changed = 0;
        double snowMass = 0, snowMassUp = 0, snowMassFlank = 0;
        // Brightness and neutrality are measured on SOLID snow only. Soft edges
        // and a faint dusting are wanted, but averaging them in hides whether
        // the snow that is actually there reads at gameplay zoom.
        double coreLumaSum = 0, coreSatSum = 0;
        int coreTexels = 0;
        int shadowTexels = 0, sparkleTexels = 0;
        const double SolidAlpha = 0.75;

        for (int o = 0; o < Size * Size; o++)
        {
            double a = alpha[o];
            int b = bgra[o * 4], g = bgra[o * 4 + 1], r = bgra[o * 4 + 2];

            if (a <= 0)
            {
                // Bare texel under the lip of a drift: take a short, faintly cool
                // shadow. This is what makes the snow read as resting on the
                // weapon rather than being painted onto it.
                if (used[o] > 0 && neighbourPeak[o] >= ShadowNeighbourFloor)
                {
                    double shade = 1.0 - ShadowStrength;
                    int dr = (int)Math.Round(r * shade * (1.0 - ShadowCool));
                    int dg = (int)Math.Round(g * shade);
                    int db = (int)Math.Round(b * shade * (1.0 + ShadowCool));
                    byte nb2 = (byte)Math.Min(255, Math.Max(0, db));
                    byte ng2 = (byte)Math.Min(255, Math.Max(0, dg));
                    byte nr2 = (byte)Math.Min(255, Math.Max(0, dr));
                    // Shadow texels are modified texels: count them, or the
                    // recorded changedTexels will not match an independent
                    // pixel-diff measurement.
                    if (nr2 != r || ng2 != g || nb2 != b) changed++;
                    bgra[o * 4] = nb2;
                    bgra[o * 4 + 1] = ng2;
                    bgra[o * 4 + 2] = nr2;
                    shadowTexels++;
                }
                continue;
            }

            double srcLuma = surface.Luma[o];

            // Let source contrast ghost through so wood grain and machining stay
            // legible instead of turning into flat white paint, but fade that out
            // as the drift thickens: deep snow hides what it covers.
            double bleed = DetailBleed * (1.0 - SubstrateHiding * a);
            double luma = SnowLuma + (srcLuma - meanLuma) * bleed;

            // Lit crest along the drift border.
            double crest = SmoothStep(edgeStrength[o], CrestEdgeLow, CrestEdgeHigh);
            luma += CrestGain * crest * a;

            // Crystals catching light. Interior only, and deliberately sparse.
            if (sparkleField[o] >= 0 && sparkleField[o] >= sparkleThreshold)
            {
                luma += SparkleGain;
                sparkleTexels++;
            }

            if (luma < 196) luma = 196;
            if (luma > 252) luma = 252;

            double sr = luma * SnowR, sg = luma * SnowG, sb = luma * SnowB;
            int nr = (int)Math.Round(r * (1 - a) + sr * a);
            int ng = (int)Math.Round(g * (1 - a) + sg * a);
            int nb = (int)Math.Round(b * (1 - a) + sb * a);
            if (nr > 255) nr = 255; if (ng > 255) ng = 255; if (nb > 255) nb = 255;
            if (nr < 0) nr = 0; if (ng < 0) ng = 0; if (nb < 0) nb = 0;

            if (nr != r || ng != g || nb != b) changed++;
            if (a >= SolidAlpha)
            {
                coreLumaSum += 0.299 * nr + 0.587 * ng + 0.114 * nb;
                int mx = Math.Max(nr, Math.Max(ng, nb));
                int mn = Math.Min(nr, Math.Min(ng, nb));
                if (mx > 0) coreSatSum += (mx - mn) / (double)mx;
                coreTexels++;
            }
            // Gutter texels are filtering padding, not surface. Counting their
            // mass as "flank" would make placement statistics depend on how far
            // the bleed reaches, which says nothing about where snow settled.
            if (used[o] > 0)
            {
                snowMass += a;
                if (upness[o] >= UpFacingThreshold) snowMassUp += a; else snowMassFlank += a;
            }

            bgra[o * 4] = (byte)nb;
            bgra[o * 4 + 1] = (byte)ng;
            bgra[o * 4 + 2] = (byte)nr;
        }
        // Source alpha is preserved, never overwritten. Most vanilla firearm
        // textures are RGB, where LockBits reports alpha 255 anyway, but
        // PumpAction_Shotgun and M9_Pistol are RGBA with a few hundred
        // semi-transparent edge texels. Forcing those to 255 hardened antialiased
        // edges and made the generator's changed-texel count disagree with an
        // independent measurement against the source.
        //
        // Only the colour channels above are written, so alpha already carries
        // through untouched; this loop exists to count what is there.
        int semiTransparent = 0;
        for (int o = 0; o < Size * Size; o++)
        {
            if (bgra[o * 4 + 3] != 255) semiTransparent++;
        }

        double upShare = snowMass > 0 ? snowMassUp / snowMass : 0;
        double coreLuma = coreTexels > 0 ? coreLumaSum / coreTexels : 0;
        double coreSat = coreTexels > 0 ? coreSatSum / coreTexels : 0;

        // Snow per eligible texel, up-facing versus flank. This is the invariant
        // that survives a five-stage progression: at the heaviest stage a buried
        // weapon legitimately carries a lot of flank mass, so a fixed share floor
        // would confuse "covered" with "misplaced". Density does not.
        double upDensity = mask.UpFacingTexels > 0 ? snowMassUp / mask.UpFacingTexels : 0;
        double flankDensity = mask.FlankTexels > 0 ? snowMassFlank / mask.FlankTexels : 0;
        double densityRatio = flankDensity > 0 ? upDensity / flankDensity : 999;

        // Fail closed on the properties that made the first asset invisible: it
        // sat on the flanks, it was mid-grey, and it was brown.
        if (coreTexels == 0)
            throw new Exception("mask produced no solid snow");
        if (densityRatio < 1.3)
            throw new Exception("up-facing snow is not denser than flank snow; ratio "
                + Inv(densityRatio, 3));
        if (upShare < 0.45)
            throw new Exception("snow is not concentrated on up-facing surfaces: " + Inv(upShare, 4));
        if (coreLuma < 205)
            throw new Exception("snow is too dark to read at gameplay zoom: " + Inv(coreLuma, 2));
        if (coreSat > 0.06)
            throw new Exception("snow is tinted rather than neutral: " + Inv(coreSat, 4));

        // Invariant formatting: this report is parsed back into the manifest, and
        // a locale that writes "215,89" would corrupt the JSON.
        return string.Join(";", new string[] {
            "mesh=" + mask.MeshInfo,
            "threshold=" + Inv(mask.Threshold, 6),
            "flankThreshold=" + Inv(mask.FlankThreshold, 6),
            "upFacingTexels=" + mask.UpFacingTexels,
            "flankEligibleTexels=" + mask.FlankTexels,
            "changedTexels=" + changed,
            "coveragePercent=" + Inv(100.0 * changed / (Size * Size), 4),
            "coreTexels=" + coreTexels,
            "semiTransparentTexels=" + semiTransparent,
            "shadowTexels=" + shadowTexels,
            "sparkleTexels=" + sparkleTexels,
            "upShare=" + Inv(upShare, 4),
            "upDensity=" + Inv(upDensity, 4),
            "flankDensity=" + Inv(flankDensity, 4),
            "densityRatio=" + Inv(densityRatio, 3),
            "coreSnowLuma=" + Inv(coreLuma, 2),
            "coreSnowSaturation=" + Inv(coreSat, 4)
        });
    }
}
'@ -ReferencedAssemblies System.Drawing

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Escape-JsonPath([string]$Value) {
    return $Value.Replace('\', '\\')
}

$results = @()

foreach ($asset in $spec.assets) {
    if ($Only -and $asset.id -ne $Only) { continue }

    Write-Host "=== $($asset.id) ($($asset.fullType), stage $($asset.stage)) ==="

    foreach ($required in @($asset.mesh, $asset.source)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "$($asset.id): required vanilla input missing: $required"
        }
    }

    $sourceHash = Get-Sha256 $asset.source
    $meshHash = Get-Sha256 $asset.mesh
    $meshText = [IO.File]::ReadAllText($asset.mesh)

    # Descriptive only. An operator confirms the axis by looking at a render;
    # see the warning in snow_assets.json for why no test can decide it here.
    $axes = [EwSnowMask]::DescribeAxes($meshText)
    Write-Host "    geometry: $axes"

    # The grip-side test recovers DOWN from the geometry and agrees with every
    # vanilla mesh measured, handguns included. Disagreeing with the spec means one
    # of the two is wrong, and silently trusting the spec is how the handguns
    # shipped with snow on their undersides.
    $inferred = [EwSnowMask]::InferUpSign($meshText)
    if ($inferred -eq 0) {
        Write-Warning "$($asset.id): up sign is geometrically ambiguous; the spec value stands unchecked."
    }
    elseif ($inferred -ne [int]$asset.upSign) {
        throw "$($asset.id): spec says upSign $($asset.upSign) but the grip side implies $inferred"
    }

    $shippable = [bool]$asset.visuallyVerified
    if ($PreviewRoot) {
        if (-not (Test-Path -LiteralPath $PreviewRoot)) {
            New-Item -ItemType Directory -Path $PreviewRoot | Out-Null
        }
        $outputPath = Join-Path $PreviewRoot "$($asset.id).png"
        $shippable = $false
    }
    elseif (-not $shippable) {
        # Outside the mod tree: an unverified preview is a review render, not mod
        # content, and writing it inside would change the delivered tree.
        $previewDirectory = Join-Path (Split-Path -Parent $projectRoot) 'EnvironmentalWeapons-preview'
        if (-not (Test-Path -LiteralPath $previewDirectory)) {
            New-Item -ItemType Directory -Path $previewDirectory | Out-Null
        }
        $outputPath = Join-Path $previewDirectory "$($asset.id).png"
        Write-Warning "$($asset.id) is not visually verified; writing a preview and refusing to freeze."
    }
    else {
        $outputPath = Join-Path $modRoot ($asset.output -replace '/', '\')
    }

    $sourceBitmap = [System.Drawing.Bitmap]::new($asset.source)
    try {
        if ($sourceBitmap.Width -ne 256 -or $sourceBitmap.Height -ne 256) {
            throw "$($asset.id): vanilla source is not 256x256"
        }
        $canvas = [System.Drawing.Bitmap]::new(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($canvas)
            try {
                $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.DrawImage($sourceBitmap, 0, 0, 256, 256)
            }
            finally { $graphics.Dispose() }

            $rect = [System.Drawing.Rectangle]::new(0, 0, 256, 256)
            $data = $canvas.LockBits($rect,
                [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $buffer = [byte[]]::new(256 * 256 * 4)
                for ($y = 0; $y -lt 256; $y++) {
                    [Runtime.InteropServices.Marshal]::Copy(
                        [IntPtr]::Add($data.Scan0, $y * $data.Stride),
                        $buffer, $y * 256 * 4, 256 * 4)
                }
                # Alpha is taken from the source pixel by pixel, not from
                # whatever the GDI+ copy happens to leave in the canvas. That
                # semantics differs between 24bpp and 32bpp sources and is not
                # worth depending on for a correctness invariant.
                for ($y = 0; $y -lt 256; $y++) {
                    for ($x = 0; $x -lt 256; $x++) {
                        $buffer[(($y * 256) + $x) * 4 + 3] = $sourceBitmap.GetPixel($x, $y).A
                    }
                }
                $report = [EwSnowMask]::Composite(
                    $buffer, $meshText,
                    [int]$asset.upAxis, [int]$asset.upSign, [bool]$asset.flipV,
                    [double]$asset.targetUpCoverage, [double]$asset.noiseBase,
                    [double]$asset.edgeSoftness, [double]$asset.flankCoverage,
                    [double]$asset.flankMaxAlpha)
                for ($y = 0; $y -lt 256; $y++) {
                    [Runtime.InteropServices.Marshal]::Copy(
                        $buffer, $y * 256 * 4,
                        [IntPtr]::Add($data.Scan0, $y * $data.Stride), 256 * 4)
                }
            }
            finally { $canvas.UnlockBits($data) }

            $outputDirectory = Split-Path -Parent $outputPath
            if (-not (Test-Path -LiteralPath $outputDirectory)) {
                New-Item -ItemType Directory -Path $outputDirectory | Out-Null
            }
            $canvas.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $canvas.Dispose() }
    }
    finally { $sourceBitmap.Dispose() }

    $outputHash = Get-Sha256 $outputPath

    if ($FreezeRecipe -and $shippable) {
        $recipePath = Join-Path $projectRoot ($asset.recipe -replace '/', '\')
        $recipeDirectory = Split-Path -Parent $recipePath
        if (-not (Test-Path -LiteralPath $recipeDirectory)) {
            New-Item -ItemType Directory -Path $recipeDirectory | Out-Null
        }
        [IO.File]::WriteAllBytes($recipePath, [IO.File]::ReadAllBytes($outputPath))
    }

    $measured = [ordered]@{}
    foreach ($pair in $report -split ';') {
        $parts = $pair -split '=', 2
        $measured[$parts[0]] = $parts[1]
    }

    $results += [ordered]@{
        asset = $asset
        sourceHash = $sourceHash
        meshHash = $meshHash
        outputHash = $outputHash
        outputPath = $outputPath
        shippable = $shippable
        measured = $measured
        axes = $axes
    }

    $line = [ordered]@{ Output = $outputPath; Sha256 = $outputHash; Shippable = $shippable }
    foreach ($key in $measured.Keys) { $line[$key] = $measured[$key] }
    [PSCustomObject]$line | Format-List
}

if ($results.Count -eq 0) { throw "No assets matched" }

# The manifest is produced evidence: written here, never hand-maintained, so the
# recorded numbers always belong to the bytes that were just generated.
if ($WriteManifest) {
    $shippableResults = @($results | Where-Object { $_.shippable })
    if ($shippableResults.Count -ne $results.Count) {
        throw "Refusing to write a manifest while some assets are unverified previews"
    }
    if ($Only) {
        throw "Refusing to write a partial manifest; rerun without -Only"
    }

    $lines = @('{', '  "schema": 1,',
        '  "role": "Produced evidence. Written by tools/generate_snow_textures.ps1; never hand-edited.",',
        '  "assets": {')
    for ($index = 0; $index -lt $results.Count; $index++) {
        $entry = $results[$index]
        $m = $entry.measured
        $comma = if ($index -lt $results.Count - 1) { ',' } else { '' }
        $lines += @(
            "    `"$($entry.asset.id)`": {",
            "      `"fullType`": `"$($entry.asset.fullType)`",",
            "      `"stage`": $($entry.asset.stage),",
            "      `"output`": `"$($entry.asset.output)`",",
            "      `"recipe`": `"$($entry.asset.recipe)`",",
            "      `"sourcePath`": `"$(Escape-JsonPath $entry.asset.source)`",",
            "      `"sourceSha256`": `"$($entry.sourceHash)`",",
            "      `"meshPath`": `"$(Escape-JsonPath $entry.asset.mesh)`",",
            "      `"meshSha256`": `"$($entry.meshHash)`",",
            "      `"outputSha256`": `"$($entry.outputHash)`",",
            '      "width": 256,',
            '      "height": 256,',
            '      "sourceHasAlphaChannel": false,',
            '      "outputIntroducesTransparency": false,',
            "      `"upAxis`": $($entry.asset.upAxis),",
            "      `"upSign`": $($entry.asset.upSign),",
            "      `"flipV`": $(if ($entry.asset.flipV) { 'true' } else { 'false' }),",
            "      `"driftThreshold`": $($m['threshold']),",
            "      `"flankThreshold`": $($m['flankThreshold']),",
            "      `"upFacingTexels`": $($m['upFacingTexels']),",
            "      `"flankEligibleTexels`": $($m['flankEligibleTexels']),",
            "      `"changedTexels`": $($m['changedTexels']),",
            "      `"coveragePercent`": $($m['coveragePercent']),",
            "      `"coreTexels`": $($m['coreTexels']),",
            "      `"semiTransparentTexels`": $($m['semiTransparentTexels']),",
            "      `"shadowTexels`": $($m['shadowTexels']),",
            "      `"sparkleTexels`": $($m['sparkleTexels']),",
            "      `"upShare`": $($m['upShare']),",
            "      `"upDensity`": $($m['upDensity']),",
            "      `"flankDensity`": $($m['flankDensity']),",
            "      `"densityRatio`": $($m['densityRatio']),",
            "      `"coreSnowLuma`": $($m['coreSnowLuma']),",
            "      `"coreSnowSaturation`": $($m['coreSnowSaturation']),",
            '      "status": "local development derivative pending release-rights review",',
            '      "algorithm": "EW mesh-normal-gated multi-scale value-noise snow mask v2",',
            '      "seed": "0x45574c31"',
            "    }$comma")
    }
    $lines += @('  }', '}')
    [IO.File]::WriteAllText($manifestPath,
        ($lines -join "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))
    Write-Host "manifest written: $manifestPath"
}

Write-Host "generate_snow_textures: PASS ($($results.Count) assets)"
