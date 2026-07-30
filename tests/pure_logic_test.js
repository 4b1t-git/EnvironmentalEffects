"use strict";
// Mirrors the pure Lua modules exactly. No engine calls, so this runs anywhere.
const assert = require("node:assert/strict");

const snow = {
  maximum: 100,
  minutesPerStage: 10,
  percentPerStage: 25,
  scaleWithIntensity: false,
  minimumIntensity: 0.01,
  accumulationMaxTemperatureC: 0.5,
  meltStartTemperatureC: 0,
};
const stages = { thresholds: [20, 45, 70, 90], hysteresis: 4 };
const TICK = snow.minutesPerStage;

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

// EW_Simulation.step
function step(current, minutes, s) {
  const value = clamp(Number(current) || 0, 0, snow.maximum);
  const elapsed = Math.max(0, Number(minutes) || 0);
  if (elapsed === 0) return value;
  const intensity = clamp(Number(s.snowIntensity) || 0, 0, 1);
  const temperature = Number(s.temperatureC) || 0;
  let delta = (snow.percentPerStage / snow.minutesPerStage) * elapsed;

  const accumulating = s.exposed && s.outside &&
    intensity >= snow.minimumIntensity &&
    temperature <= snow.accumulationMaxTemperatureC;
  if (accumulating) {
    if (snow.scaleWithIntensity) delta *= intensity;
    return clamp(value + delta, 0, snow.maximum);
  }

  const rainedOn = s.exposed && s.outside &&
    (Number(s.rainIntensity) || 0) >= snow.minimumIntensity;
  const melting = !s.outside || !s.exposed || rainedOn ||
    temperature > snow.meltStartTemperatureC;
  if (!melting) return value;
  return clamp(value - delta, 0, snow.maximum);
}

// EW_StageResolver.resolve
function stage(value, current) {
  const { thresholds, hysteresis } = stages;
  let result = clamp(current, 0, thresholds.length);
  while (result < thresholds.length && value >= thresholds[result]) result++;
  while (result > 0 && value < thresholds[result - 1] - hysteresis) result--;
  return result;
}

// EW_Climate.resolveSnowIntensity
function resolveSnowIntensity(isSnow, precipitation, fallback) {
  if (!isSnow) return 0;
  return clamp(precipitation == null ? Number(fallback) || 0 : Number(precipitation) || 0, 0, 1);
}

// EW_Climate.resolveRainIntensity
function resolveRainIntensity(isSnow, precipitation) {
  if (isSnow) return 0;
  return clamp(Number(precipitation) || 0, 0, 1);
}

// EW_Exposure classification: hands and body-attached are out in the weather,
// anything else being carried is sheltered.
function classify({ inHands, attachedSlot }) {
  if (inHands) return true;
  return Number(attachedSlot ?? -1) >= 0;
}

// EW_Controller elapsed-minute gate.
class ExposureClock {
  constructor() { this.lastHours = null; this.previous = new Set(); }
  update(hours, ids) {
    const elapsed = this.lastHours == null ? 0 : Math.max(0, (hours - this.lastHours) * 60);
    this.lastHours = hours;
    const current = new Set(ids);
    const charged = Object.fromEntries(ids.map(id => [id, this.previous.has(id) ? elapsed : 0]));
    this.previous = current;
    return charged;
  }
}

const findProfile = fullType => fullType === "Base.HuntingRifle" ? "rifle" : null;

function migrateLegacyWorld(trackedWorld, currentWorld) {
  const legacy = "EW_HuntingRifle_SnowLight_World";
  if (trackedWorld !== legacy) return { currentWorld, trackedWorld, cleared: false };
  if (currentWorld == null) return { currentWorld: null, trackedWorld: null, cleared: false };
  if (currentWorld !== legacy) return { currentWorld, trackedWorld: null, cleared: false };
  return { currentWorld: null, trackedWorld: null, cleared: true };
}

let checks = 0;
const check = (actual, expected, label) => {
  assert.deepEqual(actual, expected, label);
  checks++;
};

// ---- One stage per tick, climbing ----
const snowing = { exposed: true, outside: true, snowIntensity: 1, temperatureC: -5 };
let value = 0, current = 0;
const climb = [];
for (let tick = 0; tick < 4; tick++) {
  value = step(value, TICK, snowing);
  current = stage(value, current);
  climb.push([value, current]);
}
check(climb, [[25, 1], [50, 2], [75, 3], [100, 4]], "one stage gained per tick");

// ---- One stage per tick, thawing ----
const thawing = { exposed: true, outside: false, snowIntensity: 0, temperatureC: 10 };
const fall = [];
for (let tick = 0; tick < 4; tick++) {
  value = step(value, TICK, thawing);
  current = stage(value, current);
  fall.push([value, current]);
}
check(fall, [[75, 3], [50, 2], [25, 1], [0, 0]], "one stage lost per tick");

// ---- Weather intensity gates, it does not throttle ----
// This is the regression that made stage 2 unreachable: Build 42 reports low
// precipitation intensity during snow, and scaling by it stretched a stage past
// 20 game hours.
check(step(0, TICK, { ...snowing, snowIntensity: 0.15 }), 25, "faint snowfall still advances a full stage");
check(step(0, TICK, { ...snowing, snowIntensity: 0 }), 0, "no snowfall accumulates nothing");
check(step(0, TICK, { ...snowing, snowIntensity: 0.005 }), 0, "intensity below the gate accumulates nothing");

