# EnvironmentalWeapons has all four snow stages and awaits in-game confirmation

The Build 42.20 single-player vertical slice works for `Base.HuntingRifle`: the
per-item snow state and safety regressions pass, the light-snow texture appears
while equipped, and the dropped rifle lies flat with the snowy texture.

All four stages exist, the snow has surface relief rather than being flat paint,
and the natural weather cycle now advances one stage per 10 game minutes in each
direction. Every validator passes. **The three screenshots in `docs/evidence`
predate all of this**, so what is in them is not what ships today.

All four stages are confirmed in game as of 2026-07-30, after the engine review
fixes. The next task is expanding to the remaining firearms.

**Before investing in that expansion, settle the publication question.** The
textures are derivatives of the installed vanilla art. The project has always
carried this as "pending release-rights review", and it decides whether this can
reach the Workshop at all or stays a personal build.

## Quick path

1. Read `tools/snow_assets.json` (reviewed intent) and
   `tools/generate_snow_textures.ps1` (the mask algorithm).
2. Read `EW_Profiles.lua` and `EW_VisualAdapter.lua` before editing anything.
3. Change a texture by editing its entry in `tools/snow_assets.json`
   (`targetUpCoverage`, `noiseBase`, `edgeSoftness`, `flankCoverage`,
   `flankMaxAlpha`), then regenerating and refreezing. Preserve exact
   dimensions, opacity, UV layout, gameplay state, and firearm world fallback.
4. Run the exact validation commands below.
5. Ask the user to confirm both equipped and dropped visuals before expanding
   scope, and replace the stale screenshots in `docs/evidence`.

## Current status

| Topic | Confirmed state |
| --- | --- |
| Game target | Project Zomboid 42.20 stable, single-player |
| Multiplayer | Explicitly pinned for later |
| Enabled weapons | 8 firearms: HuntingRifle, MSR7T_Rifle, AssaultRifle, AssaultRifle2, JS14_Rifle, L92_Carbine, VarmintRifle, TrapperCarbine |
| Vanilla visual source | `weapons/firearm/MSR788_Rifle`, 256×256 texture |
| Visual coverage | All four stages present; stage 0 is vanilla |
| Equipped visual | Confirmed in game by the user, all four stages |
| Ground visual | Confirmed snowy and flat after removing WorldStaticModel |
| Stages 2-4 | Validators pass, progression reviewed on the contact sheet, and confirmed in game on 2026-07-30 |
| Snow placement | Mesh-normal gated; 72-94% of snow mass on up-facing surface |
| Progression | Provably nested: each stage's snow is a superset of the previous |
| Flank dusting | Sparse flecks at stage 1, growing to real cover at stage 4; undersides always clear |
| Snow readability | Solid-snow cores at luma 218-226, saturation ≤0.02 (was 110 / 0.09) |
| Surface detail | Lit crest, cast shadow at the drift foot, thickness taper, crevice packing, metal-first frost, sparse crystals |
| Detail retention | 73-91% of vanilla fine detail survives under snow (was 46-78%) |
| Debug state | `DEBUG = true` development build |
| Logic suite | 59 assertions pass; 32 textures validated |
| Installed path | `C:\Users\4b1t2\Zomboid\mods\EnvironmentalWeapons` |
| Release status | Development test, not publishable |

## Visual evidence

All three screenshots were taken with the **previous** Stage 1 texture
(`5b78e02c…`). They still prove the pipeline and the orientation fix, but none of
them shows the refined mask.

| Evidence | What it proves | Caveat |
| --- | --- | --- |
| [Equipped Stage 1](docs/evidence/hunting-rifle-stage1-equipped-subtle.png) | Custom Stage 1 texture renders on the held rifle | Shows the retired subtle texture |
| [Upright ground bug](docs/evidence/hunting-rifle-stage1-ground-upright-bug.png) | Reproduces the retired WorldStaticModel orientation bug | Historical failure; must not regress |
| [Corrected flat ground](docs/evidence/hunting-rifle-stage1-ground-flat-corrected.png) | HandWeapon fallback restores flat orientation and retains texturing | Shows the retired subtle texture |

