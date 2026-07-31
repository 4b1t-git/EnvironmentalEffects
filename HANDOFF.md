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

## Publication

[WORKSHOP.md](WORKSHOP.md) carries the paste-ready store description and the
blocker checklist. The build cannot be uploaded as it stands: asset rights are
unresolved, `DEBUG = true`, `mod.info` still says "Development Test", there is no
multiplayer and no poster.

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
| Enabled weapons | **19 firearms** — every vanilla firearm whose texture is 256x256 and whose mesh is 1:1 indexed |
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
| Wetness | Implemented and seen in game 2026-07-30. One signed axis: +100 snowed, 0 dry, -100 soaked. 57 wet textures, 3 levels per weapon. **Visible, but the three levels are too close together** -- see the open tasks below |
| Judging textures | **Always** run `tools/gameplay_scale_preview.ps1` on the contact sheet. Review size is ~5x play size and hides everything |
| Logic suite | 80 assertions pass; 133 textures validated |
| Mod identity | `id=EnvironmentalEffects`, frozen 2026-07-30 while unpublished |
| Installed path | `%USERPROFILE%\Zomboid\mods\EnvironmentalEffects` |
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
| `tools/preview_snow_textures.js` | Contact-sheet renderer | The only reliable check on axis choice. Optional 5th arg filters by asset id |
| `tools/gameplay_scale_preview.ps1` | Downsamples a sheet to on-screen weapon size | Mandatory before believing any texture change |
| `tools/generate_wet_assets.js` | Derives the 57 wet spec entries from each weapon's stage 1 | Per-level coverage and alpha live here |

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
| Two separate mods for snow and rain | A weapon has ONE `WeaponSprite`, so something must arbitrate which phenomenon draws, and that arbiter is shared logic. Worse, each mod snapshots the "original" visual to restore later: whichever ran second would capture the first one's texture as vanilla and write that corruption into the save. Mod load order is not guaranteed either | One mod, one state, sandbox options for the player's choice |
| Wetness as a second independent axis | Snow x wet x mud would be 4x3x3 = 36 textures per weapon, 684 total | One SIGNED axis: +snow, 0 dry, -wet. States are mutually exclusive, which the existing "rain strips snow" rule already made physically true |
| ~~Darkening cannot be the universal wet effect~~ **-- OVERTURNED 2026-07-30** | The evidence was that the near-black M9 Pistol had no headroom to darken before hitting the luma floor. The floor was `WetLumaFloor = 26` and the M9 atlas sits near 30, so the finding was about the constant, not about the pistol. At a floor of 14 every one of the 19 weapons darkens, M9 included | Water darkens, always. Both validators now REJECT a wet core that is brighter than vanilla |
| Letting wetness brighten "where the material calls for it" | It brightened on every weapon, because firearm atlases are dark and `PuddleReflect` mixed toward luma 168. Snow moves a texel +110 and wet moved it +20, so both phenomena pushed the same way and wetness read as thin snow at play size | The two phenomena move in OPPOSITE directions. That contrast is what makes them distinguishable, not their strength |
| Ramping the wet levels on coverage alone | Snow can, because each snow texel moves ~110 luma; the area ramp is all it needs. A wet texel moves a fraction of that, and three levels at 24, 22 and 22 luma were a progression on paper and none on screen | Wet levels ramp depth AND area. `validate_snow_textures.ps1` requires each level to be >= 0.06 deeper than the last |
| A wide pool edge so the rim survives downscaling | Backwards priority. Over a smooth single-octave field a 0.13 band is spatially enormous, so pools were ramp all the way through: 19045 of 20944 core texels still counted as edge and alpha never reached its ceiling. Since the darkening scales by alpha, the pools could not darken | The large dark SHAPE is what survives the reduction to ~200 px; the meniscus is close-range detail. Narrow edge, flat saturated interior |
| Contact sheet preferring the delivered texture over the preview | The generator writes unverified assets to the preview tree and leaves the previously approved copy in `mod/`, so "delivered wins" rendered a regenerated texture as its own predecessor. An entire retune of the wet levels reviewed as the pass it replaced, with no visible difference to explain why | The preview copy wins. It only exists while an asset is under review |
| Absolute luma-shift assertion for wetness | Not portable: a shift of 3 on the M16's near-black receiver is a visible change, the same 3 on a pale stock is nothing | Assert the shift RELATIVE to the vanilla luma underneath, scaled by the level |
| Wide specular highlight on wet metal | A barrel is a cylinder, so a large share of it reads as up-facing; a highlight with a 0.55 floor and a 2.6x dark boost lit the whole top half and turned black steel mid-grey, which looks dusty rather than wet | Narrow the highlight to the crown (0.80 floor) and carry dark surfaces with a small uniform lift instead |
| Uniform wet base share on every material | Wood soaks evenly but metal beads. A flat base share made barrels an even pale grey | Metal takes most of its wetness from the pooling mask, wood from the uniform base |
| One fixed metric list in the texture manifest | The wet composite reports specular counts and no flank threshold; the snow composite the reverse. A fixed list emitted `"flankThreshold": ,` and produced unparseable JSON | The manifest emits whatever metrics the running composite actually reported |
| Sorting stages -3..4 as one progression | Compared the most soaked texture against the least snowed one. On the wet side -3 is the DEEPEST level, so signed order runs backwards | Group by weapon AND mode, order by magnitude. Only snow proves texel nesting |
| Debug probe hard-coded to `Base.HuntingRifle` | Quietly stopped covering eighteen of the nineteen supported firearms once the roster grew | The probe offers itself for any profiled item |
| Reading vanilla's structure off filenames | `HuntingRifle_Scope.png` and `VarmintRifle_Scope.x` look exactly like a rifle-with-scope variant, and a whole task was specified on that reading. They are dead assets no script references: the two meshes are byte-identical to each other and have FEWER vertices than the plain rifle, and the PNG is a 128x128 atlas of a different, older rifle. A scope is really a separate model on an `attachment scope` anchor, and all four scopes share one texture | Confirm against `media/scripts/`, not against `media/textures/` and `media/models_X/`. A vanilla asset that no script mentions is not a feature |
| Generating attachment blocks with nothing checking them | `generate_mod_wiring.js` copies vanilla's attachment anchors into all 133 EW models by brace matching. A miscopy would move or drop every mounted part -- scope, muzzle, bayonet, recoil pad, red dot -- on the affected weapon, silently, and only for players who had one attached | Two layers, because either alone has a blind spot. `validate.js` proves the set is non-empty and identical across a weapon's states, with no need for the game installed. `validate_snow_textures.ps1` proves it matches vanilla exactly, which is the only way to catch every state being wrong in the same way |
| Giving water a mask of its own | Pools over every surface but the undersides, on the reasoning that rain reaches everything. In game it reads as scattered staining, not as weather, and no amount of retuning the pools fixed it because the defect was structural. Snow accumulates from the top down and creeps onto the flanks as it builds; rain does the same. Sharing the geometry and differing only in the optics is what makes the two look like two states of one weapon | `BuildWetMask` delegates to `BuildMask`. Wet spec entries carry snow's geometry keys, copied from the weapon's own snow stages 1, 2 and 4. Both validators now assert `wetUpShare >= 0.35` |
| Trusting `state.visual` to decide the visual is already applied | `state.visual` lives in the item's modData and survives a save and reload; the `WeaponSprite` it describes is a runtime override that does not necessarily survive with it. After a reload the two disagree -- modData says "WetHeavy applied", the item has its vanilla sprite back -- and `reconcile` returns early because the stage asked for is the one it believes it set. The weapon renders dry forever while the state says soaked, silently, because the return precedes the only log in the function | Justify the early return with the ITEM's live `getWeaponSprite()`, not with our own record of what we asked for. Self-correcting after a reload and after anything else that resets the sprite |
| Logging only from the visual adapter | The adapter returns early when the stage it is asked for is the one already applied, so a weapon that never leaves stage 0 is silent forever -- and `Controller.update` returned silently when there was no player yet. A live-but-idle build and a build whose client Lua never executed produced byte-identical logs. An in-game report of "it was soaked and nothing showed" could not be told apart from "it never got wet", which are opposite problems and cost a full debugging pass | With `DEBUG`, log proof of life at require time, the climate sample and tracked count every tick, and each item's value and stage before reconciling |
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
| Flank alpha reaching 0.90 at high stages | A flank is near-vertical, so its snow is thin by definition; letting the dusting reach near-opaque filled a shotgun stock side with solid white that read as a painted rectangle | Cap flankMaxAlpha at 0.42-0.60 |
| Core statistics measured two different ways | The generator knows the real alpha and reports 0.012-0.019 saturation; the validator's absolute-luma proxy admits bright flank dust over pale wood and reached 0.062 | Strict neutrality asserted on the generator's figure; the pixel pass keeps a loose bound |
| Handguns shipped with an inverted up axis | All six had upSign +1, so snow landed on their undersides. The grip sits at +Z on every handgun mesh, meaning +Z is DOWN when the weapon is held | Grip-side test recovers the sign from geometry and is enforced on every generate |
| Contact sheet rendering every weapon +Z up | It ignored upSign, so a handgun drew grip-up. That looks plausible as an image but is upside down for a held weapon, which is why the visual gate passed six inverted assets | The sheet now renders each weapon the way it is held |
| Crevice and metal affinity multiplying unbounded | A revolver cylinder is deeply fluted AND dark desaturated steel, so it reached nearly 2x affinity, won the global threshold and swallowed the snow budget while the frame stayed bare | Cap the affinity product |
| Assuming every vanilla firearm texture is RGB | PumpAction_Shotgun and M9_Pistol are RGBA with a few hundred semi-transparent edge texels. Forcing alpha to 255 hardened antialiased edges, and a 1:1 GDI+ transfer of an RGBA image is not bit-exact, so the generator and validator counted differently | Preserve source alpha; treat the changed-texel cross-check as a bound, not an exactness claim |
| Saturating the up-facing region at high stages | With targetUpCoverage at 0.96 the top of a UV island filled completely, and once an island is full the visible snow edge is no longer the mask but the edge of the geometry -- straight by definition on a barrel. Two rounds of boundary jitter did nothing because they were raggedizing an edge that was not the one being seen | Ceiling the coverage below saturation so holes always remain |
| Smooth up-facing gate on a cylinder | A barrel is a cylinder, so the set of points at a given surface angle is a circle, which unwraps to a STRAIGHT LINE in UV: snow ended at a ruler-straight edge along the handguard while irregular geometry got a natural boundary. Multiplying by noise scales the value but leaves the iso-line where it is | Jitter the up value before the gate, so the boundary itself is perturbed |
| Absolute `coreTexels >= 3000` | A property of how much atlas a weapon occupies, not of snow quality: JS14 owns 4255 up-facing texels against the Hunting Rifle's 13313 and was rejected at 2136 cores | Require cores to be >=25% of changed texels |
| Absolute coverage band 8-55% of the atlas | Same defect: T_Carabine at 5.3% of its atlas was 31% of its own area | Measure coverage against the weapon's owned atlas area |
| `upShare` floors disagreeing between validators | validate.js kept 0.68 while the PowerShell validator moved to 0.45, so the stricter one rejected a valid M16 stage 4 | Both use the density ratio plus a matching 0.45 floor |
| Accumulation rate scaled by snowfall intensity | Build 42.20 reports precipitation intensity far below 1.0 during snow, so the nominal 8-hours-to-full became 20+ game hours and the mod looked broken: the user watched for hours and never left stage 1 | Intensity gates accumulation; the rate is a fixed one stage per tick |
| Ground weapons simulated but never redrawn | The state advances correctly and shows the right stage once picked up, but the square keeps drawing the old model: no character refresh reaches an IsoWorldInventoryObject. Marking the object dirty (`invalidateRenderChunkLevel` + `setSquareChanged`) was tried and **measured not to fix the 3D case**: the model instance is built when the item lands and is never re-read from its WeaponSprite | Accepted limitation, documented in `EW_VisualAdapter.lua` and in the store description. The dirty calls are kept because they are correct for sprite-drawn world items and cost nothing |
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
- Do not add networking, particles, rust, frost, melee, icons, or other weapons
  during Stage 1 refinement. Wetness shipped on 2026-07-30 and is no longer on
  this list.
