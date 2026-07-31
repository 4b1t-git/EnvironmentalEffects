"use strict";
// Adds the last three vanilla firearms to tools/snow_assets.json.
//
// They were excluded because the generator hard-assumed a 256x256 atlas. It no
// longer does, so the only thing that kept them out is gone.
//
//   L94_Rifle        2048x2048, and it reuses the L92_Carbine MESH, so its axis
//                    and up sign are already confirmed by that weapon's entries
//                    and nothing new has to be eyeballed.
//   Revolver_CapGun  64x64, mesh ToyGun_Hand, texture ToyGun
//   Rifle_CapGun     64x64, mesh ToyRifle_Hand, texture ToyRifle
//
// The two cap guns are declared in scripts/generated/TEMPORARY_TESTING_new_items,
// which is the developers' own name for unfinished content. Including them is
// safe either way: profiles are keyed by FullType, so if the items are ever
// removed the profile simply never matches and nothing runs.
//
// Coverage numbers are copied from an existing weapon of the same shape rather
// than invented, so the four stages ramp identically across the roster.
//
// Safe to run twice: it replaces its own entries rather than appending.

const fs = require("node:fs");
const path = require("node:path");

const specPath = path.join(__dirname, "snow_assets.json");
const spec = JSON.parse(fs.readFileSync(specPath, "utf8"));

const VANILLA = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\ProjectZomboid\\media";
const mesh = name => `${VANILLA}\\models_X\\weapons\\firearm\\${name}.x`;
const texture = name => `${VANILLA}\\textures\\weapons\\firearm\\${name}.png`;

const WEAPONS = [
  {
    id: "EW_L94_Rifle",
    fullType: "Base.L94_Rifle",
    vanillaModel: "Base.L94_Rifle",
    modelName: "EW_L94_Rifle",
    mesh: mesh("L92_Carbine"),
    source: texture("L94_Rifle"),
    // Same mesh as the L92, so the same axis, and the same shape means the same
    // coverage ramp. Nothing here is a guess.
    shapeOf: "EW_L92_Carbine",
  },
  {
    id: "EW_Revolver_CapGun",
    fullType: "Base.Revolver_CapGun",
    vanillaModel: "Base.Revolver_CapGun",
    modelName: "EW_Revolver_CapGun",
    mesh: mesh("ToyGun_Hand"),
    source: texture("ToyGun"),
    // A pistol-shaped toy; the handgun ramp fits it, not the rifle one.
    shapeOf: "EW_M9_Pistol",
  },
  {
    id: "EW_Rifle_CapGun",
    fullType: "Base.Rifle_CapGun",
    vanillaModel: "Base.Rifle_CapGun",
    modelName: "EW_Rifle_CapGun",
    mesh: mesh("ToyRifle_Hand"),
    source: texture("ToyRifle"),
    shapeOf: "EW_L92_Carbine",
  },
];

const SUFFIX = { 1: "SnowLight", 2: "SnowMedium", 3: "SnowHeavy", 4: "SnowFull" };

for (const file of [...new Set(WEAPONS.flatMap(w => [w.mesh, w.source]))]) {
  if (!fs.existsSync(file)) throw new Error(`vanilla asset missing: ${file}`);
}

const added = [];
for (const weapon of WEAPONS) {
  const template = spec.assets.filter(
    a => a.mode !== "wet" && a.id.startsWith(weapon.shapeOf + "_Snow"));
  if (template.length !== 4) {
    throw new Error(`${weapon.id}: expected 4 snow stages on ${weapon.shapeOf}, found ${template.length}`);
  }
  for (const source of template) {
    const stage = Number(source.stage);
    const id = `${weapon.id}_${SUFFIX[stage]}`;
    added.push({
      id,
      fullType: weapon.fullType,
      vanillaModel: weapon.vanillaModel,
      modelName: `${weapon.modelName}_${SUFFIX[stage]}`,
      stage,
      mesh: weapon.mesh,
      source: weapon.source,
      output: `42/media/textures/weapons/firearm/${id}.png`,
      recipe: `tools/recipes/${id}.png.seed`,
      targetUpCoverage: source.targetUpCoverage,
      noiseBase: source.noiseBase,
      edgeSoftness: source.edgeSoftness,
      flankCoverage: source.flankCoverage,
      flankMaxAlpha: source.flankMaxAlpha,
      upAxis: source.upAxis,
      upSign: source.upSign,
      flipV: source.flipV,
      visuallyVerified: false,
      verificationNote:
        `Ramp copied from ${weapon.shapeOf}. Axis unconfirmed for this mesh; ` +
        `check the contact sheet before shipping.`,
    });
  }
}

const ours = new Set(WEAPONS.map(w => w.fullType));
spec.assets = spec.assets.filter(a => !ours.has(a.fullType)).concat(added);

console.log(`add_remaining_firearms: ${added.length} entries for ${WEAPONS.length} weapons`);
fs.writeFileSync(specPath, JSON.stringify(spec, null, 2) + "\n");
