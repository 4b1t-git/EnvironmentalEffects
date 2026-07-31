# Workshop release notes

Two things in one file: the player-facing description, ready to paste, and the
checklist of what still blocks publication. Read the checklist first — **this
build cannot be uploaded as it stands**, and one of the blockers is not technical.

---

## Pre-publication checklist

Every row below was re-verified against the working tree on 2026-07-30.

| # | Blocker | Status | Verified by |
| --- | --- | --- | --- |
| 1 | **Asset rights.** The textures are derivatives of the installed Project Zomboid art. | **Resolved 2026-07-30 by the maintainer** | Maintainer's own review; see below |
| 2 | `DEBUG = true` exposes a "force stage" menu to every player. | Not started | `EW_Config.lua` still reads `DEBUG = true` |
| 3 | `mod.info` still identifies the build as a development test, and carries no version. | Partly done | Identity fixed 2026-07-30; `name` still says "Development Test" |
| 4 | No multiplayer support. | Not started | No networking calls; the validator forbids them in this slice |
| 5 | No Workshop poster image. | Not started | `mod/42/poster.png` does not exist |

Toolchain exclusion, previously listed as a blocker, is **done**: `mod/` is the
only tree mirrored, zipped and installed, so `tools/`, `tests/`, `docs/` and the
project Markdown never reach a player.

### 1. Asset rights — resolved

Every snow texture is generated from the vanilla weapon art in the maintainer's
own game install, so publishing them means redistributing The Indie Stone's
artwork. Reusing and recolouring vanilla textures is common practice on the PZ
Workshop, and the mod only functions for people who already own the game.

**The maintainer reviewed this on 2026-07-30 and considers it settled: the mod
may be published.** No specific policy citation was recorded at the time. If this
is ever challenged, record the reasoning here rather than re-litigating it from
memory.

Kept for context, because it constrains any future re-think: there is no clean
technical escape. Project Zomboid cannot generate PNGs at runtime from Lua, so
"let each player derive the textures from their own install" is not achievable.
Shipping the images is the only practical route — the alternatives are a personal
build, or commissioned original artwork, which is a different project.

> **2026-07-31: blockers 2, 3, 4 and 5 are RESOLVED.** `DEBUG` is `false`,
> `mod.info` carries the release name plus `modversion=1.0.0` and `poster`,
> `mod/42/poster.png` exists, and multiplayer works with remote players drawn.
> The upload folder is built by `tools/build_workshop_package.ps1` and lives at
> `%USERPROFILE%\Zomboid\Workshop\Environmental Effects`. The sections below are
> kept as the record of what each blocker was.
>
> **The one thing still unverified:** the multiplayer code has never run in a
> live session with two players. It boots a dedicated server clean and passes
> every validator, which proves it loads, not that it works.

### 2. `DEBUG = true`

`mod/42/media/lua/shared/EnvironmentalWeapons/EW_Config.lua` currently ships with
debug on, which puts *EW Debug: force stage 1-4* and *restore vanilla* in every
player's right-click menu. Set it to `false` for release. The probe is already
fail-closed behind that flag, so nothing else needs touching.

### 3. `mod.info`

The identity was settled on 2026-07-30, while the mod was still unpublished and
changing it was still free. `mod/42/mod.info` now reads:

```
name=Environmental Effects - Development Test
id=EnvironmentalEffects
description=Development test build for single-player weapon snow visuals across nineteen vanilla firearms. Not a release build.
```

`id` is now frozen. Project Zomboid binds saves to it, so changing it after
publication orphans every save that uses the mod. The sync tooling also refuses
to install over a folder whose `mod.info` carries a different id.

What remains for release: drop "Development Test" from `name`, and add a version.
The parser accepts more keys than this file uses — verified against
`ChooseGameInfo$Mod` in the game jar, which recognises `modVersion`, `versionMin`,
`versionMax`, `require`, `incompatible`, `poster` and `packs`. `require` is what
would let a future companion mod depend on this one.

The current ZIP is about 5.7 MiB.

