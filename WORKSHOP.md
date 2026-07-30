# Workshop release notes

Two things in one file: the player-facing description, ready to paste, and the
checklist of what still blocks publication. Read the checklist first — **this
build cannot be uploaded as it stands**, and one of the blockers is not technical.

---

## Pre-publication checklist

| # | Blocker | Status |
| --- | --- | --- |
| 1 | **Asset rights.** The textures are derivatives of the installed Project Zomboid art. | **Unresolved — yours to settle** |
| 2 | `DEBUG = true` exposes a "force stage" menu to every player. | Not started |
| 3 | The toolchain would need excluding, and `mod.info` rewriting. | Partly done |
| 4 | No multiplayer support. | Not started |
| 5 | No Workshop poster image. | Not started |

### 1. Asset rights — settle this before anything else

Every snow texture is generated from the vanilla weapon art in your own game
install. Publishing them means redistributing The Indie Stone's artwork.

Reusing and recolouring vanilla textures is extremely common on the PZ Workshop,
and mods only function for people who own the game. That is context, not
permission: check TIS's current mod and asset policy yourself. Nobody in this
project can grant it for you.

There is no clean technical escape. Project Zomboid cannot generate PNGs at
runtime from Lua, so "let each player derive it from their own install" is not
achievable. Shipping the images is the only practical route.

If the answer is no, the realistic options are keeping this as a personal build,
or commissioning original artwork — which is a different project.

### 2. `DEBUG = true`

`mod/42/media/lua/shared/EnvironmentalWeapons/EW_Config.lua` currently ships with
debug on, which puts *EW Debug: force stage 1-4* and *restore vanilla* in every
player's right-click menu. Set it to `false` for release. The probe is already
fail-closed behind that flag, so nothing else needs touching.

### 3. Packaging

`mod/` is already the only thing mirrored, zipped and installed, so the toolchain
is not shipped. What remains is `mod/42/mod.info`, which still reads:

```
name=Environmental Weapons - Development Test
description=Development test build for single-player Hunting Rifle snow visuals. Not a release build.
```

It needs a real name, description and version. The current ZIP is about 5.8 MB.

### 4. Multiplayer

There is none, deliberately, and the validator forbids networking calls in this
slice. Workshop mods get used on servers, so expect it to be reported as broken
there. Either implement synchronisation or say plainly in the description that
this is single-player only.

### 5. Poster

Workshop wants a preview image. `mod/42/poster.png` does not exist yet.

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