## Architecture map

| File | Responsibility | Key invariant |
| --- | --- | --- |
| `mod/` | The deliverable; everything else is toolchain | Only this is mirrored, zipped and installed |
| `tools/generate_mod_wiring.js` | Generates model blocks and EW_Profiles.lua from the spec | Attachments copied verbatim from the vanilla ModelScript |
| `EW_Config.lua` | Rates, thresholds, debug gate | Development build currently uses `DEBUG = true` |
| `EW_State.lua` | Versioned per-item modData and original visual snapshot | Never replace the item |
| `EW_Simulation.lua` | Pure elapsed-game-minute snow math | Clamp to 0-100 |
| `EW_StageResolver.lua` | Stage thresholds with hysteresis | Prevent visual thrashing |
| `EW_Profiles.lua` | Explicit FullType profiles | Hunting Rifle Stage 1 has equipped model only |
| `EW_Climate.lua` | 42.20 weather sampling | Rain never accumulates snow, and always strips it |
| `EW_Exposure.lua` | Classifies carried weapons as exposed or sheltered | Hands and body slots are exposed; containers thaw |
| `EW_Controller.lua` | Low-frequency lifecycle | `EveryTenMinutes`, never `OnTick`; no time charged before an item was carried |
| `EW_VisualAdapter.lua` | Reversible visual mutation and legacy migration | No nil model setters; refresh reaches held AND slung weapons in every pose |
| `EW_DebugProbe.lua` | Force any stage / restore actions | Available only when debug is enabled |
| `models_EnvironmentalWeapons.txt` | Equipped snow model registration | No firearm WorldStaticModel model |
| `tools/snow_assets.json` | Reviewed intent: what to generate, per asset | Human-edited; `visuallyVerified` gates shipping |
| `assets/snow_texture_manifest.json` | Produced evidence: hashes and measurements | Generator-written; the only place expected hashes live |
| `tools/generate_snow_textures.ps1` | The mask algorithm; parses the vanilla mesh | Snow only where the surface normal points up |
| `tools/replay_snow_textures.ps1` | Replays the frozen PNG bytes | Contains no algorithm; hash-gated byte copy |
| `tools/validate_snow_textures.ps1` | Pixel properties per asset | Asserts what snow must look like, not a frozen count |
| `tools/preview_snow_textures.js` | Contact-sheet renderer | The only reliable check on axis choice |

## Verified behavior

| Behavior | Evidence |
| --- | --- |
| One visual stage is gained per 10 game minutes, and lost per 10 game minutes | Pure logic tests |
| Faint snowfall still advances a full stage per tick | Pure logic tests |
| A stowed weapon thaws even while it snows outside | Pure logic tests |
| Snow holds on a frozen weapon outdoors in clear weather | Pure logic tests |
| Rain strips snow even below freezing, one stage per tick | Pure logic tests |
| A dropped weapon accumulates and thaws, judged by its own square | Pure logic tests + bounded-radius guard |
| A stage change refreshes held and slung weapons, in any pose | Static validator + user report |
| A schema bump preserves the vanilla snapshot, snow and stage | Pure logic tests |
| The slot probe runs only for profiled items | Pure logic tests |
| A trace of rain below the intensity gate does not strip snow | Pure logic tests |
| A coalesced or skipped tick advances the right amount | Pure logic tests |
| Indoor and warm-weather melting clamps safely | Pure logic tests |
| Hours before an item was carried are not charged | Lifecycle regressions |
| Rain cannot accumulate snow | Precipitation gate regressions |
| `minutesPerStage` cannot drift from the controller interval | Static validator |
| One tick cannot skip or stall a stage | Static validator |
| A different item sharing `HuntingRifle` sprite is unsupported | FullType regression |
| Missing original WeaponSprite never reaches the Java setter as nil | Static validation |
| Legacy EW world override clears only when adapter-owned | Three migration regressions |
| External world override is preserved | Migration regression |
| Equipped Stage 1 renders | User screenshot |
| Dropped Stage 1 lies flat and remains textured | User screenshot |