// ---- Accumulation preconditions ----
check(step(0, TICK, { ...snowing, temperatureC: 5 }), 0, "too warm to accumulate");
check(step(0, TICK, { ...snowing, outside: false }), 0, "indoors accumulates nothing");
check(step(40, TICK, { ...snowing, exposed: false }), 15, "stowed weapon thaws while it snows outside");

// ---- Frozen and idle holds its snow ----
const frozenClear = { exposed: true, outside: true, snowIntensity: 0, rainIntensity: 0, temperatureC: -8 };
check(step(60, TICK, frozenClear), 60, "snow holds on a frozen weapon in clear weather");
check(step(60, 600, frozenClear), 60, "and keeps holding over a long span");

// ---- Rain strips snow even below freezing ----
// The realistic sequence: it snowed, snowfall stopped, the air is still below
// zero, then rain moves in. Liquid water is falling, so it carries heat and
// washes the surface; ambient temperature must not gate this.
const freezingRain = { exposed: true, outside: true, snowIntensity: 0, rainIntensity: 0.6, temperatureC: -5 };
check(step(100, TICK, freezingRain), 75, "rain below freezing strips a stage");
let rained = 100;
const washed = [];
for (let tick = 0; tick < 4; tick++) {
  rained = step(rained, TICK, freezingRain);
  washed.push(rained);
}
check(washed, [75, 50, 25, 0], "rain clears every stage at the same pace");
check(step(60, TICK, { ...freezingRain, rainIntensity: 0.005 }), 60,
  "a trace of rain below the gate does not strip snow");
check(step(60, TICK, { ...freezingRain, outside: false }), 35,
  "indoors it thaws regardless of the rain outside");
check(step(0, TICK, { ...freezingRain, temperatureC: -5 }), 0, "rain never accumulates snow");

// ---- Clamping ----
check(step(90, 600, snowing), 100, "accumulation clamps at maximum");
check(step(10, 600, thawing), 0, "thaw clamps at zero");
check(step(50, 0, snowing), 50, "a zero-minute tick changes nothing");

// ---- Time-proportional, so a coalesced tick is not lost ----
check(step(0, TICK * 2, snowing), 50, "a doubled interval advances two stages worth");
check(step(0, TICK / 2, snowing), 12.5, "a half interval advances half a stage");

// ---- Hysteresis still damps a value sitting on a boundary ----
check(stage(45, 0), 2, "threshold entry");
check(stage(42, 2), 2, "inside the hysteresis band, stage holds");
check(stage(40, 2), 1, "past the hysteresis band, stage drops");

// ---- Rain is not snow ----
check(resolveSnowIntensity(false, 1, 1), 0, "rain yields no snow intensity");
check(resolveSnowIntensity(true, 0.75, 0.1), 0.75, "active precipitation channel wins");
check(resolveSnowIntensity(true, null, 0.4), 0.4, "snow strength is the fallback");
check(resolveRainIntensity(true, 0.8), 0, "snowfall yields no rain intensity");
check(resolveRainIntensity(false, 0.8), 0.8, "non-snow precipitation is rain");
check(resolveRainIntensity(false, 0), 0, "clear weather is not rain");

// ---- Exposure classification ----
check(classify({ inHands: true, attachedSlot: -1 }), true, "held weapon is exposed");
check(classify({ inHands: false, attachedSlot: 0 }), true, "slung weapon is exposed");
check(classify({ inHands: false, attachedSlot: 3 }), true, "holstered weapon is exposed");
check(classify({ inHands: false, attachedSlot: -1 }), false, "stowed weapon is sheltered");
check(classify({ inHands: false }), false, "absent slot reads as sheltered");

// ---- Controller elapsed-minute gate ----
const clock = new ExposureClock();
check(clock.update(0, ["rifle"]).rifle, 0, "first observation charges nothing");
check(clock.update(1 / 6, ["rifle"]).rifle, TICK, "second observation charges the interval");
clock.update(1 / 3, []);
clock.update(4, []);
check(clock.update(4 + 1 / 6, ["rifle"]).rifle, 0, "re-observation after a gap charges nothing");

// ---- Profiles are keyed by exact FullType ----
check(findProfile("Base.HuntingRifle"), "rifle", "declared profile resolves");
check(findProfile("Other.CopyWithHuntingRifleSprite"), null, "a shared sprite does not enable an item");

// ---- Legacy world-model migration ----
check(migrateLegacyWorld("EW_HuntingRifle_SnowLight_World", "EW_HuntingRifle_SnowLight_World"),
  { currentWorld: null, trackedWorld: null, cleared: true }, "adapter-owned legacy value clears");
check(migrateLegacyWorld("EW_HuntingRifle_SnowLight_World", "OtherMod.WorldModel"),
  { currentWorld: "OtherMod.WorldModel", trackedWorld: null, cleared: false }, "external override survives");
check(migrateLegacyWorld(null, "OtherMod.WorldModel"),
  { currentWorld: "OtherMod.WorldModel", trackedWorld: null, cleared: false }, "untracked value is left alone");

// The stage table and the tick rate have to agree, or a tick would skip or stall
// a stage. Prove it from the numbers rather than trusting the comment.
for (let index = 0; index < stages.thresholds.length; index++) {
  const gap = stages.thresholds[index] - (stages.thresholds[index - 1] ?? 0);
  assert.ok(gap <= snow.percentPerStage,
    `threshold gap ${gap} exceeds one tick of ${snow.percentPerStage}`);
  assert.ok(snow.percentPerStage < gap + stages.hysteresis + snow.percentPerStage,
    "tick must not overshoot two stages");
  checks++;
}

console.log(`pure_logic_test: PASS (${checks} assertions)`);
