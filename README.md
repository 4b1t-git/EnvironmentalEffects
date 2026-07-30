# Environmental Weapons — Development Test Build

Development test scaffold for Project Zomboid 42.20, single-player only. This
package is not a release build and currently ships with `DEBUG = true`.

Start with [HANDOFF.md](HANDOFF.md) for the current status, evidence, guardrails,
and next task. A paste-ready Claude brief is in
[CLAUDE_CONTINUATION_PROMPT.md](CLAUDE_CONTINUATION_PROMPT.md).

The first enabled profile is `Base.HuntingRifle`. Snow state is simulated and
persisted per unique item, using one deterministic development texture per stage
across all four snow stages.

Snow advances **one stage per 10 game minutes** while the weapon is out in
snowfall, and retreats at the same pace once it is sheltered, rained on, or warm
enough to thaw. A weapon in your hands or slung on your back collects snow; one
stowed in a bag thaws.

Snow held outdoors below freezing in clear weather simply stays. Rain strips it
regardless of temperature: liquid water is falling, so it carries heat and washes
the surface.

## Exact in-game diagnostic sequence

1. Install the canonical `EnvironmentalWeapons` folder as a local Build 42 mod
   and enable it in a disposable single-player save.
2. Equip one vanilla `Base.HuntingRifle`; do not unload it or remove attachments.
3. Record its ammo, magazine, chamber, condition, name, favorite state, and attachments.
4. Right-click that exact rifle and select `EW Debug: force stage 1 (light snow)`.
5. Confirm the equipped rifle changes while all recorded gameplay state remains
   unchanged.
6. Step through `force stage 2`, `3`, and `4`, confirming that snow only ever
   grows and never jumps to a different part of the rifle.
7. Drop the rifle and confirm it stays snowy and lies with the normal vanilla
   rifle orientation.
8. Pick it up, right-click it, and select `EW Debug: restore vanilla`.
9. Confirm vanilla equipped/world visuals return on the same item instance.

The texture is a local derivative of the installed vanilla
`MSR788_Rifle.png`, pending release-rights review. It is not a final icon or a
complete stage set.

Existing development saves may contain the retired
`EW_HuntingRifle_SnowLight_World` override. Pick up that rifle and use either
debug action once; the adapter clears only that owned legacy value. It preserves
any unrelated world-model override. Drop the rifle again to confirm the normal
`HandWeapon` rotation.

## Validate

Run:

```text
node tests/pure_logic_test.js
node tools/validate.js
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/replay_snow_textures.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/validate_snow_textures.ps1
```

## Continue safely

Run from `work/EnvironmentalWeapons`.

Audit the current source, canonical package, installed mod, ZIP, and hashes
without synchronizing:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/sync_development_build.ps1
```

After an intentional source change, validate and synchronize the exact
development build:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/sync_development_build.ps1 -Apply
```

The script fails closed unless its source, canonical output, and install paths
are exact and the existing canonical/install trees contain
`id=EnvironmentalWeapons`. It mirrors only this mod, rebuilds a rooted safe ZIP,
regenerates the external build hashes, and proves work/output/install/ZIP
parity. It never targets vanilla files, saves, EWTC, Gemini, or audit outputs.

The PowerShell generator and visual validator use only Windows PowerShell,
`System.Drawing`, and the exact installed vanilla source. No package install,
`NODE_PATH`, Sharp, or Python is required.

The mask algorithm lives in `tools/generate_snow_textures.ps1`. It parses
the vanilla `MSR788_Rifle.x` mesh, gives every texel the interpolated surface
normal of the triangle that owns it, and settles snow only where that normal
points up (+Z in model space). Roughly 65% of this atlas maps to the rifle's
vertical flanks, so a uniform texture-space mask spends most of its budget on
surfaces snow cannot hold — which is why the first attempt was invisible from
Project Zomboid's overhead camera.

The shipped `.png.seed` is the frozen byte output of that generator.
`tools/replay_snow_textures.ps1` only replays it: it verifies the exact vanilla
source hash, materializes the reviewed PNG bytes, and verifies the expected
output hash. This preserves the approved image byte-for-byte even though
different PNG encoders would otherwise produce different files from identical
pixels.

Which textures exist is declared in `tools/snow_assets.json` (reviewed intent,
human-edited). What they measured is recorded in
`assets/snow_texture_manifest.json` (produced evidence, generator-written and
the only place expected hashes live). Adding a weapon is one spec entry.

The up axis is explicit per asset and cannot be inferred: "up-facing area
exceeds down-facing area" fails on both vanilla pistols, and "centroid below
mid-height" fails on every rifle. Confirm placement by running
`node tools/preview_snow_textures.js` and looking at the contact sheet. An asset
marked `"visuallyVerified": false` is written to `docs/preview/` and never
frozen or shipped.

A second, weaker pass dusts sparse flecks onto the near-vertical flanks, because
a top-only mask leaves the rifle looking bare whenever the camera sees its side —
most obviously when it is slung on the character's back. Undersides are excluded;
snow does not hold there.

The four stages differ only in `targetUpCoverage` (0.46 / 0.66 / 0.84 / 0.96),
`flankCoverage` (0.05 / 0.15 / 0.30 / 0.36) and `flankMaxAlpha` (0.45 / 0.55 /
0.78 / 0.90). `noiseBase` and `edgeSoftness` are identical on purpose: the mask
keeps one noise field and only lowers the threshold, so each stage's snow is a
strict superset of the previous stage's. Re-rolling the field per stage would
make snow appear in different places between stages, which reads in game as snow
teleporting the moment a threshold is crossed.
`tools/validate_snow_textures.ps1` proves that nesting texel by texel.

Even at stage 4 the wood stays recognizable. Burying the weapon completely would
make every snowed weapon a white blob and cost the player the ability to identify
what they are carrying.

## Surface detail

Flat snow made the weapon look like it had lost resolution: measured against the
vanilla texture, only 46% of fine detail survived under a heavy drift. Six
effects give the snow a surface of its own, all derived from the mesh and the
vanilla pixels:

- **Translucency scaled by thickness.** A dusting lets wood grain and machining
  ghost through; a deep drift hides them. Constant translucency fails both ways —
  too little is flat paint, too much stains the snow brown.
- **Lit crest.** The alpha gradient locates drift borders, which get a brighter
  edge.
- **Cast shadow.** A bare texel under a drift lip takes a short, faintly cool
  shadow. This is what makes snow read as resting *on* the weapon.
- **Thickness taper.** Alpha scales with surface inclination, so snow thins
  around the barrel's curve instead of ending in a hard band.
- **Crevice packing.** The vanilla texture paints recesses darker than their
  surroundings, so local darkness works as an ambient-occlusion proxy: snow packs
  around the bolt, trigger guard, sight base and swivels.
- **Metal frosts first.** Metal conducts cold away faster than wood. Vanilla
  metal is dark and desaturated while the stock is saturated brown, so saturation
  separates them and the barrel frosts a stage ahead of the stock.
- **Sparse crystals.** ~1.2% of drift interiors get a brighter texel. Kept rare
  deliberately: single-texel highlights are sub-pixel at gameplay zoom and
  shimmer if overused.

Detail retention rose from 46-78% to 73-91% of the vanilla baseline.

This development build is installed at
`C:\Users\4b1t2\Zomboid\mods\EnvironmentalWeapons`. The editable source remains
`work/EnvironmentalWeapons`; use the continuation workflow above so the
canonical output, ZIP, hash manifest, and same-ID installed tree stay identical.
