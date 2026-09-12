// Phase 9: derive real base-body dimensions for AI Production Packages.
//
// Reads the Phase 2 analysis (public/generated-assets/base_body/analysis.json) and re-walks the
// source Outliner with the same transform model as build-base-model.mjs (translation = origin -
// parentOrigin, ZYX Euler, uniform 1/12 metre scale established in Phase 2/5). It writes a small
// measurements.json so the app can quote *measured* head / hand / socket numbers in prompts
// instead of telling an AI agent to "use an appropriate size".
//
// Read-only: base_1.bbmodel, analysis.json and the generated GLB are never modified.
import { readFile, writeFile } from "node:fs/promises";

const base = new URL("../public/generated-assets/base_body/", import.meta.url);
const analysis = JSON.parse(await readFile(new URL("analysis.json", base), "utf8"));
const SCALE = analysis.coordinates.metersPerSourceUnit;

const groups = new Map(analysis.groups.map((g) => [g.uuid, g]));
const elements = new Map(analysis.elements.map((e) => [e.uuid, e]));

// ---- minimal 3x3 math (three.js Euler order "ZYX" means R = Rz * Ry * Rx) ----
const ident = () => [1, 0, 0, 0, 1, 0, 0, 0, 1];
function mul3(a, b) {
  const out = new Array(9).fill(0);
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 3; c++) {
      for (let k = 0; k < 3; k++) out[r * 3 + c] += a[r * 3 + k] * b[k * 3 + c];
    }
  }
  return out;
}
function rot(deg) {
  const [x, y, z] = deg.map((d) => (d * Math.PI) / 180);
  const ca = Math.cos(x), sa = Math.sin(x);
  const cb = Math.cos(y), sb = Math.sin(y);
  const cc = Math.cos(z), sc = Math.sin(z);
  const Rx = [1, 0, 0, 0, ca, -sa, 0, sa, ca];
  const Ry = [cb, 0, sb, 0, 1, 0, -sb, 0, cb];
  const Rz = [cc, -sc, 0, sc, cc, 0, 0, 0, 1];
  return mul3(Rz, mul3(Ry, Rx));
}
const apply3 = (m, v) => [
  m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
  m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
  m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
];
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
/** frame = { r, t }; world(v) = r * v + t */
const compose = (parent, r, t) => ({ r: mul3(parent.r, r), t: add(parent.t, apply3(parent.r, t)) });

// ---- walk the Outliner exactly like the GLB converter ----
const frames = new Map(); // uuid -> { r, t }
const meta = new Map();   // uuid -> { name, parent, kind }
function visit(entry, parent, parentOrigin, parentFrame) {
  const uuid = typeof entry === "string" ? entry : entry.uuid;
  const object = groups.get(uuid) ?? elements.get(uuid);
  if (!object) throw new Error(`Unknown Outliner uuid: ${uuid}`);
  const origin = object.origin ?? [0, 0, 0];
  const rotation = object.rotation ?? [0, 0, 0];
  const translation = origin.map((v, i) => v - parentOrigin[i]);
  const frame = compose(parentFrame, rot(rotation), translation);
  frames.set(uuid, frame);
  meta.set(uuid, { name: object.name, parent, kind: groups.has(uuid) ? "group" : "element" });
  if (groups.has(uuid)) for (const child of entry.children ?? []) visit(child, uuid, origin, frame);
}
for (const entry of analysis.outliner) visit(entry, null, [0, 0, 0], { r: ident(), t: [0, 0, 0] });

const childrenOf = new Map();
for (const [uuid, m] of meta) {
  if (!m.parent) continue;
  childrenOf.set(m.parent, [...(childrenOf.get(m.parent) ?? []), uuid]);
}

