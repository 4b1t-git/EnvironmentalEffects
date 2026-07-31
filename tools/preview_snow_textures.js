"use strict";
// Renders every asset in tools/snow_assets.json as a contact sheet: vanilla on
// top, the snow derivative below, from a Project Zomboid-like overhead angle.
//
// This exists because no cheap geometric test recovers a mesh's up sign (see the
// warning in snow_assets.json). Placement has to be confirmed by looking at it,
// so make that one glance for N weapons instead of N separate checks.
//
// Usage: node tools/preview_snow_textures.js [out.png] [yaw] [elev]
// Dependencies: Node only. No packages.

const fs = require("node:fs");
const path = require("node:path");
const zlib = require("node:zlib");

const root = path.resolve(__dirname, "..");
const modRoot = path.join(root, "mod");
const spec = JSON.parse(fs.readFileSync(path.join(__dirname, "snow_assets.json"), "utf8"));

// Contact sheets live OUTSIDE the mod tree, in a sibling directory. They are
// review renders, not mod content: writing them inside meant every regeneration
// changed the delivered tree and broke work/output parity until the next sync.
// With nineteen weapons and iterative tuning that is constant friction.
const PREVIEW_ROOT = path.resolve(root, "..", "EnvironmentalWeapons-preview");

const outFile = process.argv[2] || path.join(PREVIEW_ROOT, "contact_sheet.png");
const yaw = parseFloat(process.argv[3] || "84");
const elev = parseFloat(process.argv[4] || "30");
const ROW_W = 1000;
const ROW_H = 150;

function readPng(file) {
  const buf = fs.readFileSync(file);
  let pos = 8, width = 0, height = 0, bitDepth = 0, colorType = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[12] !== 0) throw new Error(`interlaced PNG unsupported: ${file}`);
    } else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    pos += 12 + len;
  }
  if (bitDepth !== 8) throw new Error(`bit depth ${bitDepth} unsupported: ${file}`);
  const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[colorType];
  if (!channels) throw new Error(`color type ${colorType} unsupported: ${file}`);
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = Buffer.alloc(height * stride);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const cur = Buffer.alloc(stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= channels ? cur[i - channels] : 0;
      const b = prev[i];
      const c = i >= channels ? prev[i - channels] : 0;
      let v = line[i];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
      }
      cur[i] = v & 0xff;
    }
    cur.copy(out, y * stride);
    prev = cur;
  }
  return { width, height, channels, data: out };
}

let crcTable = null;
function crc32(buf) {
  if (!crcTable) {
    crcTable = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      crcTable[n] = c >>> 0;
    }
  }
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function writePng(file, width, height, rgb) {
  const stride = width * 3;
  const raw = Buffer.alloc(height * (stride + 1));
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0;
    rgb.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  function chunk(type, data) {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]));
}

// Mirrors the parser in generate_snow_textures.ps1, including the template skip:
// a .x file opens with `template <Name> { <GUID> }` blocks that reuse the data
// block names, and parsing those as geometry yields nonsense.
function parseMesh(file) {
  const body = fs.readFileSync(file, "utf8");
  function findDataBlock(marker) {
    let at = 0;
    for (;;) {
      at = body.indexOf(marker, at);
      if (at < 0) throw new Error(`data block not found: ${marker}`);
      let back = at - 1;
      while (back >= 0 && /\s/.test(body[back])) back--;
      if (!(back >= 7 && body.slice(back - 7, back + 1) === "template")) return at;
      at += marker.length;
    }
  }
  function intAt(from) {
    const re = /\d+/g;
    re.lastIndex = from;
    const m = re.exec(body);
    return { value: Number(m[0]), end: re.lastIndex };
  }
  function tuples(from, count, arity) {
    const re = /-?\d+\.?\d*(?:[eE][-+]?\d+)?/g;
    re.lastIndex = from;
    const out = [];
    while (out.length < count) {
      const t = [];
      while (t.length < arity) t.push(parseFloat(re.exec(body)[0]));
      out.push(t);
    }
    return { data: out, end: re.lastIndex };
  }
  function faceList(from, count) {
    const re = /(\d+);((?:\d+,)*\d+);/g;
    re.lastIndex = from;
    const out = [];
    let m;
    while (out.length < count && (m = re.exec(body))) {
      const idx = m[2].split(",").map(Number);
      if (idx.length !== Number(m[1])) continue;
      out.push(idx);
    }
    return out;
  }
  const frameAt = findDataBlock("Frame ");
  const meshBrace = body.indexOf("{", body.indexOf("Mesh ", frameAt)) + 1;
  const vCount = intAt(meshBrace);
  const verts = tuples(vCount.end, vCount.value, 3);
  const faceHead = /(\d+);\s*\r?\n\s*3;\d+,\d+,\d+;,/.exec(body.slice(verts.end));
  const faces = faceList(verts.end + faceHead.index, Number(faceHead[1]));
  const nBrace = body.indexOf("{", findDataBlock("MeshNormals")) + 1;
  const nCount = intAt(nBrace);
  const normals = tuples(nCount.end, nCount.value, 3);
  const tBrace = body.indexOf("{", findDataBlock("MeshTextureCoords")) + 1;
  const tCount = intAt(tBrace);
  const uvs = tuples(tCount.end, tCount.value, 2);
  if (nCount.value !== vCount.value || tCount.value !== vCount.value) {
    throw new Error(`mesh is not 1:1 indexed: ${file}`);
  }
  return { verts: verts.data, normals: normals.data, uvs: uvs.data, faces };
}