### 4. Multiplayer

There is none, deliberately, and the validator forbids networking calls in this
slice. Workshop mods get used on servers, so expect it to be reported as broken
there. Either implement synchronisation or say plainly in the description that
this is single-player only.

### 5. Poster

Workshop wants a preview image. `mod/42/poster.png` does not exist yet.

### Not a blocker, but do not "fix" it again

The dropped-weapon redraw limitation stated in the description below is settled,
not open. Commit `c7b1ce2` implemented the obvious fix — mark the world object
dirty with `invalidateRenderChunkLevel(FBORenderChunk.DIRTY_REDRAW)` plus
`square:setSquareChanged()`, which is how vanilla marks any changed world object
— and it was then measured **not** to rebuild a 3D world model. The model
instance is created when the item lands and is never re-read from the item's
`WeaponSprite` afterwards. The calls are still in `EW_VisualAdapter.lua` because
they are correct for sprite-drawn world items and cost nothing, with the measured
result recorded beside them. The simulation itself was never affected: state
advances correctly on the ground and the right level shows the instant the weapon
is picked up.

---

## Description (paste-ready)

### Environmental Weapons — Snow

Your guns remember the weather.

Carry a rifle through a snowstorm and snow settles on it: on the barrel, along
the receiver, on top of the stock. Step inside and it thaws. Leave it out in the
cold and clear, and it simply stays. Nineteen vanilla firearms, four levels of
cover each.

**Snow goes where snow would go.** Placement is derived from each weapon's actual
3D mesh, not painted on. Snow settles on surfaces that face up and skips the
undersides, so a barrel gets a cap and the trigger guard stays clean. It packs
into recesses around the bolt and sight base, and takes hold on cold metal before
it does on a wooden stock.

**It builds and melts as you play.** A weapon out in snowfall gains a level every
ten in-game minutes and loses one at the same pace once it is sheltered or warm.
Nothing is instant and nothing is permanent.

**Where you carry it matters.**

- In your hands, or slung on your back: fully exposed.
- Holstered: still collecting, at about half the rate — the holster covers most
  of the frame.
- Stowed in a bag: sheltered, so it thaws.
- Dropped on the ground nearby: judged by where it lies, not where you stand.

**Rain strips it, even below freezing.** Liquid water is falling, so it washes
the snow off regardless of what the thermometer says. Snowfall builds; rain
clears. Rain never leaves snow behind.

**Your weapon is never replaced.** The mod changes appearance only. Ammunition,
magazine, chambered round, condition, custom name, favourite state and every
attachment are untouched, and the original look is restored exactly when the snow
goes.

#### Covered weapons

Assault Rifle · Assault Rifle (M14) · Hunting Rifle · MSR7T Tactical Rifle ·
Varmint Rifle · JS-14 Rifle · L92 Carbine · Trapper Carbine · Shotgun ·
Sawn-off Shotgun · Double Barrel Shotgun · Sawn-off Double Barrel ·
JS-3T Tactical Shotgun · M9 Pistol · M1911 Pistol · Desert Eagle ·
M625 Revolver · Magnum Revolver · M36 Revolver

#### Not covered

The two cap guns and the L94 Rifle. Their textures are 64×64 and 2048×2048 while
the generator assumes 256×256; support is planned. Weapon attachments such as
scopes do not carry snow yet.

#### Known limitations

- **Single-player.** No multiplayer synchronisation.
- **A weapon already lying on the ground keeps the look it had when dropped.**
  Its snow still builds and melts correctly underneath, and the right level shows
  the moment you pick it up. Project Zomboid builds a dropped item's model once
  and never re-reads it, and vanilla itself never changes the appearance of an
  item on the ground, so there is no safe way to force it.
- Weapons more than ten tiles away are not simulated until you come back.

#### Compatibility

Build 42.20. Touches no vanilla files, no saves and no other mod's assets: it
only sets a weapon's own sprite and stores its snow level in that item's own
data. Safe to remove — weapons revert to their normal appearance.