const EMPTY = () => ({ min: [Infinity, Infinity, Infinity], max: [-Infinity, -Infinity, -Infinity] });
function expand(box, p) {
  for (let i = 0; i < 3; i++) {
    box.min[i] = Math.min(box.min[i], p[i]);
    box.max[i] = Math.max(box.max[i], p[i]);
  }
}
const round = (v) => Math.round(v * 1e4) / 1e4;
function finish(box) {
  if (!Number.isFinite(box.min[0])) return null;
  const min = box.min.map((v) => round(v * SCALE));
  const max = box.max.map((v) => round(v * SCALE));
  return {
    min,
    max,
    size: min.map((v, i) => round(max[i] - v)),
    center: min.map((v, i) => round((v + max[i]) / 2)),
  };
}
function elementBox(uuid, box = EMPTY()) {
  const element = elements.get(uuid);
  const frame = frames.get(uuid);
  if (!element || !frame) return box;
  for (const v of Object.values(element.vertices ?? {})) expand(box, add(apply3(frame.r, v), frame.t));
  // The base body is mesh-only; stay safe if a cube ever appears.
  if (element.from && element.to) {
    const origin = element.origin ?? [0, 0, 0];
    for (let i = 0; i < 8; i++) {
      const corner = [
        i & 1 ? element.to[0] : element.from[0],
        i & 2 ? element.to[1] : element.from[1],
        i & 4 ? element.to[2] : element.from[2],
      ].map((c, k) => c - origin[k]);
      expand(box, add(apply3(frame.r, corner), frame.t));
    }
  }
  return box;
}
function subtreeBox(rootUuid) {
  const box = EMPTY();
  const stack = [rootUuid];
  while (stack.length) {
    const uuid = stack.pop();
    if (meta.get(uuid)?.kind === "element") elementBox(uuid, box);
    for (const child of childrenOf.get(uuid) ?? []) stack.push(child);
  }
  return finish(box);
}

// ---- named body regions -------------------------------------------------------------
const partsByName = new Map();
for (const [uuid, m] of meta) {
  if (m.kind !== "element") continue;
  partsByName.set(m.name, [...(partsByName.get(m.name) ?? []), uuid]);
}
const named = (name) => partsByName.get(name) ?? [];
/**
 * The character's LEFT is -Z (forward x left = up requires +X x -Z = +Y), and the source spells
 * the +Z side "_left". Regions are keyed by the PHYSICAL side, so they resolve by geometry here
 * and by SOURCE_NODE_BY_SIDE in base-rig.ts. See docs/phase-2.md.
 */
function pickSide(name, side) {
  const scored = named(name).map((uuid) => ({ uuid, z: finish(elementBox(uuid))?.center[2] ?? 0 }));
  scored.sort((a, b) => (side === "left" ? a.z - b.z : b.z - a.z));
  return scored[0] ? [scored[0].uuid] : [];
}
const REGION_SOURCES = {
  head: named("ganmenn"),
  head_with_ears: [...named("ganmenn"), ...named("mimi_left"), ...named("mimi_right")],
  neck: named("kubi"),
  torso: named("dou"),
  // Source "_left" meshes sit at +Z, which is the character's RIGHT.
  shoulder_left: named("kata_right"),
  shoulder_right: named("kata_left"),
  upper_arm_left: named("ude_right"),
  upper_arm_right: named("ude_left"),
  forearm_left: named("tekubi_right"),
  forearm_right: named("tekubi_left"),
  hand_left: named("te_right"),
  hand_right: named("te_left"),
  pelvis: named("koshi"),
  thigh_left: named("momo_right"),
  thigh_right: named("momo_left"),
  ankle_left: pickSide("ashikubi", "left"),
  ankle_right: pickSide("ashikubi", "right"),
  foot_left: pickSide("ashisaki", "left"),
  foot_right: pickSide("ashisaki", "right"),
};
const regions = {};
for (const [key, uuids] of Object.entries(REGION_SOURCES)) {
  if (!uuids.length) continue;
  const box = EMPTY();
  for (const uuid of uuids) elementBox(uuid, box);
  const result = finish(box);
  if (result) regions[key] = result;
}

