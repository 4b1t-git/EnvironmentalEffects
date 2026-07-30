"use strict";
// Generates the two wiring files from tools/snow_assets.json:
//
//   mod/42/media/scripts/models_EnvironmentalWeapons.txt
//   mod/42/media/lua/shared/EnvironmentalWeapons/EW_Profiles.lua
//
// Attachment offsets are copied verbatim from the vanilla ModelScript, because a
// snow model is the vanilla mesh with a different texture and must keep every
// mount point exactly where the vanilla model has it. Transcribing them by hand
// is where errors hide: four stages across nineteen firearms is 76 model blocks.
//
// Run with --check to verify the files on disk match what would be generated,
// without writing. tools/validate.js uses that to keep them from drifting.
//
// Dependencies: Node only.

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const modRoot = path.join(root, "mod");
const spec = JSON.parse(fs.readFileSync(path.join(__dirname, "snow_assets.json"), "utf8"));

const VANILLA_MODELS = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\ProjectZomboid" +
  "\\media\\scripts\\generated\\models_weapons.txt";

const modelsPath = path.join(modRoot, "42/media/scripts/models_EnvironmentalWeapons.txt");
const profilesPath = path.join(modRoot, "42/media/lua/shared/EnvironmentalWeapons/EW_Profiles.lua");

// Extracts the body of `model <name> { ... }` by brace matching, so a nested
// attachment block cannot terminate the search early.
function vanillaModelBody(text, name) {
  // Scripts declare `model HuntingRifle` inside `module Base`, while items refer
  // to it as `Base.HuntingRifle`. Strip the module qualifier before searching.
  const bare = name.includes(".") ? name.slice(name.indexOf(".") + 1) : name;
  const header = new RegExp(`(^|\\n)\\s*model\\s+${bare.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*(\\r?\\n)?\\s*\\{`);
  const m = header.exec(text);
  if (!m) throw new Error(`vanilla model not found: ${name} (looked for "model ${bare}")`);
  let depth = 0;
  const open = text.indexOf("{", m.index);
  for (let i = open; i < text.length; i++) {
    if (text[i] === "{") depth++;
    else if (text[i] === "}") {
      depth--;
      if (depth === 0) return text.slice(open + 1, i);
    }
  }
  throw new Error(`unterminated vanilla model: ${name}`);
}