## Exact validation commands

Run from `work/EnvironmentalWeapons` (the project root, where the toolchain
lives). Validation runs once against the source; the canonical and installed
trees are then proved byte-identical to it, which is stronger than re-running
the same checks against copies.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/replay_snow_textures.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/validate_snow_textures.ps1
node tests/pure_logic_test.js
node tools/validate.js
```

To change a texture itself, run the generator instead of the replay script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/generate_snow_textures.ps1 -FreezeRecipe -WriteManifest
node tools/preview_snow_textures.js
```

It rewrites every PNG, its frozen seed, and `assets/snow_texture_manifest.json`
together. **No hashes are hard-coded anywhere else** — the replay script, both
validators, and the build-hash writer all read the manifest. Then look at
`../EnvironmentalWeapons-preview/contact_sheet.png` before trusting the result.
Previews live outside the mod tree on purpose: writing them inside broke
work/output parity on every regeneration.

Required results:

- regeneration `PASS`;
- visual validation: 256×256, zero transparent pixels, drift-core luma ≥ 205,
  drift-core saturation ≤ 0.06, up-facing share ≥ 0.68;
- pure logic: 59 assertions;
- static validator `PASS`;
- work/canonical/installed file counts and SHA-256 values match;
- ZIP entries all start with `EnvironmentalWeapons/`, contain no `..`, absolute
  paths, or copied vanilla source texture.

## Exact continuation workflow

From `work/EnvironmentalWeapons`, audit without synchronizing:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/sync_development_build.ps1
```

After an intentional source edit, apply the complete validated continuation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/sync_development_build.ps1 -Apply
```

The script is dependency-free and fails closed on unexpected paths, reparse
points, missing or foreign mod IDs, unsafe ZIP entries, stale hashes, or any
work/output/install byte mismatch.

## Hash and provenance anchors

| Artifact | SHA-256 |
| --- | --- |
| Exact local vanilla `MSR788_Rifle.png` | `c4f0b2271056779f214831d61a44a5a41fcf1b797515e6e7b8658a4f6ac0d9d4` |
| Exact local vanilla `MSR788_Rifle.x` mesh | `8bfd63c6b9e4b53b3778a91cfa568df97b5093099553f58d43090b91ddbbcda2` |
| Stage 1 derivative | `ea96b12ac63a6e3016801f91238a61f4d1ecdb710bc89a2e39b43638fda0d7b2` |
| Stage 2 derivative | `36c88536d73b1a502c7a0235bb1315afa2bd368dba48d851bbf2b015cb79bd7c` |
| Stage 3 derivative | `062e7fbe3d87bb8b114c2074e0252c1631e69cbb92c6ca05c2f6eb03bb13fcf1` |
| Stage 4 derivative | `8a5c5b441210ce6d11b5a8f414e7fe3829048342290a2187091a7834fad87065` |
| Retired pre-review Stage 1-4 | `2803d149…`, `2ce41244…`, `af75a9e8…`, `cc468a73…` |
| Retired flat-snow Stage 1-4 | `c5014e50…`, `0e86fc39…`, `c4b4a01d…`, `ead78dc3…` |
| Retired Stage 1, user-confirmed in game | `7e2165ed202823e53ca546aff7ba3b60be15641f95ee4737b8af9272274d7d04` |
| Retired top-only Stage 1 | `dc3568ce60d03146a5f08653eff21c610b390904b1e9f3e458e9d757585c3bd9` |
| Retired subtle Stage 1 | `5b78e02c54fbe117138165a9a16f3da9e7dc3ec346f44c0e5c1fce632216264c` |

