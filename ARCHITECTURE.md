# Architecture and behavior

## Runtime flow

`EW_Controller` runs on `EveryTenMinutes` and once on `OnGameStart`. It resolves
every tracked weapon the player carries, samples climate, advances each
persistent snow value using elapsed game minutes, resolves a visual stage with
hysteresis, and asks the isolated visual adapter to reconcile the item. The
controller owns the interval clock and remembers which items it saw on the
previous run. A newly observed item receives zero elapsed minutes, so time before
it was carried can never be charged retroactively.

Primary and secondary hands are deduplicated by Lua object identity, which is
important for two-handed rifles.

## Exposure

`EW_Exposure` walks the player's hands and then their inventory, recursing into
bags to a bounded depth, and classifies every profiled weapon:

| Location | Exposed | Behaviour in a snowstorm |
| --- | --- | --- |
| Primary or secondary hand | yes | accumulates |
| Attached to a body slot (slung, holstered) | yes | accumulates |
| Loose in inventory or inside a bag | no | thaws |

Body attachment is read from `getAttachedSlot()`, with `getAttachedSlotType()` as
a fallback. Tracking stowed weapons is what allows snow to melt off them at all;
before this, a snowy rifle put in a bag stayed snowy forever.

## Persistent schema

Each tracked item owns `item:getModData().EnvironmentalWeapons` with schema
version 1. It records snow `0..100`, stage, last update time, original visual
channels, and the last adapter-owned visual values. The item is never replaced,
so condition, attachments, ammunition, name, favorite state, and item identity
remain untouched.

## Snow behavior

The rate is expressed as **one visual stage per controller tick** in each
direction: 25 points per 10 game minutes. An exposed weapon in snowfall reaches
full cover in 40 game minutes, and a thawing one is bare 40 minutes later.

| Situation | Change per 10 game minutes |
| --- | ---: |
| Exposed, outdoors, snowing, at or below 0.5 C | +25 |
| Exposed, outdoors, **raining** — at any temperature | -25 |
| Sheltered in a container | -25 |
| Indoors | -25 |
| Outdoors above 0 C | -25 |
| Outdoors below 0 C, no precipitation | 0 (holds) |

Rain strips snow **even below freezing**. Liquid water is falling, so it carries
heat and washes the surface, and Build 42 can report sub-zero air temperature
while it rains — so temperature alone must not gate this. Rain is derived as
active precipitation that is not snow, with `RainManager.isRaining()` as a
fallback if the intensity channel reports nothing.

Snowfall intensity **gates** accumulation rather than scaling it. Build 42.20
reports precipitation intensity well below 1.0 during snow, and the earlier
proportional rate stretched stage 2 past 20 game hours, which read in game as the
mod not working. `Config.Snow.scaleWithIntensity` restores proportional rates for
anyone who prefers them.

Accumulation still requires `getPrecipitationIsSnow()`, so rain never leaves
snow. Snow held outdoors below freezing does not quietly drain away; it only
retreats when sheltered, rained on, or warm enough to thaw.

Because the rate is derived per minute rather than per tick, a coalesced or
skipped tick advances the correct amount instead of losing time.

All results are clamped to `0..100`. Stage entry thresholds are 20, 45, 70, and
90%; a 4-point hysteresis prevents rapid visual toggling. `tools/validate.js`
proves that one tick crosses exactly one threshold and that `minutesPerStage`
matches the controller's subscribed interval.

## Visual safety

The Hunting Rifle has five explicit stage slots. Stages 1-4 each link a
deterministic equipped model of increasing snow cover; every world slot is
deliberately `nil`. Dropped rifles therefore use the engine's specialized
`HandWeapon` fallback, preserving rifle rotation and the model's `world`
attachment while retaining the custom WeaponSprite texture. A missing asset
causes no visual mutation. The adapter owns
only `setWeaponSprite`, `setWorldStaticModel`, `setTexture`, and the model
refresh calls.

Before any possible mutation the state snapshots exactly the channels the adapter
restores: the original `WeaponSprite`, and whether an adapter-owned
`worldStaticModel` override existed. Earlier versions also captured the static
model, model index and icon name, which read as extra safety but were never
restored from, so they were removed rather than left implying a guarantee that did
not exist. Icon restore uses a runtime snapshot of the item's texture, falling
back to the ScriptItem's normal texture.

## Making a stage change visible

A stage change must reach the rendered model in every pose, and two separate
failures produced the same symptom of "the console says it changed but the rifle
looks the same until I stand up":

- `resetEquippedHandsModels()` rebuilds hand attachments only, and that rebuild
  does not reach the rendered model while the character is seated or lying down.
  Standing up forces a full rebuild, which is why the change appeared then.
- A weapon slung on the back is not a hand attachment at all, so it received no
  refresh whatsoever, in any pose.

The adapter therefore refreshes whenever the item is **rendered on the
character** — in hand or in a body slot — and requests both the targeted
`resetEquippedHandsModels()` and the deferred `resetModelNextFrame()`, which is
the full rebuild vanilla itself uses for appearance changes. The cheap call lands
immediately when it can; the deferred one guarantees the change is not stuck until
the pose changes. A stage change happens at most once per controller tick, so the
cost is irrelevant.

A weapon stowed inside a container is not rendered and is deliberately not
refreshed; equipping it triggers the engine's own rebuild.

An absent original world override is restored by clearing only the adapter-owned
`worldStaticModel` modData value; `nil` is never passed to the Java setter.
The adapter also migrates the retired `EW_HuntingRifle_SnowLight_World` value
only when the item state proves it was adapter-owned; external overrides are
left untouched.

## Confirmed 42.20 evidence

- `Base.HuntingRifle`: WeaponSprite `HuntingRifle`, equipped model
  `Base.HuntingRifle`, mesh `weapons/firearm/MSR788_Rifle`.
- Vanilla Lua uses `Events.EveryTenMinutes`, `Events.OnGameStart`,
  `getClimateManager():getPrecipitationIsSnow()`,
  `getClimateManager():getSnowStrength()`,
  `getClimateManager():getPrecipitationIntensity()`,
  `getClimateManager():getAirTemperatureForCharacter(player, false)`, and
  `square:isOutside()`.
- The prior isolated 42.20 test proved per-instance `setWeaponSprite`,
  `setWorldStaticModel`, icon mutation, persistence, and
  `resetEquippedHandsModels` refresh without replacing the item.

## Explicit exclusions

No networking, multiplayer synchronization, particles, rust, wetness, frost,
melee profiles, final icons, or a complete visual stage set are included.