// upSign flips the model so the weapon is drawn the way it is held. Without this
// a handgun renders grip-up, which looks plausible as an image and hides an
// inverted axis -- the six handguns shipped with snow on their undersides because
// this sheet showed them upside down and the mistake read as normal.
function render(mesh, tex, flipV, upSign) {
  const ya = (yaw * Math.PI) / 180;
  const ea = (elev * Math.PI) / 180;
  const f = [Math.cos(ea) * Math.sin(ya), Math.cos(ea) * Math.cos(ya), -Math.sin(ea)];
  let r = [f[1], -f[0], 0];
  const rl = Math.hypot(r[0], r[1], r[2]);
  r = r.map((v) => v / rl);
  const u = [
    r[1] * f[2] - r[2] * f[1],
    r[2] * f[0] - r[0] * f[2],
    r[0] * f[1] - r[1] * f[0],
  ];

  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
  for (const v of mesh.verts) {
    for (let k = 0; k < 3; k++) {
      if (v[k] < lo[k]) lo[k] = v[k];
      if (v[k] > hi[k]) hi[k] = v[k];
    }
  }
  const center = [0, 1, 2].map((k) => (lo[k] + hi[k]) / 2);
  const sign = upSign === -1 ? -1 : 1;
  const pts = mesh.verts.map((v) => {
    const d = [v[0] - center[0], v[1] - center[1], sign * (v[2] - center[2])];
    return [
      d[0] * r[0] + d[1] * r[1] + d[2] * r[2],
      -(d[0] * u[0] + d[1] * u[1] + d[2] * u[2]),
      d[0] * f[0] + d[1] * f[1] + d[2] * f[2],
    ];
  });
  const plo = [Infinity, Infinity], phi = [-Infinity, -Infinity];
  for (const p of pts) {
    for (let k = 0; k < 2; k++) {
      if (p[k] < plo[k]) plo[k] = p[k];
      if (p[k] > phi[k]) phi[k] = p[k];
    }
  }
  const pad = 12;
  const s = Math.min((ROW_W - 2 * pad) / (phi[0] - plo[0]), (ROW_H - 2 * pad) / (phi[1] - plo[1]));
  const ox = (ROW_W - (phi[0] - plo[0]) * s) / 2;
  const oy = (ROW_H - (phi[1] - plo[1]) * s) / 2;
  const screen = pts.map((p) => [ox + (p[0] - plo[0]) * s, oy + (p[1] - plo[1]) * s, p[2]]);

  const img = Buffer.alloc(ROW_W * ROW_H * 3);
  // Neutral mid grey: keeps both dark metal and white snow judgeable.
  for (let p = 0; p < ROW_W * ROW_H; p++) {
    img[p * 3] = 92; img[p * 3 + 1] = 96; img[p * 3 + 2] = 104;
  }
  const depth = new Float32Array(ROW_W * ROW_H).fill(Infinity);
  const light = [0.35, -0.25, 0.9];
  const ll = Math.hypot(light[0], light[1], light[2]);
  const ln = light.map((v) => v / ll);

  for (const face of mesh.faces) {
    for (let t = 1; t + 1 < face.length; t++) {
      const tri = [face[0], face[t], face[t + 1]];
      const P = tri.map((k) => screen[k]);
      const det = (P[1][0] - P[0][0]) * (P[2][1] - P[0][1]) - (P[2][0] - P[0][0]) * (P[1][1] - P[0][1]);
      if (Math.abs(det) < 1e-12) continue;
      const minX = Math.max(0, Math.floor(Math.min(P[0][0], P[1][0], P[2][0])));
      const maxX = Math.min(ROW_W - 1, Math.ceil(Math.max(P[0][0], P[1][0], P[2][0])));
      const minY = Math.max(0, Math.floor(Math.min(P[0][1], P[1][1], P[2][1])));
      const maxY = Math.min(ROW_H - 1, Math.ceil(Math.max(P[0][1], P[1][1], P[2][1])));
      for (let y = minY; y <= maxY; y++) {
        for (let x = minX; x <= maxX; x++) {
          const px = x + 0.5, py = y + 0.5;
          const w0 = ((P[1][0] - px) * (P[2][1] - py) - (P[2][0] - px) * (P[1][1] - py)) / det;
          const w1 = ((P[2][0] - px) * (P[0][1] - py) - (P[0][0] - px) * (P[2][1] - py)) / det;
          const w2 = 1 - w0 - w1;
          if (w0 < 0 || w1 < 0 || w2 < 0) continue;
          const z = w0 * P[0][2] + w1 * P[1][2] + w2 * P[2][2];
          const o = y * ROW_W + x;
          if (z >= depth[o]) continue;
          depth[o] = z;
          const uu = w0 * mesh.uvs[tri[0]][0] + w1 * mesh.uvs[tri[1]][0] + w2 * mesh.uvs[tri[2]][0];
          let vv = w0 * mesh.uvs[tri[0]][1] + w1 * mesh.uvs[tri[1]][1] + w2 * mesh.uvs[tri[2]][1];
          if (flipV) vv = 1 - vv;
          const tx = Math.min(255, Math.max(0, Math.floor(uu * 256)));
          const ty = Math.min(255, Math.max(0, Math.floor(vv * 256)));
          const ti = (ty * tex.width + tx) * tex.channels;
          const nx = w0 * mesh.normals[tri[0]][0] + w1 * mesh.normals[tri[1]][0] + w2 * mesh.normals[tri[2]][0];
          const ny = w0 * mesh.normals[tri[0]][1] + w1 * mesh.normals[tri[1]][1] + w2 * mesh.normals[tri[2]][1];
          const nz = w0 * mesh.normals[tri[0]][2] + w1 * mesh.normals[tri[1]][2] + w2 * mesh.normals[tri[2]][2];
          const nl = Math.hypot(nx, ny, nz) || 1;
          const diff = Math.max(0, (nx * ln[0] + ny * ln[1] + nz * ln[2]) / nl);
          const shade = 0.55 + 0.45 * diff;
          img[o * 3] = Math.min(255, tex.data[ti] * shade);
          img[o * 3 + 1] = Math.min(255, tex.data[ti + 1] * shade);
          img[o * 3 + 2] = Math.min(255, tex.data[ti + 2] * shade);
        }
      }
    }
  }
  return img;
}