- Nothing under `shared/` may require anything under `client/`. A dedicated
  server loads only `shared/`, so one stray require crashes it on boot.
- Do not install over an unknown folder. The target must be absent or contain
  `id=EnvironmentalWeapons`.
- Keep `WorldStaticModel` unset for the Hunting Rifle snow profile.

## Multiplayer

Unpinned by the maintainer on 2026-07-31, who is putting the mod on a server.

### What was actually tested

A dedicated server was booted locally with `Mods=EnvironmentalEffects`, on its
own config and world so nothing existing was touched, and both were deleted
afterwards. Result: **`*** SERVER STARTED ****`**, and zero errors naming this
mod -- no script parse error, no Lua error, no model failure. The only mod-
related lines are `NoSuchFileException` for `media/AnimSets` and
`media/actiongroups`, which is the engine probing for optional folders every mod
without animations lacks.

Structurally that is expected and is worth keeping true: **no file under
`shared/` requires anything under `client/`**. A dedicated server loads only
`shared/`, so a single stray require there would crash it on boot. There is a
one-line check for this at the top of the require graph -- keep it that way.

### Remote players ARE drawn, as of 2026-07-31

Each client now simulates the weapons of every player it can see, not only its
own. `Exposure.remotePlayers` enumerates them and `Exposure.resolveRendered`
returns what is actually drawn on each -- the two hands and anything slung or
holstered -- and the controller runs the same simulation over them.

