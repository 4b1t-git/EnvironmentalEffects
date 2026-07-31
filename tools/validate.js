"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const root = path.resolve(__dirname, "..");
// `mod` is the deliverable: exactly what gets mirrored, zipped and installed.
// Everything else in the project is toolchain that never reaches a player.
const modRoot = path.join(root, "mod");
const resolve = rel => path.join(rel.startsWith("42/") ? modRoot : root, rel);
const required = [
  "42/mod.info",
  "42/media/lua/client/EnvironmentalWeapons/EW_Controller.lua",
  "42/media/lua/client/EnvironmentalWeapons/EW_Climate.lua",
  "42/media/lua/client/EnvironmentalWeapons/EW_DebugProbe.lua",
  "42/media/lua/client/EnvironmentalWeapons/EW_Exposure.lua",
  "42/media/lua/client/EnvironmentalWeapons/EW_VisualAdapter.lua",
  "42/media/lua/shared/EnvironmentalWeapons/EW_Config.lua",
  "42/media/lua/shared/EnvironmentalWeapons/EW_State.lua",
  "42/media/lua/shared/EnvironmentalWeapons/EW_Simulation.lua",
  "42/media/lua/shared/EnvironmentalWeapons/EW_StageResolver.lua",
  "42/media/lua/shared/EnvironmentalWeapons/EW_Profiles.lua",
  "42/media/scripts/models_EnvironmentalWeapons.txt",
  "42/media/textures/weapons/firearm/EW_MSR788_Rifle_SnowLight.png",
  "assets/snow_texture_manifest.json",
  "tools/snow_assets.json",
  "tools/generate_snow_textures.ps1",
  "tools/replay_snow_textures.ps1",
  "tools/validate_snow_textures.ps1",
  "tools/preview_snow_textures.js",
  "tools/generate_mod_wiring.js",
];
for (const rel of required) {
  if (!fs.existsSync(resolve(rel))) throw new Error(`Missing ${rel}`);
}
const luaFiles = required.filter(x => x.endsWith(".lua"));
const joined = luaFiles.map(x => fs.readFileSync(resolve(x), "utf8")).join("\n");
if (/\bOnTick\b/.test(joined)) throw new Error("OnTick is forbidden");
if (/sendClientCommand|sendServerCommand|OnClientCommand|OnServerCommand/.test(joined)) {
  throw new Error("Networking code is forbidden in the single-player slice");
}
if (!/Base\.HuntingRifle/.test(joined) || !/HuntingRifle/.test(joined)) {
  throw new Error("Initial rifle profile missing");
}
if (!/getPrecipitationIsSnow/.test(joined)) {
  throw new Error("Active snow precipitation gate missing");
}
// Rain must strip snow even below freezing. The channel has to be sampled,
// forwarded by the controller, and consumed by the simulation; dropping any one
// of the three would silently restore the bug where snow survived a downpour.
const rainWiring = [
  ["42/media/lua/client/EnvironmentalWeapons/EW_Climate.lua", /resolveRainIntensity/],
  ["42/media/lua/client/EnvironmentalWeapons/EW_Controller.lua", /rainIntensity\s*=\s*climate\.rainIntensity/],
  ["42/media/lua/shared/EnvironmentalWeapons/EW_Simulation.lua", /sample\.rainIntensity/],
];
for (const [rel, pattern] of rainWiring) {
  const body = fs.readFileSync(resolve(rel), "utf8");
  if (!pattern.test(body)) throw new Error(`Rain melt wiring missing in ${rel}`);
}
// Nothing under shared/ may require anything under client/.
//
// A dedicated server loads only shared/, so a single stray require there is a
// crash on boot for every server running the mod -- the kind of break that
// cannot be found in single-player at all. Verified clean against a real
// dedicated server on 2026-07-31; this keeps it that way.
{
  const sharedDir = resolve("42/media/lua/shared/EnvironmentalWeapons");
  const clientDir = resolve("42/media/lua/client/EnvironmentalWeapons");
  const clientModules = new Set(
    fs.readdirSync(clientDir)
      .filter(f => f.endsWith(".lua"))
      .map(f => f.slice(0, -4))
  );
  if (clientModules.size === 0) throw new Error("no client modules found to check against");
  for (const file of fs.readdirSync(sharedDir).filter(f => f.endsWith(".lua"))) {
    const text = fs.readFileSync(path.join(sharedDir, file), "utf8");
    for (const m of text.matchAll(/require\s*"([^"]+)"/g)) {
      const module = m[1].split("/").pop();
      if (clientModules.has(module)) {
        throw new Error(
          `shared/${file} requires client-only ${m[1]}; a dedicated server ` +
            `loads shared/ without client/ and would crash on boot`
        );
      }
    }
  }
}