// Keeps only the attachment blocks. mesh and texture are supplied per stage, and
// anything else in a vanilla block (shader, scale) belongs to the vanilla model.
function attachmentBlocks(body) {
  const blocks = [];
  const re = /attachment\s+(\w+)\s*(\r?\n)?\s*\{/g;
  let m;
  while ((m = re.exec(body))) {
    let depth = 0;
    const open = body.indexOf("{", m.index);
    for (let i = open; i < body.length; i++) {
      if (body[i] === "{") depth++;
      else if (body[i] === "}") {
        depth--;
        if (depth === 0) {
          blocks.push({ name: m[1], inner: body.slice(open + 1, i) });
          re.lastIndex = i;
          break;
        }
      }
    }
  }
  return blocks;
}

function renderModelBlock(asset, blocks) {
  const lines = [];
  lines.push(`    model ${asset.modelName}`);
  lines.push("    {");
  lines.push(`        mesh = ${asset.mesh.split("\\").pop().replace(/\.x$/, "")
    .replace(/^/, meshPrefix(asset))},`);
  lines.push(`        texture = ${textureReference(asset)},`);
  for (const block of blocks) {
    lines.push(`        attachment ${block.name}`);
    lines.push("        {");
    for (const raw of block.inner.split(/\r?\n/)) {
      const trimmed = raw.trim();
      if (trimmed) lines.push(`            ${trimmed}`);
    }
    lines.push("        }");
  }
  lines.push("    }");
  return lines.join("\n");
}

// `mesh` in the spec is an absolute .x path; the ModelScript wants the
// media-relative form, e.g. weapons/firearm/MSR788_Rifle.
function meshPrefix(asset) {
  const normalized = asset.mesh.replace(/\\/g, "/");
  const at = normalized.toLowerCase().indexOf("/models_x/");
  if (at < 0) throw new Error(`mesh is not under models_X: ${asset.mesh}`);
  return normalized.slice(at + "/models_x/".length).replace(/\.x$/i, "").replace(/[^/]+$/, "");
}

function textureReference(asset) {
  return asset.output
    .replace(/^42\/media\/textures\//, "")
    .replace(/\.png$/i, "");
}

function buildModels() {
  const vanilla = fs.readFileSync(VANILLA_MODELS, "utf8");
  const cache = new Map();
  const blocksFor = name => {
    if (!cache.has(name)) cache.set(name, attachmentBlocks(vanillaModelBody(vanilla, name)));
    return cache.get(name);
  };
  const ordered = [...spec.assets].sort(
    (a, b) => a.fullType.localeCompare(b.fullType) || a.stage - b.stage);
  const body = ordered.map(a => renderModelBlock(a, blocksFor(a.vanillaModel))).join("\n\n");
  return `module Base\n{\n${body}\n}\n`;
}

function buildProfiles() {
  const byFullType = new Map();
  for (const asset of spec.assets) {
    if (!byFullType.has(asset.fullType)) byFullType.set(asset.fullType, new Map());
    const stages = byFullType.get(asset.fullType);
    if (stages.has(asset.stage)) {
      throw new Error(`${asset.fullType} declares stage ${asset.stage} twice`);
    }
    stages.set(asset.stage, asset);
  }

  const lines = [];
  lines.push("-- GENERATED by tools/generate_mod_wiring.js from tools/snow_assets.json.");
  lines.push("-- Edit the spec, not this file.");
  lines.push("");
  lines.push("local Profiles = {}");
  lines.push("");
  lines.push("-- Every stage leaves worldModel nil on purpose. Firearms must fall through to");
  lines.push("-- the engine's HandWeapon handling, which keeps a dropped weapon flat and still");
  lines.push("-- textured; a WorldStaticModel forces the generic atlas branch and stands it");
  lines.push("-- upright.");
  lines.push("local profiles = {");

  const fullTypes = [...byFullType.keys()].sort();
  for (const fullType of fullTypes) {
    const stages = byFullType.get(fullType);
    lines.push(`    {`);
    lines.push(`        fullType = ${JSON.stringify(fullType)},`);
    lines.push(`        enabled = true,`);
    lines.push(`        stages = {`);
    lines.push(`            [0] = { equippedModel = nil, worldModel = nil, icon = nil },`);
    for (let stage = 1; stage <= 4; stage++) {
      const asset = stages.get(stage);
      const model = asset ? `"${asset.modelName}"` : "nil";
      lines.push(`            [${stage}] = { equippedModel = ${model}, worldModel = nil, icon = nil },`);
    }
    lines.push(`        },`);
    lines.push(`    },`);
  }

  lines.push("}");
  lines.push("");
  lines.push("Profiles.byFullType = {}");
  lines.push("for _, profile in ipairs(profiles) do");
  lines.push("    Profiles.byFullType[profile.fullType] = profile");
  lines.push("end");
  lines.push("");
  lines.push("-- Future aliases must be explicitly keyed by FullType. A shared WeaponSprite");
  lines.push("-- never enables an unrelated item.");
  lines.push("Profiles.aliasesByFullType = {}");
  lines.push("");
  lines.push("function Profiles.find(item)");
  lines.push("    if not item then return nil end");
  lines.push("    local fullType = item:getFullType()");
  lines.push("    local profile = Profiles.byFullType[fullType]");
  lines.push("    if not profile then");
  lines.push("        local canonicalType = Profiles.aliasesByFullType[fullType]");
  lines.push("        profile = canonicalType and Profiles.byFullType[canonicalType] or nil");
  lines.push("    end");
  lines.push("    return profile and profile.enabled and profile or nil");
  lines.push("end");
  lines.push("");
  lines.push("return Profiles");
  lines.push("");
  return lines.join("\n");
}

const outputs = [
  [modelsPath, buildModels()],
  [profilesPath, buildProfiles()],
];

const check = process.argv.includes("--check");
let drift = 0;
for (const [file, content] of outputs) {
  const existing = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null;
  const same = existing === content;
  if (check) {
    if (!same) {
      drift++;
      console.error(`DRIFT: ${path.relative(root, file)} differs from the spec`);
    }
  } else {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
    console.log(`${same ? "unchanged" : "written  "}: ${path.relative(root, file)}`);
  }
}

if (check && drift > 0) {
  throw new Error(`${drift} wiring file(s) drifted; run node tools/generate_mod_wiring.js`);
}
console.log(`generate_mod_wiring: PASS (${spec.assets.length} assets, ${check ? "check" : "write"})`);