Three decisions worth keeping:

- **No networking, still.** Weather is global, the other player's square is
  readable locally, and their client runs this same simulation over the same
  inputs, so the two converge without anyone sending anything. The "do not add
  networking" guardrail survives intact.
- **Their item's modData is never written.** A remote weapon's state lives in
  `State.ensureRemote`, an in-memory weak-keyed table. Writing modData on
  someone else's item would be this client deciding what their rifle looks like
  everywhere, which is exactly the reach the mod avoids by never transmitting.
- **Their backpack and the ground near them are skipped.** Bag contents are not
  rendered, so it would be invisible work; ground items near them are already
  covered by the local sweep when the two are close enough to see each other,
  and recording one twice would charge it the elapsed time twice and age it at
  double rate. `simulate` dedupes by item identity as a second line of defence.

### What has NOT been tested live

Everything that moves lives in `client/`, so the server runs none of it and
carries no load from this mod.

**State is per client.** It lives in `item:getModData()` for your own items and
in memory for everyone else's, and the mod never calls `transmitModData()`. It
is unknown whether a server inventory sync overwrites the field on your own
weapon, and whether the server accepts a client-side `setWeaponSprite` on
another player's item or reverts it. If it reverts, the adapter re-applies on
the next tick by design, because its early return is justified against the live
sprite readback rather than against its own record.