const models = fs.readFileSync(resolve("42/media/scripts/models_EnvironmentalWeapons.txt"), "utf8");
for (const reference of [
  "EW_HuntingRifle_SnowLight",
  "weapons/firearm/MSR788_Rifle",
  "weapons/firearm/EW_MSR788_Rifle_SnowLight",
]) {
  if (!models.includes(reference)) throw new Error(`Model reference missing: ${reference}`);
}
if (/model EW_HuntingRifle_SnowLight_World\b/.test(models)) {
  throw new Error("Legacy world model must not be registered");
}

// Every EW model must carry the vanilla model's attachment points, and all of a
// weapon's states must carry the SAME ones.
//
// This is what keeps a scoped rifle working. A mounted scope is not part of the
// rifle mesh: vanilla declares `attachment scope` on the weapon model and hangs
// the separate x2Scope/x4Scope/x8Scope model off that anchor. Swapping the
// weapon's WeaponSprite to an EW model therefore swaps the anchor set too, and a
// model that lost its attachment blocks would leave every mounted part -- scope,
// muzzle, bayonet, recoil pad, red dot -- with nowhere to sit. Nothing checked
// this before, and generate_mod_wiring.js copies those blocks out of the vanilla
// script by brace matching, which is exactly the kind of thing that fails
// quietly and only on some weapons.
{
  const byModel = new Map();
  const re = /model\s+(EW_\w+)\s*(?:\r?\n)?\s*\{/g;
  let match;
  while ((match = re.exec(models))) {
    const name = match[1];
    let depth = 0;
    const open = models.indexOf("{", match.index);
    let body = null;
    for (let i = open; i < models.length; i++) {
      if (models[i] === "{") depth++;
      else if (models[i] === "}" && --depth === 0) {
        body = models.slice(open + 1, i);
        break;
      }
    }
    if (body === null) throw new Error(`${name}: unterminated model block`);
    const attachments = [...body.matchAll(/attachment\s+(\w+)/g)].map(a => a[1]).sort();
    if (attachments.length === 0) {
      throw new Error(
        `${name}: declares no attachment points; a mounted scope or muzzle ` +
          `device would have no anchor on this state`
      );
    }
    byModel.set(name, attachments.join(","));
  }
  if (byModel.size === 0) throw new Error("no EW models found to check attachments on");

  // States of one weapon share a name prefix: EW_<weapon>_<state>.
  const byWeapon = new Map();
  for (const [name, attachments] of byModel) {
    const weapon = name.replace(/_(Snow|Wet)[A-Za-z]+$/, "");
    if (weapon === name) throw new Error(`${name}: cannot derive a weapon from the model name`);
    if (!byWeapon.has(weapon)) byWeapon.set(weapon, new Map());
    byWeapon.get(weapon).set(name, attachments);
  }
  for (const [weapon, states] of byWeapon) {
    const distinct = new Set(states.values());
    if (distinct.size > 1) {
      const detail = [...states].map(([n, a]) => `${n}=[${a}]`).join(" ");
      throw new Error(
        `${weapon}: states disagree on their attachment points, so a mounted ` +
          `part would move or vanish as the weapon ices up or dries: ${detail}`
      );
    }
  }
}
const profiles = fs.readFileSync(resolve("42/media/lua/shared/EnvironmentalWeapons/EW_Profiles.lua"), "utf8");
if (!/\[1\]\s*=\s*\{[\s\S]*?worldModel\s*=\s*nil/.test(profiles)) {
  throw new Error("Hunting Rifle Stage 1 must use HandWeapon world fallback");
}
const debugProbe = fs.readFileSync(resolve("42/media/lua/client/EnvironmentalWeapons/EW_DebugProbe.lua"), "utf8");
if (!/if not Config\.DEBUG then return end/.test(debugProbe)) {
  throw new Error("Debug probe is not fail-closed behind Config.DEBUG");
}

// The accumulation rate is expressed as "one stage per tick", so the configured
// minutesPerStage has to equal the controller's actual interval or every stage
// silently takes the wrong amount of game time.
const config = fs.readFileSync(resolve("42/media/lua/shared/EnvironmentalWeapons/EW_Config.lua"), "utf8");
const controller = fs.readFileSync(resolve("42/media/lua/client/EnvironmentalWeapons/EW_Controller.lua"), "utf8");
const eventInterval = { EveryTenMinutes: 10, EveryHours: 60, EveryDays: 1440 };
const updateEvent = /UPDATE_EVENT\s*=\s*"(\w+)"/.exec(config);
if (!updateEvent) throw new Error("Config.UPDATE_EVENT is missing");
const expectedMinutes = eventInterval[updateEvent[1]];
if (expectedMinutes === undefined) {
  throw new Error(`Unknown update event interval: ${updateEvent[1]}`);
}
if (!new RegExp(`Events\\.${updateEvent[1]}\\.Add`).test(controller)) {
  throw new Error(`Controller does not subscribe to ${updateEvent[1]}`);
}
const minutesPerStage = /minutesPerStage\s*=\s*([\d.]+)/.exec(config);
if (!minutesPerStage) throw new Error("Config.Snow.minutesPerStage is missing");
if (Number(minutesPerStage[1]) !== expectedMinutes) {
  throw new Error(`minutesPerStage ${minutesPerStage[1]} does not match ${updateEvent[1]} (${expectedMinutes})`);
}

// One tick must cross exactly one stage boundary in each direction.
const percentPerStage = /percentPerStage\s*=\s*([\d.]+)/.exec(config);
if (!percentPerStage) throw new Error("Config.Snow.percentPerStage is missing");
const thresholdList = /thresholds\s*=\s*\{([^}]*)\}/.exec(config);
if (!thresholdList) throw new Error("Config.Stages.thresholds is missing");
const thresholds = thresholdList[1].split(",").map(x => Number(x.trim())).filter(x => !Number.isNaN(x));
const perTick = Number(percentPerStage[1]);
let previous = 0;
for (const threshold of thresholds) {
  if (threshold - previous > perTick) {
    throw new Error(`Stage gap ${previous}->${threshold} exceeds one tick of ${perTick}`);
  }
  previous = threshold;
}
// Expected hashes live only in the manifest, so a texture change touches one
// file instead of constants copied into three scripts. The manifest is a
// delivered artifact, so editing it moves the canonical tree hash, and
// validate_snow_textures.ps1 re-proves the pixel properties from the images.
const spec = JSON.parse(fs.readFileSync(path.join(root, "tools/snow_assets.json"), "utf8"));
const textureManifest = JSON.parse(fs.readFileSync(path.join(root,
  "assets/snow_texture_manifest.json"), "utf8"));
if (textureManifest.schema !== 1) {
  throw new Error(`Unsupported manifest schema: ${textureManifest.schema}`);
}

const specIds = spec.assets.map(a => a.id).sort();
const manifestIds = Object.keys(textureManifest.assets).sort();
if (specIds.join(",") !== manifestIds.join(",")) {
  throw new Error(`Spec assets [${specIds}] do not match manifest assets [${manifestIds}]`);
}
for (const asset of spec.assets) {
  if (asset.visuallyVerified !== true) {
    throw new Error(`${asset.id} ships without visual verification`);
  }
}
for (const [id, entry] of Object.entries(textureManifest.assets)) {
  const texture = fs.readFileSync(path.join(modRoot, entry.output));
  const recipe = fs.readFileSync(path.join(root, entry.recipe));
  if (!recipe.equals(texture)) {
    throw new Error(`${id}: frozen recipe differs from delivered texture`);
  }
  const textureSha = crypto.createHash("sha256").update(texture).digest("hex");
  if (entry.outputSha256 !== textureSha) {
    throw new Error(`${id}: manifest outputSha256 ${entry.outputSha256} != texture ${textureSha}`);
  }
  // Snow and wetness get separate assertions rather than one loosened set.
  // Snow must be bright and neutral; wet must be darker or shinier than the
  // vanilla pixels and is usually saturated. Relaxing the snow bounds until
  // both fitted would have thrown away the guarantee that snow reads as snow.
  if (entry.mode === "wet") {
    // Water accumulates from the top down and creeps onto the flanks as it
    // builds, on the same mask snow uses. An earlier version claimed there was
    // no placement to assert here because "rain reaches every surface", gave
    // water a scattered field of its own, and in game it read as staining
    // rather than as a weapon getting wet. The bar is below snow's 0.45
    // because water runs down the flanks by design: concentrated up top, not
    // confined there.
    if (!(entry.wetUpShare >= 0.35)) {
      throw new Error(
        `${id}: water is not concentrated on up-facing surfaces: ${entry.wetUpShare}`
      );
    }
    if (!(entry.relativeLumaShift > 0)) {
      throw new Error(`${id}: wet texture records no shift from vanilla: ${entry.relativeLumaShift}`);
    }
    // Water darkens; snow brightens. Without this the two phenomena were free to
    // move a weapon the same way, and they did: every wet core shipped BRIGHTER
    // than vanilla, so at gameplay scale wetness read as a thin coat of snow
    // rather than as its own state.
    if (!(entry.relativeSignedLumaShift < 0)) {
      throw new Error(
        `${id}: wet texture brightens rather than darkens (${entry.relativeSignedLumaShift}); ` +
          `that reads as snow in game`
      );
    }
    if (!(entry.coreWetSaturation > 0)) {
      throw new Error(`${id}: wet texture lost all colour: ${entry.coreWetSaturation}`);
    }
    if (!(entry.coreTexels > 0)) {
      throw new Error(`${id}: wet texture has no wetted core`);
    }
  } else {
    // Density, not share, is the placement invariant that survives a four-stage
    // progression: a heavily covered weapon legitimately carries flank mass. This
    // floor must match validate_snow_textures.ps1; they disagreed once (0.68 here
    // against 0.45 there) and the stricter one rejected a valid stage 4.
    if (!(entry.densityRatio >= 1.3)) {
      throw new Error(`${id}: up-facing snow is not denser than flank snow: ${entry.densityRatio}`);
    }
    if (!(entry.upShare >= 0.45)) {
      throw new Error(`${id}: snow is not concentrated on up-facing surfaces: ${entry.upShare}`);
    }
    if (!(entry.coreSnowSaturation <= 0.06)) {
      throw new Error(`${id}: snow core is tinted rather than neutral: ${entry.coreSnowSaturation}`);
    }
    if (!(entry.coreSnowLuma >= 205)) {
      throw new Error(`${id}: snow core is too dark to read: ${entry.coreSnowLuma}`);
    }
  }
  if (entry.outputIntroducesTransparency !== false) {
    throw new Error(`${id}: manifest admits introduced transparency`);
  }
}
if (/byWeaponSprite/.test(profiles)) {
  throw new Error("Generic WeaponSprite profile fallback is forbidden");
}
const adapter = fs.readFileSync(resolve("42/media/lua/client/EnvironmentalWeapons/EW_VisualAdapter.lua"), "utf8");
if (/safeCall\(item,\s*"setWeaponSprite",\s*state\.original\.weaponSprite\)/s.test(adapter)) {
  throw new Error("Original WeaponSprite restore must be nil-guarded");
}
if (!/if state\.original\.weaponSprite then[\s\S]{0,220}setWeaponSprite/.test(adapter)) {
  throw new Error("Guarded original WeaponSprite restore missing");
}
if (!/LEGACY_WORLD_MODEL\s*=\s*"EW_HuntingRifle_SnowLight_World"/.test(adapter)
    || !/tostring\(current\)\s*~=\s*LEGACY_WORLD_MODEL/.test(adapter)) {
  throw new Error("Guarded legacy world override migration missing");
}
if (/setWorldStaticModel",\s*nil/.test(adapter)) {
  throw new Error("nil must never be passed to setWorldStaticModel");
}
// A stage change has to reach the rendered model in every pose. Two distinct
// failures produced the same symptom: a slung weapon got no refresh at all
// because it is not a hand attachment, and while seated even the hand refresh did
// not land until the player stood up. Both calls, and the slung case, must stay.
if (!/resetEquippedHandsModels/.test(adapter)) {
  throw new Error("Targeted hands refresh missing from the visual adapter");
}
if (!/resetModelNextFrame/.test(adapter)) {
  throw new Error("Deferred full model refresh missing; seated poses would not update");
}
if (!/Exposure\.attachedToBody/.test(adapter)) {
  throw new Error("Slung weapons would not be refreshed on a stage change");
}
// A weapon on the ground is an IsoWorldInventoryObject; no character refresh
// reaches it, so the square kept drawing the old model until it was picked up.
if (!/invalidateRenderChunkLevel/.test(adapter)) {
  throw new Error("Ground weapons would not redraw on a stage change");
}
const controllerBody = fs.readFileSync(resolve(
  "42/media/lua/client/EnvironmentalWeapons/EW_Controller.lua"), "utf8");
if (!/exposure\.worldObject/.test(controllerBody)) {
  throw new Error("Controller does not forward the world object to the adapter");
}
const exposure = fs.readFileSync(resolve("42/media/lua/client/EnvironmentalWeapons/EW_Exposure.lua"), "utf8");
// Dropped weapons must be simulated, and the sweep must stay bounded: ground
// items are world objects on squares, so cost scales with area rather than with
// what the player carries.
if (!/getWorldObjects/.test(exposure)) {
  throw new Error("Ground sweep missing; dropped weapons would never thaw or accumulate");
}
const groundRadius = /GROUND_RADIUS\s*=\s*(\d+)/.exec(exposure);
if (!groundRadius) throw new Error("Ground sweep has no bounded radius");
if (Number(groundRadius[1]) > 16) {
  const squares = (2 * Number(groundRadius[1]) + 1) ** 2;
  throw new Error(`Ground sweep radius ${groundRadius[1]} is too wide: ${squares} squares per tick`);
}
if (!/Exposure\.attachedToBody/.test(exposure)) {
  throw new Error("EW_Exposure must export attachedToBody for the visual adapter");
}
if (!/getAttachedSlot/.test(exposure)) {
  throw new Error("Body-slot exposure detection missing");
}
// Version-control metadata is not part of the delivered mod. Without this the
// manifest absorbs every file under .git the moment the source tree is placed in
// a repository, which breaks work/output parity against a clean checkout.
const EXCLUDED_DIRECTORIES = new Set([".git", ".svn", ".hg"]);
const files = [];
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory() && EXCLUDED_DIRECTORIES.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else files.push(path.relative(modRoot, full).replaceAll("\\", "/"));
  }
}
walk(modRoot);
const manifest = files.filter(x => x !== "artifact_manifest.json").sort().map(rel => {
  const data = fs.readFileSync(path.join(modRoot, rel));
  return { path: rel, bytes: data.length, sha256: crypto.createHash("sha256").update(data).digest("hex") };
});
fs.writeFileSync(path.join(root, "artifact_manifest.json"), JSON.stringify({
  artifact: "EnvironmentalEffects",
  target: "Project Zomboid 42.20 single-player",
  files: manifest,
}, null, 2) + "\n");
console.log(`validate: PASS (${manifest.length} files)`);
