"use strict";
// Adds the wet entries to tools/snow_assets.json, one set per weapon, derived
// from that weapon's stage 1 snow entry.
//
// Written as a generator rather than by hand for the same reason the model
// wiring is: nineteen weapons times three levels is fifty-seven near-identical
// blocks, and every mesh path, source path and axis in them has to stay in
// lockstep with the snow entry it came from. Hand-editing that is how a single
// weapon ends up pointing at the wrong mesh.
//
// Safe to run twice: existing wet entries are replaced, not appended.

const fs = require("node:fs");
const path = require("node:path");

const specPath = path.join(__dirname, "snow_assets.json");
const spec = JSON.parse(fs.readFileSync(specPath, "utf8"));

// Three levels, mirroring EW_Config's wetThresholds.
//
// Coverage is of the surface that can actually HOLD standing water -- the
// near-level area -- not of the whole weapon. These are pools you can point at,
// so the numbers are far lower than a film would use: at the lightest level a
// few puddles have gathered in the recesses, at the heaviest they have run
// together across most of the level surface but still stop short of flooding it.
//
// Each wet level takes its GEOMETRY from one of the weapon's own snow stages
// and supplies only its own alpha ceiling.
//
// Water used to have a mask of its own -- a coarse pool field over every
// surface but the undersides -- and reviewed in game it read as scattered
// staining rather than as weather. Snow accumulates from the top down and
// creeps onto the flanks as it builds; rain does the same, and that shared
// top-down structure is what makes the two look like two states of one weapon.
// Deriving from the snow stages rather than restating the numbers also keeps
// each weapon's per-mesh flank tuning, which does vary across the roster.
//
// 1, 2 and 4 rather than 1, 2 and 3: the widest spread the snow ramp offers,
// because legibility between levels was the original complaint.
//
// Alpha reaching 1.0 does not mean opaque. It is the input to a transparent
// darkening, so a fully soaked surface still shows the weapon through it.
const LEVELS = [
  { suffix: "WetLight", stage: -1, geometryFromSnowStage: 1, wetMaxAlpha: 0.50 },
  { suffix: "WetMedium", stage: -2, geometryFromSnowStage: 2, wetMaxAlpha: 0.76 },
  { suffix: "WetHeavy", stage: -3, geometryFromSnowStage: 4, wetMaxAlpha: 1.00 },
];

// The MaxAlpha constant in generate_snow_textures.ps1, which is the ceiling the
// snow flank alphas below were chosen against.
const SNOW_MAX_ALPHA = 0.95;

const isWet = asset => asset.mode === "wet";
const templates = spec.assets.filter(a => !isWet(a) && Number(a.stage) === 1);

if (templates.length === 0) {
  throw new Error("no stage 1 snow entries found to derive wet entries from");
}

// Every snow stage of one weapon, keyed by stage, so a level can borrow the
// geometry of a stage other than the one the naming is derived from.
const snowStagesByWeapon = new Map();
for (const asset of spec.assets) {
  if (isWet(asset)) continue;
  const key = `${asset.fullType}|${asset.mesh}|${asset.source}`;
  if (!snowStagesByWeapon.has(key)) snowStagesByWeapon.set(key, new Map());
  snowStagesByWeapon.get(key).set(Number(asset.stage), asset);
}

const wetAssets = [];
for (const template of templates) {
  const stages = snowStagesByWeapon.get(
    `${template.fullType}|${template.mesh}|${template.source}`);
  for (const level of LEVELS) {
    const geometry = stages && stages.get(level.geometryFromSnowStage);
    if (!geometry) {
      throw new Error(
        `${template.id}: no snow stage ${level.geometryFromSnowStage} to take ` +
          `${level.suffix} geometry from`);
    }
    const id = template.id.replace(/_Snow[A-Za-z]+$/, `_${level.suffix}`);
    const modelName = template.modelName.replace(/_Snow[A-Za-z]+$/, `_${level.suffix}`);
    if (id === template.id || modelName === template.modelName) {
      throw new Error(`could not derive a wet name from ${template.id}`);
    }
    wetAssets.push({
      id,
      fullType: template.fullType,
      vanillaModel: template.vanillaModel,
      modelName,
      stage: level.stage,
      mode: "wet",
      mesh: template.mesh,
      source: template.source,
      output: `42/media/textures/weapons/firearm/${id}.png`,
      recipe: `tools/recipes/${id}.png.seed`,
      upAxis: template.upAxis,
      upSign: template.upSign,
      flipV: template.flipV,
      // Geometry borrowed wholesale from a snow stage of the same weapon, so
      // water builds up exactly the way snow does and each mesh keeps the flank
      // tuning it was given.
      targetUpCoverage: geometry.targetUpCoverage,
      flankCoverage: geometry.flankCoverage,
      // Rescaled into this level's range, not copied. The snow flank alphas were
      // picked against a ceiling of 0.95, so copying 0.42 straight into a level
      // whose top only reaches 0.50 would make the flanks nearly as dark as the
      // upward faces and flatten the very top-down gradient this change is for.
      // Scaling by the same ratio the top uses preserves snow's proportion.
      flankMaxAlpha: Number(
        (geometry.flankMaxAlpha * (level.wetMaxAlpha / SNOW_MAX_ALPHA)).toFixed(4)),
      wetMaxAlpha: level.wetMaxAlpha,
      // Shared with this weapon's snow entries on purpose. The noise field is
      // what makes one level a superset of the last; re-rolling it per level
      // would move the wetted area around as the weapon soaks.
      noiseBase: template.noiseBase,
      edgeSoftness: template.edgeSoftness,
      visuallyVerified: false,
      verificationNote: `Derived from ${template.id}, geometry from snow stage ${level.geometryFromSnowStage}. Not yet seen in game.`,
    });
  }
}

spec.assets = spec.assets.filter(a => !isWet(a)).concat(wetAssets);

spec.conventions.wetness =
  "Wet entries carry mode='wet' and a NEGATIVE stage, matching the signed state axis in EW_Config: " +
  "positive stages are snow, negative are wet, 0 is vanilla. They carry the SAME geometry keys as " +
  "snow -- targetUpCoverage, flankCoverage, flankMaxAlpha, noiseBase, edgeSoftness -- copied from " +
  "one of the weapon's own snow stages (1, 2 and 4 for the three levels), and add only wetMaxAlpha. " +
  "Water builds from the top down and creeps onto the flanks exactly the way snow does; only the " +
  "compositing differs, darkening where snow whitens. An earlier version gave water a pool field of " +
  "its own with every surface but the undersides eligible, and in game it read as scattered staining " +
  "rather than as weather.";

fs.writeFileSync(specPath, JSON.stringify(spec, null, 2) + "\n");

console.log(`generate_wet_assets: ${wetAssets.length} wet entries for ${templates.length} weapons`);