The Stage 1 texture the user confirmed in game (`7e2165ed…`) has been superseded
twice since: once by a gutter-dilation fix, and once by the surface-detail pass
below. Snow placement and the approved visual direction are unchanged; what
changed is that the snow now has surface relief instead of being flat paint.
| Equipped screenshot | `f752b40a95dd2a2a4a3c96ce5f27ba88a30aa9678017fd511482e9aa9cab1550` |
| Upright-bug screenshot | `8da7c2b551ee7a004824deccdabfae9d612c49195cae646ab8b7504588b99f70` |
| Corrected-ground screenshot | `209619abd62fc400bbd1f4f4d2737dda9bef568a4e265fdaadd206a2de260f56` |

The authoritative current tree, ZIP, and per-file hashes live outside the ZIP in
`outputs/EnvironmentalWeapons_build_hashes.json`. Regenerate that file after
documentation or asset changes; do not copy stale values into this document.

The texture is a local derivative of the user's installed Project Zomboid asset.
It is suitable for private development testing only until release rights are
reviewed. Do not upload or publish the texture, seed, or package.

## Prior bugs and non-regression rules

| Rejected or fixed approach | Why it failed | Rule |
| --- | --- | --- |
| Rejected generative image | Did not meet the required vanilla-aligned visual direction | Never reuse or copy it |
| FireAxe-first slice | User chose firearms first | Continue with Hunting Rifle |
| Generic WeaponSprite profile fallback | Could enable unrelated items | Match exact FullType or explicit FullType alias |
| Per-item last-seen clock | Charged hours spent unequipped | Use controller interval plus previous-exposure lifecycle |
| Snow strength without type gate | Rain could be treated as snow | Require `getPrecipitationIsSnow()` |
| Passing nil to model setters | Java overload/NPE risk | Clear only owned modData keys; never call a setter with nil |
| Rifle WorldStaticModel | Forced generic atlas branch and upright drop | Firearms use custom WeaponSprite plus HandWeapon fallback |
| Hidden Sharp/NODE_PATH dependency | Artifact tools were not portable | Keep dependency-free PowerShell validation |
| Claimed "value-noise mask v1" algorithm | It was never shipped; only the frozen PNG and a provenance string existed, so the texture could not actually be re-derived | The algorithm now lives in `generate_snow_textures.ps1` |
| Uniform texture-space snow mask | ~65% of this atlas maps to the rifle's vertical flanks, so most snow landed where snow cannot settle and stayed invisible from PZ's overhead camera | Gate the mask on the mesh normal |
| Low-opacity grey overlay | Produced drift cores at luma 110 and saturation 0.09 — mud and camouflage, not snow | Composite near-neutral snow at luma ≥ 205 |
| "Zero alpha mismatches" as a safety claim | The vanilla PNG is RGB with no alpha channel, so the check was vacuous | Assert that no transparency is introduced instead |
| Hand-maintained provenance numbers | Invited stale values that no longer described the shipped bytes | The generator writes provenance; validators bind it to the texture hash |
| Frozen `ChangedRgbPixels` as the only pixel assertion | It blocked any texture change without describing what the texture should look like | Assert brightness, neutrality, and placement as well |
| Derivative hash pinned in three scripts | Every texture change needed four synchronized manual edits; multiplied across 22 firearms it is pure waste plus a whole class of drift | One generator-written manifest is the single source |
| Geometric up-axis self-check | Measured and rejected: "up area exceeds down area" fails on both pistols, "centroid below mid-height" fails on every rifle. A test that passes for rifles and fails for pistols is worse than none | Axis is explicit per asset and confirmed on a rendered contact sheet |
| Iterated gutter dilation guarded by `alpha > 0` | Path-dependent: a minuscule invisible alpha blocked the fill, and which texels had one shifted with the stage, so snow vanished from seam texels as later stages were built | One pass, fixed radius, sampling owned texels only |
| Counting gutter mass as flank mass | Placement statistics moved with how far the bleed reached, understating the up-facing share (0.94 read as 0.74) | Exclude unowned texels from placement accounting |
| Per-stage coverage bands | Stage 1 is a dusting and stage 4 is nearly buried; any fixed band either rejects a valid stage or admits a broken one | Assert monotonic, nested growth between consecutive stages |
| Re-rolling noise per stage | Snow would appear in different places between stages and pop when a threshold is crossed | `noiseBase` and `edgeSoftness` are identical across a weapon's stages |
| Flat `DetailBleed = 0.10` | Snow was opaque paint: measured 46% of vanilla fine detail surviving under a heavy drift, which reads as the weapon losing resolution | Bleed 0.45, scaled down by drift thickness |
| Flat `DetailBleed = 0.42` | The opposite failure: wood grain ghosted through deep drifts and the snow looked stained brown | Thick snow hides its substrate; detail comes from crest/shadow/crystals instead |
| Fourth noise octave | Sat at 3.2 texels per cycle, the atlas Nyquist limit, so it aliased into speckle rather than adding shape | Three octaves |
| Literal sparkle cutoff (`fbm >= 0.88`) | A 3-octave fbm sum almost never reaches it, so only 2-14 crystals appeared and the feature could not be judged | Threshold bisected to a target density, like every other threshold |
| Raw-luma stage monotonicity | Drift shadows legitimately darken texels, and those bands move as drifts grow, so the assertion flagged correct output | Assert nesting on the snow mask, not on raw luma |
| Smooth up-facing gate on a cylinder | A barrel is a cylinder, so the set of points at a given surface angle is a circle, which unwraps to a STRAIGHT LINE in UV: snow ended at a ruler-straight edge along the handguard while irregular geometry got a natural boundary. Multiplying by noise scales the value but leaves the iso-line where it is | Jitter the up value before the gate, so the boundary itself is perturbed |
| Absolute `coreTexels >= 3000` | A property of how much atlas a weapon occupies, not of snow quality: JS14 owns 4255 up-facing texels against the Hunting Rifle's 13313 and was rejected at 2136 cores | Require cores to be >=25% of changed texels |
| Absolute coverage band 8-55% of the atlas | Same defect: T_Carabine at 5.3% of its atlas was 31% of its own area | Measure coverage against the weapon's owned atlas area |
| `upShare` floors disagreeing between validators | validate.js kept 0.68 while the PowerShell validator moved to 0.45, so the stricter one rejected a valid M16 stage 4 | Both use the density ratio plus a matching 0.45 floor |
| Accumulation rate scaled by snowfall intensity | Build 42.20 reports precipitation intensity far below 1.0 during snow, so the nominal 8-hours-to-full became 20+ game hours and the mod looked broken: the user watched for hours and never left stage 1 | Intensity gates accumulation; the rate is a fixed one stage per tick |
| Dropped weapons never simulated | Exposure walked only the player's inventory, so a rifle dropped indoors kept its snow forever and one left out in a blizzard collected none | Bounded sweep of nearby squares, each item judged by its own square |
| Exposure defined as "in hands" only | A rifle slung on the back collected nothing though it is fully in the weather, and a snowy rifle stowed in a bag stayed snowy forever because melt was also hands-only | Hands and body slots accumulate; anything in a container thaws |
| Stage change invisible while seated | `resetEquippedHandsModels` does not reach the rendered model in a seated or lying animation state, so the change only appeared after standing up | Also request `resetModelNextFrame`, the deferred full rebuild vanilla uses for appearance changes |
| Stage change invisible on a slung weapon | The refresh was gated on the item being in hands, so a weapon on the back is drawn on the character but never got refreshed at all | Refresh whenever the item is rendered on the character, hands or body slot |
| `upness` averaged over all subsamples | Diluted every texel on a UV island edge by up to 16x (11.5% of owned texels; 437 fell under the up-facing threshold), so snow visibly retreated along the seams | Normalize by the subsamples a triangle owns |
| Core classified by absolute luma alone | Portable only by accident: D_E_Pistol has 8203 vanilla texels already above the floor and DoubleBarrelShotgun 344, so a dusting there counted as solid snow and the brightness assertion passed vacuously. A texel with zero snow scored as a core | Require both a bright result and a real rise above vanilla |
| Crevice blur reading unowned atlas space | The gutter averages luma 69 against the surface's 62, inflating apparent recess depth within the blur radius of every seam | Weighted blur over owned texels only |
| Snapshotting channels that are never restored | staticModel, worldStaticModel, modelIndex and textureName had zero readers but were persisted into every save, and ARCHITECTURE.md claimed a restore guarantee that did not exist | Capture only what the adapter restores |
| Snow surviving freezing rain | Melt was gated on temperature alone, so after snowfall stopped at sub-zero a downpour left snow pinned at 100% forever | Rain is its own melt trigger, independent of temperature |
| Unconditional `resetEquippedHandsModels` | Harmless with hands-only tracking, but once stowed weapons are reconciled it would restart the held weapon's models whenever a bagged weapon changed stage | Refresh only when the changed item is actually in hand |