// An optional substring filter, because the full sheet is 171 rows and judging
// one weapon's progression means being able to see its rows side by side.
//   node tools/preview_snow_textures.js out.png 84 30 MSR788
// argv[2..4] are the existing output path, yaw and elevation; the filter takes
// the next free slot rather than displacing them.
const filter = process.argv[5] || null;
const selected = filter
  ? spec.assets.filter(a => a.id.includes(filter))
  : spec.assets;
if (filter && selected.length === 0) {
  throw new Error(`no asset id contains ${filter}`);
}

const rows = [];
// One vanilla row per mesh+source, not per asset: the stages of a weapon share
// both, and at four stages across many weapons half the sheet would be repeats.
let lastBase = null;
for (const asset of selected) {
  const mesh = parseMesh(asset.mesh);
  const base = `${asset.mesh}|${asset.source}`;
  const deliveredPath = path.join(modRoot, asset.output);
  const previewPath = path.join(PREVIEW_ROOT, `${asset.id}.png`);
  const texturePath = fs.existsSync(deliveredPath) ? deliveredPath : previewPath;
  if (!fs.existsSync(texturePath)) {
    console.error(`skip ${asset.id}: no texture at ${deliveredPath} or ${previewPath}`);
    continue;
  }
  const derivative = readPng(texturePath);
  if (base !== lastBase) {
    rows.push({
      label: `${path.basename(asset.source)} vanilla`,
      data: render(mesh, readPng(asset.source), asset.flipV, asset.upSign),
    });
    lastBase = base;
  }
  rows.push({
    label: `${asset.id} stage ${asset.stage}${texturePath === previewPath ? " (UNVERIFIED PREVIEW)" : ""}`,
    data: render(mesh, derivative, asset.flipV, asset.upSign),
  });
}

if (rows.length === 0) throw new Error("nothing to preview");

const sheet = Buffer.alloc(ROW_W * ROW_H * rows.length * 3);
rows.forEach((row, index) => {
  row.data.copy(sheet, index * ROW_W * ROW_H * 3);
  // Amber rule between rows so pairs are easy to separate by eye.
  for (let y = 0; y < 2; y++) {
    for (let x = 0; x < ROW_W; x++) {
      const o = (index * ROW_H + y) * ROW_W + x;
      sheet[o * 3] = 255; sheet[o * 3 + 1] = 200; sheet[o * 3 + 2] = 0;
    }
  }
});
writePng(outFile, ROW_W, ROW_H * rows.length, sheet);
console.log(`preview_snow_textures: wrote ${outFile} (yaw=${yaw} elev=${elev})`);
rows.forEach((row, index) => console.log(`  row ${index + 1}: ${row.label}`));
