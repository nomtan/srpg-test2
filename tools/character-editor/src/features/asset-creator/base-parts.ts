// Base body part list for the hideParts picker. Sourced from the generated base analysis
// (spec section 14: pick from the existing part map, do not free-type strings).
import analysis from "../../../public/generated-assets/base_body/analysis.json";
import { baseSocketDefinitions } from "@/domain/base-rig";
import type { CharacterSocket } from "@/domain/constants";

export interface BasePart {
  name: string;
  uuids: string[];
  hint: string;
}

const ROLE_HINTS: Record<string, string> = {
  ganmenn: "head / face", mimi_left: "ear L", mimi_right: "ear R", kubi: "neck",
  dou: "torso", kata_left: "shoulder L", kata_right: "shoulder R",
  ude_left: "upper arm L", ude_right: "upper arm R",
  tekubi_left: "forearm L", tekubi_right: "forearm R",
  te_left: "hand L", te_right: "hand R", koshi: "pelvis",
  momo_left: "thigh L", momo_right: "thigh R",
  ashikubi: "ankle", ashisaki: "foot",
};

export const BASE_PARTS: BasePart[] = Object.values(
  analysis.bodyParts
    .filter((p) => p.visible && p.exported)
    .reduce<Record<string, BasePart>>((acc, part) => {
      const entry = acc[part.name] ?? { name: part.name, uuids: [], hint: ROLE_HINTS[part.name] ?? "" };
      entry.uuids.push(part.uuid);
      acc[part.name] = entry;
      return acc;
    }, {}),
);

/**
 * Node name -> body part name is NOT reliable after loading the base GLB.
 *
 * GLTFLoader uniquifies duplicate node names, so the base model's two `ashisaki` / `ashikubi`
 * meshes arrive as `ashisaki` + `ashisaki_1`, and the torso mesh `dou` collides with the group
 * node of the same name and arrives as `dou_1`. Matching on the name silently misses those.
 *
 * Every mesh node carries its Blockbench element UUID in `extras.sourceUuid`, which GLTFLoader
 * puts into `userData`. That is stable and unique, so resolve through it.
 */
const PART_NAME_BY_UUID: Record<string, string> = Object.fromEntries(
  BASE_PARTS.flatMap((part) => part.uuids.map((uuid) => [uuid, part.name])),
);

/** The body part a loaded base-GLB object belongs to, or null if it is not a body part. */
const BASE_PART_NAMES = new Set(BASE_PARTS.map((p) => p.name));

export function basePartNameOf(object: { name?: string; userData?: Record<string, unknown> }): string | null {
  const uuid = object.userData?.sourceUuid;
  if (typeof uuid === "string") return PART_NAME_BY_UUID[uuid] ?? null;
  // Fallback for objects that lost their extras: strip GLTFLoader's "_1" disambiguation suffix.
  const name = object.name ?? "";
  const stripped = name.replace(/_\d+$/, "");
  if (BASE_PART_NAMES.has(name)) return name;
  return BASE_PART_NAMES.has(stripped) ? stripped : null;
}

/** Which base GLB group node an asset attaches under, for a given socket. */
export function socketNodeName(socket: CharacterSocket): string | null {
  return baseSocketDefinitions.find((s) => s.id === socket)?.parent ?? null;
}

export const BASE_REST_SIZE_METERS: readonly [number, number, number] = [
  analysis.bounds.size[0] * analysis.coordinates.metersPerSourceUnit,
  analysis.bounds.size[1] * analysis.coordinates.metersPerSourceUnit,
  analysis.bounds.size[2] * analysis.coordinates.metersPerSourceUnit,
];