Unknown and only answerable in a live session with two players: whether the
server accepts a client-side `setWeaponSprite` or reverts it, and whether the
anti-cheat objects to it. Nothing here touches damage, condition, ammo or any
other stat, so the exposure is cosmetic, but that is reasoning rather than
evidence.

### Nothing verifies the Lua compiles, except block balance

`tools/check_lua_blocks.js` is not a parser and is not trying to be. It catches
one thing -- a missing or extra `end`, an unclosed `repeat` -- which is the
mistake that turns the mod into a mod that silently does not load. Nothing else
in this toolchain reads the shipped Lua at all: `tests/pure_logic_test.js`
exercises a JavaScript mirror of the simulation, not those files, so before this
a syntax error reached the game unopposed. It runs first in the sync pipeline
because it is the cheapest and its failure mode is the most invisible.

A real check would need a Lua runtime and the project takes no new dependencies.

## Open tasks

### 1. Wetness -- DONE, confirmed in game 2026-07-30

Closed. What follows is the record of why it took four passes, because three of
the four went after the wrong thing and the reasoning is worth not repeating.

**The defect was structural, and the last change is the one that fixed it.**
Water had a mask of its own -- a pool field over every surface but the
undersides -- so it gathered in scattered patches. Snow builds from the top down
and creeps onto the flanks; rain does the same. Two phenomena with different
geometry will never look like two states of one weapon, and no amount of tuning
coverage, alpha, darkening or rim strength changed that. `BuildWetMask` now
delegates to `BuildMask`; only the optics differ.

The three passes before it were all real bugs, and all insufficient on their own:

The user's verdict on the first wet build was that the three levels "are not
consistent like the snow". Measuring the shipped textures against the snow ones
found three defects, not the one this file previously recorded.

Per painted texel, against vanilla, on the hunting rifle:

