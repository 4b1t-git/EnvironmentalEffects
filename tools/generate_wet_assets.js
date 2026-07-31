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

// Three levels, mirroring EW_Config's wetThresholds. Coverage is measured
// against the weapon's whole owned atlas area, not its up-facing share: rain
// reaches every surface, so "half wet" means half the weapon, not half its top.
//
// Alpha stays below 1.0 even when soaked. Water darkens what is underneath; it
// never replaces it, and a weapon whose machining has vanished into flat brown
// has stopped being readable at gameplay zoom.
const LEVELS = [
  { suffix: "WetLight", stage: -1, wetCoverage: 0.42, wetMaxAlpha: 0.46 },
  { suffix: "WetMedium", stage: -2, wetCoverage: 0.70, wetMaxAlpha: 0.68 },
  { suffix: "WetHeavy", stage: -3, wetCoverage: 0.93, wetMaxAlpha: 0.86 },
];

const isWet = asset => asset.mode === "wet";
const templates = spec.assets.filter(a => !isWet(a) && Number(a.stage) === 1);

if (templates.length === 0) {
  throw new Error("no stage 1 snow entries found to derive wet entries from");
}

const wetAssets = [];
for (const template of templates) {
  for (const level of LEVELS) {
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
      wetCoverage: level.wetCoverage,
      wetMaxAlpha: level.wetMaxAlpha,
      // Shared with this weapon's snow entries on purpose. The noise field is
      // what makes one level a superset of the last; re-rolling it per level
      // would move the wet patches around as the weapon soaks.
      noiseBase: template.noiseBase,
      edgeSoftness: template.edgeSoftness,
      visuallyVerified: false,
      verificationNote: `Derived from ${template.id}: identical mesh, source and axis. Not yet seen in game.`,
    });
  }
}

spec.assets = spec.assets.filter(a => !isWet(a)).concat(wetAssets);

spec.conventions.wetness =
  "Wet entries carry mode='wet' and a NEGATIVE stage, matching the signed state axis in EW_Config: " +
  "positive stages are snow, negative are wet, 0 is vanilla. They use wetCoverage and wetMaxAlpha " +
  "instead of targetUpCoverage/flankCoverage/flankMaxAlpha, because water has no up-facing gate to " +
  "tune -- rain reaches every surface and only pools differently. noiseBase and edgeSoftness are " +
  "inherited from the weapon's snow entries so both phenomena sit on the same noise field.";

fs.writeFileSync(specPath, JSON.stringify(spec, null, 2) + "\n");

console.log(`generate_wet_assets: ${wetAssets.length} wet entries for ${templates.length} weapons`);