// ---- sockets: Phase 2 parent-local definition + measured rest-pose world position ----
const sockets = {};
for (const socket of analysis.sockets) {
  const frame = frames.get(socket.parentUuid);
  if (!frame) continue;
  sockets[socket.id] = {
    parent: socket.parent,
    parentUuid: socket.parentUuid,
    // Phase 2 mapping values, unchanged: local anchor at the existing group pivot.
    position: socket.position,
    rotation: socket.rotation,
    scale: [1, 1, 1],
    space: socket.space,
    status: socket.status,
    // Derived rest-pose world position in metres (Phase 5 normalization; no new scale rule).
    worldPosition: frame.t.map((v) => round(v * SCALE)),
  };
}

// ---- existing source props: measured, but explicitly NOT a validated size standard ----
// Only the equipment roots (a nested grip/blade group is not a prop of its own).
const equipmentByUuid = new Map(analysis.equipmentGroups.map((g) => [g.uuid, g]));
const referenceProps = {};
for (const group of analysis.equipmentGroups) {
  if (group.parent && equipmentByUuid.has(group.parent)) continue;
  const box = subtreeBox(group.uuid);
  if (!box) continue;
  referenceProps[group.name] = {
    classification: group.classification.replace(/^equipment:/, ""),
    visibleInPreview: group.visible && group.exported,
    size: box.size,
    longestAxis: round(Math.max(...box.size)),
    note: "Prop that exists inside base_1.bbmodel, measured in rest pose. Most are hidden placeholders and are NOT a validated size standard; use recommendedLength instead.",
  };
}

// ---- self-check: our transform walk must reproduce the Phase 2 three.js bounds ----
const bodyBox = EMPTY();
for (const part of analysis.bodyParts) {
  if (part.visible && part.exported) elementBox(part.uuid, bodyBox);
}
for (let i = 0; i < 3; i++) {
  const dMin = Math.abs(bodyBox.min[i] - analysis.bounds.min[i]);
  const dMax = Math.abs(bodyBox.max[i] - analysis.bounds.max[i]);
  if (dMin > 1e-6 || dMax > 1e-6) {
    throw new Error(`Transform mismatch vs analysis.bounds on axis ${i}: ${dMin} / ${dMax}`);
  }
}

const heightM = round(analysis.bounds.size[1] * SCALE);
const character = {
  height: heightM,
  size: analysis.bounds.size.map((v) => round(v * SCALE)),
  min: analysis.bounds.min.map((v) => round(v * SCALE)),
  max: analysis.bounds.max.map((v) => round(v * SCALE)),
  headHeight: regions.head ? regions.head.size[1] : null,
  headsTall: regions.head ? round(heightM / regions.head.size[1]) : null,
  note: "Visible exported body meshes in rest pose, including the tilted legs.",
};

/**
 * Recommended overall length per weapon type, as a fraction of the measured character height.
 * Derived from the character, not from the hidden placeholder props in the source, which are not
 * a validated size standard. Ratios are authoring guidance and stay editable.
 */
const WEAPON_LENGTH_RATIO = {
  sword: [0.42, 0.58],
  great_sword: [0.6, 0.8],
  spear: [0.85, 1.15],
  bow: [0.55, 0.8],
  dagger: [0.18, 0.3],
  staff: [0.8, 1.05],
};
const recommendedLength = {};
for (const [type, [lo, hi]] of Object.entries(WEAPON_LENGTH_RATIO)) {
  recommendedLength[type] = {
    min: round(heightM * lo),
    max: round(heightM * hi),
    ratioOfCharacterHeight: [lo, hi],
  };
}

const out = {
  specVersion: 1,
  generator: "scripts/build-measurements.mjs",
  source: analysis.source,
  coordinates: analysis.coordinates,
  units: "metres",
  metersPerSourceUnit: SCALE,
  character,
  regions,
  sockets,
  recommendedLength,
  referenceProps,
};
await writeFile(new URL("measurements.json", base), JSON.stringify(out, null, 2) + "\n");
console.log(JSON.stringify({
  character,
  regions: Object.keys(regions).length,
  sockets: Object.keys(sockets).length,
  referenceProps: Object.keys(referenceProps),
}, null, 2));