| | painted % | mean signed shift | mean absolute shift |
| --- | --- | --- | --- |
| SnowLight -> SnowFull | 20.5 -> 39.9 | +99 -> +113 | 103 -> 116 |
| WetLight -> WetHeavy, before | 27.6 -> 51.0 | **+23 -> +18 -> +15** | 24 -> 22 -> 22 |
| WetLight -> WetHeavy, after | 22.2 -> 46.4 | **-5 -> -14 -> -21** | 7 -> 17 -> 24 |

1. **Water was brightening the weapon.** `PuddleReflect` mixed pool interiors
   toward luma 168, and firearm atlases are dark, so the reflection beat the
   darkening and every wet core came out paler than the dry weapon. Snow at +110
   and water at +20 push the SAME way, so at gameplay scale wetness could only
   read as thin snow. Reflection now stays in the meniscus: 0.20 -> 0.05.
2. **The levels ramped on area alone.** Their per-texel shift measured 24, 22
   and 22 -- flat. Snow gets away with an area-only ramp because each of its
   texels moves ~110 luma; water has no such margin. Alpha now spans 0.50 to
   1.00 instead of 0.62 to 0.94, so depth ramps too.
3. **The pools were all edge and no interior.** `PuddleEdge` was 0.13 over a
   smooth single-octave field, so 19045 of 20944 core texels still counted as
   rim and alpha almost never reached its ceiling -- and since the darkening is
   scaled by alpha, pools that never saturate can never darken. Now 0.05.

Also: `WetLumaFloor` 26 -> 14. The old "water can only add sheen to the M9
Pistol, it cannot darken it" conclusion was an artefact of that floor sitting
just under the M9's near-black atlas, not a fact about the pistol.

Resulting core darkening ratio, hunting rifle: **0.18 / 0.34 / 0.45**, monotonic
and separated. Every one of the 19 weapons passes a >= 0.06 deepening step.

**Still true and still binding:** snow adds an opaque material of a different
colour, water has none of its own, so water is intrinsically the less legible of
the two. It is now snow's OPPOSITE rather than a weak copy, which is what makes
them distinguishable; do not expect it to match snow for sheer strength.

**Do not fix anything here by raising `PuddleReflect`.** At 0.62 pools over dark
wood came out near-white and the rifle read as mould-spotted.

**Judge every wet change with `tools/gameplay_scale_preview.ps1`.** A rifle is
~1000 px wide on the contact sheet and ~200 px in game. A version that looked
correct at review size shipped completely invisible, twice.

A fourth bug hid all of the above and is worth its own note: a reloaded weapon
rendered dry while its state said soaked, because `state.visual` persists in
modData and the `WeaponSprite` it describes does not. `reconcile` returned early
against its own stale record, silently, since the return precedes the only log
in the function. Two in-game reports were spent on textures that were never
being applied. See the non-regression table.

Shipped values, hunting rifle:

| | coverage | darkening | share on up-facing |
| --- | --- | --- | --- |
| WetLight | 16.7% | 0.20 | 0.94 |
| WetMedium | 24.9% | 0.32 | 0.88 |
| WetHeavy | 36.5% | 0.45 | 0.77 |

Four regression guards now exist so none of this can silently come back. Both
validators reject a wet texture whose core is brighter than vanilla, and one
whose up-facing share falls below 0.35. `validate_snow_textures.ps1` rejects a
wet level that is not at least 0.06 deeper than the level before it. And the
adapter justifies its early return against the item's live sprite readback.

### 2. Scopes -- NOT POSSIBLE with this mod's mechanism. Premise corrected.

**There is no scoped rifle variant in vanilla 42.20.** An earlier version of this
section claimed a mounted scope is drawn as part of the rifle's model and that
feeding the generator a scoped mesh would snow the scope for free. That was
wrong on every point, and it was written from filenames rather than from the
scripts. Measured on 2026-07-31:

- A scope is its own model hung off an anchor: every weapon model declares
  `attachment scope` (and often `scope2`), and vanilla defines
  `model x2Scope { mesh = weapons/parts/Rifle_2XScope, texture =
  weapons/parts/Rifle_12XScope }`, likewise x4, x8 and x12. All four share ONE
  texture.
- `HuntingRifle_Scope.x` and `VarmintRifle_Scope.x` are **the same file**
  (106548 bytes, 575 vertices) and have FEWER vertices than the plain
  `MSR788_Rifle.x` (879), so neither is a rifle-with-scope. `HuntingRifle_Scope.png`
  is a 128x128 atlas of an old wooden rifle. **No vanilla script references any
  of them.** They are dead assets.
