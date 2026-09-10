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

/** Which base GLB group node an asset attaches under, for a given socket. */
export function socketNodeName(socket: CharacterSocket): string | null {
  return baseSocketDefinitions.find((s) => s.id === socket)?.parent ?? null;
}

export const BASE_REST_SIZE_METERS: readonly [number, number, number] = [
  analysis.bounds.size[0] * analysis.coordinates.metersPerSourceUnit,
  analysis.bounds.size[1] * analysis.coordinates.metersPerSourceUnit,
  analysis.bounds.size[2] * analysis.coordinates.metersPerSourceUnit,
];