## Scope guardrails

- Preserve item identity, ammo, magazine, chamber, condition, custom name,
  favorite state, and attachments.
- Do not modify saves, vanilla files, EWTC, Gemini material, or audit outputs.
- Do not add networking, particles, rust, wetness, frost, melee, icons, or other
  weapons during Stage 1 refinement.
- Do not install over an unknown folder. The target must be absent or contain
  `id=EnvironmentalWeapons`.
- Keep `WorldStaticModel` unset for the Hunting Rifle snow profile.

## Prioritized next tasks

1. Confirm the natural cycle in game: hold the rifle outdoors in snowfall and
   watch a stage appear every 10 game minutes, then stow it and watch the stages
   come off at the same pace. Confirm a slung rifle also accumulates.
2. Confirm all four stages with the debug probe, then replace the three stale
   screenshots in `docs/evidence`.
3. Revalidate save/load and restore in a disposable single-player save, watching
   for visible popping at the stage thresholds.
4. Remaining firearms, in the order surveyed: shotguns (Shotgun, ShotgunSawnoff,
   DoubleBarrelShotgun, DoubleBarrelShotgunSawnoff, JS3T_Shotgun), then pistols
   and revolvers (Pistol, Pistol2, Pistol3, Revolver, Revolver_Long,
   Revolver_Short). Expect to retune noiseBase for the handguns: they pack a much
   smaller object into the same 256x256 atlas, so drifts land at a different
   physical scale. Three weapons stay blocked on texture size: Revolver_CapGun
   and Rifle_CapGun at 64x64, L94_Rifle at 2048x2048.
5. Decide whether attachments should carry snow. Scopes are the strong case: they
   mount on top, so they are the most exposed part of the rifle, and a pristine
   black scope on a snowed rifle is the most visible inconsistency left. Only
   `x2Scope`, `x4Scope` and `x8Scope` are worth it; the laser, choke tubes and
   tritium sights are tiny or hidden. Unresolved design question: an attachment is
   a separate item with its own modData, so if it accumulates snow and is then
   moved to a dry rifle, does the snow travel with it? That is the same
   state-ownership question as multiplayer, so resolve it once.
5. Expand explicit profiles across vanilla firearms, then other weapons.
6. Finish single-player v1.
7. Add multiplayer synchronization later; it remains pinned, not forgotten.

## Copyable next-task prompt

Use the exact prompt in `CLAUDE_CONTINUATION_PROMPT.md`.