**CLOSED 2026-07-31, tested in game.** A route looked plausible and did not
survive contact. Both halves of it are blocked, and this is now measured rather
than assumed in either direction:

- `ModelWeaponPart` is **not exposed to Lua**. The global is nil, so the class
  cannot be constructed and the `ArrayList` that `setModelWeaponPart` takes
  cannot be built.
- Reading a field off a `ModelWeaponPart` returned by `getModelWeaponPart()`
  **raises**. The class declares four public Strings and no accessors, and
  Kahlua exposes methods, not fields. So even the objects the game hands back
  are opaque: they cannot be read and they cannot be edited in place.

`getModelWeaponPart()` and `list:size()` and `list:get(i)` all work, which is
what made this look promising. The objects that come out are useless from Lua.

The evidence that made it look possible, kept because it is correct and only the
Lua reachability was missing:

- The model a mounted part uses is declared on the **weapon**, not on the part:
  `ModelWeaponPart = x2Scope x2Scope scope scope` in `items/weapon.txt` means
  "for part type x2Scope, draw model x2Scope at anchor scope".
- `zombie.scripting.objects.ModelWeaponPart` has four **public** String fields
  (`partType`, `modelName`, `attachmentNameSelf`, `attachmentParent`) and a
  **public no-arg constructor**.
- `HandWeapon` exposes **public** `getModelWeaponPart()` and
  `setModelWeaponPart(ArrayList)`.

On paper that is a per-weapon, per-stage lever. In practice Lua cannot reach it,
per the test above. `EW_DebugProbe.inspectWeaponParts` is kept as the record and
re-runs the whole check in one click; it uses a nil test rather than a blind
call, so it reports instead of tripping the debugger.

The only remaining way to make a scope react would be replacing the shared
`weapons/parts/Rifle_12XScope` texture globally, which is static -- a
permanently snowy scope in July -- and therefore worse than leaving it alone.

**Do not reopen this without new evidence.** It has now been wrong in both
directions: first declared impossible from the wrong reason, then thought
possible from a real API that turns out to be unreachable. If a future build
exposes `ModelWeaponPart` to Lua, the shape is seven derivatives of
`Rifle_12XScope` (one texture covers all four scopes), seven EW scope models,
and a write in the adapter beside the existing `setWeaponSprite` -- and the
first thing to check then is whether the returned list is per-item or shared
with the script object, because a shared list would change every weapon of that
type in the save.

**What was done instead**, because the scope anchor is the fragile part:
`generate_mod_wiring.js` copies vanilla's attachment blocks into all 133 EW
models by brace matching, and nothing verified the copy. A miscopy would move or
drop every mounted part on the affected weapon, silently. `validate.js` now
proves the set is non-empty and identical across a weapon's seven states without
needing the game installed; `validate_snow_textures.ps1` proves it matches the
vanilla anchor set exactly, with the vanilla path derived from the spec rather
than hard-coded.

Decision already taken by the user on 2026-07-30, held for the day the engine
ever allows it: **a scope keeps its own state** when moved between weapons,
because state lives in the item's own modData like everything else in this mod.

## Prioritized next tasks

1. Confirm the natural cycle in game: hold the rifle outdoors in snowfall and
   watch a stage appear every 10 game minutes, then stow it and watch the stages
   come off at the same pace. Confirm a slung rifle also accumulates.
2. Confirm all four stages with the debug probe, then replace the three stale
   screenshots in `docs/evidence`.
3. Revalidate save/load and restore in a disposable single-player save, watching
   for visible popping at the stage thresholds.
4. Three firearms remain blocked on the generator's fixed 256x256 assumption:
   Revolver_CapGun and Rifle_CapGun at 64x64, L94_Rifle at 2048x2048. Making the
   size dynamic is contained work, but the normal buffer supersamples 4x, so a
   2048 atlas would need an 8192x8192 buffer (~500 MB) unless the supersample
   factor drops for large textures. L94_Rifle is worth it; the two toy guns are
   not.
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

There is no separate copyable brief. This document is the brief: the status
table, the guardrails, and the prioritized tasks above are what a new session
needs. A standalone prompt file existed and was deleted on 2026-07-30 because it
had drifted into describing a Stage-1-only, one-weapon scope that stopped being
true many commits earlier.
