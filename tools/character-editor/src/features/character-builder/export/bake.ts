// Phase 5 export orchestrator (prompt 20-23). Ties together validation, palette bake, mesh
// assembly, GLB export, metadata, packaging and round-trip validation, reporting each step so a
// failure says exactly where it happened (prompt 30).
import type { CharacterRecipe } from "@/domain/character-recipe";
import {
  buildCharacterMetadata, characterMetadataText, buildAnimationMapping,
  type CharacterExportMetadata,
} from "@/domain/character-export";
import { ANIMATION_SETS } from "@/domain/constants";
import type { AssetLibrary } from "@/features/asset-library/library";
import { createZip, downloadBlob } from "@/features/asset-creator/zip";
import { buildCharacterScene } from "../character-scene";
import { validateExport, hasBlockingErrors, type ExportIssue } from "./export-validation";
import { bakePaletteTexture } from "./palette-bake";
import { exportCharacterGlb } from "./glb-export";
import { roundTrip, type RoundTripReport } from "./round-trip";
import { godotImportGuide } from "./godot-import-guide";

export const BAKE_STEPS = [
  "Validating character",
  "Baking palette",
  "Preparing meshes",
  "Exporting animations",
  "Creating GLB",
  "Generating metadata",
  "Packaging files",
  "Round-trip validation",
] as const;
export type BakeStep = (typeof BAKE_STEPS)[number];

export class BakeError extends Error {
  constructor(public step: BakeStep, message: string, public issues: ExportIssue[] = []) {
    super(message);
    this.name = "BakeError";
  }
}

export interface BakeInput {
  recipe: CharacterRecipe;
  name: string;
  activeAnimationSet: string;
  library: AssetLibrary;
  /** Optional PNG data URL captured from the live preview. */
  thumbnailDataUrl?: string | null;
  onProgress?: (step: BakeStep, index: number, note?: string) => void;
}

export interface BakeResult {
  id: string;
  metadata: CharacterExportMetadata;
  zipBlob: Blob;
  zipName: string;
  glbBlob: Blob;
  glbUrl: string;
  paletteDataUrl: string;
  files: { name: string; bytes: number }[];
  validation: ExportIssue[];
  roundTrip: RoundTripReport;
  sceneWarnings: string[];
}

const REQUIRED_ROLES = ["idle", "walk", "run", "attack"] as const;

function requiredClips(activeSet: string): string[] {
  const map = buildAnimationMapping();
  const out = new Set<string>();
  for (const set of [activeSet, "default"]) {
    for (const role of REQUIRED_ROLES) {
      const clip = map[set]?.[role];
      if (clip) out.add(clip);
    }
  }
  return [...out];
}

export async function bakeCharacter(input: BakeInput): Promise<BakeResult> {
  const { recipe, library, onProgress } = input;
  const id = recipe.id;
  const step = (s: BakeStep, note?: string) => onProgress?.(s, BAKE_STEPS.indexOf(s), note);

  // 1 --------------------------------------------------------------------
  step("Validating character");
  const validation = validateExport({ recipe, name: input.name, library, activeAnimationSet: input.activeAnimationSet });
  if (hasBlockingErrors(validation)) {
    const first = validation.find((i) => i.level === "error");
    throw new BakeError("Validating character", `Validation error: ${first?.message ?? "重大なエラーがあります。"}`, validation);
  }

  // 2 --------------------------------------------------------------------
  step("Baking palette");
  let palette;
  try {
    palette = await bakePaletteTexture(recipe.palette);
  } catch (e) {
    throw new BakeError("Baking palette", messageOf(e), validation);
  }

  // 3 --------------------------------------------------------------------
  step("Preparing meshes");
  let built;
  try {
    built = await buildCharacterScene(recipe, library);
  } catch (e) {
    throw new BakeError("Preparing meshes", messageOf(e), validation);
  }

  try {
    // 4 ------------------------------------------------------------------
    const activeSet = (ANIMATION_SETS as readonly string[]).includes(input.activeAnimationSet) ? input.activeAnimationSet : "default";
    const wanted = requiredClips(activeSet);
    const present = new Set(built.clips.map((c) => c.name));
    const missing = wanted.filter((c) => !present.has(c));
    step("Exporting animations", missing.length ? `clip 欠落: ${missing.join(", ")}` : `${built.clips.length} clips`);
    if (built.clips.length === 0) throw new BakeError("Exporting animations", "Base GLB に Animation clip がありません。", validation);

    // 5 ------------------------------------------------------------------
    step("Creating GLB");
    let glb;
    try {
      glb = await exportCharacterGlb(built.root, built.clips);
    } catch (e) {
      throw new BakeError("Creating GLB", messageOf(e), validation);
    }

    // 6 ------------------------------------------------------------------
    step("Generating metadata");
    const metadata = buildCharacterMetadata({
      recipe,
      name: input.name,
      activeAnimationSet: activeSet,
      hiddenParts: built.hiddenParts,
      hairPolicy: built.hairPolicy,
      characterVersion: recipe.characterVersion ?? 1,
      thumbnail: !!input.thumbnailDataUrl,
    });
    const metaText = characterMetadataText(metadata);
    const guide = godotImportGuide(metadata);

    // 7 ------------------------------------------------------------------
    step("Packaging files");
    const enc = new TextEncoder();
    const glbBytes = new Uint8Array(glb.buffer.slice(0));
    const pngBytes = new Uint8Array(await palette.blob.arrayBuffer());
    const entries = [
      { name: `${id}/${id}.glb`, data: glbBytes },
      { name: `${id}/${id}.png`, data: pngBytes },
      { name: `${id}/${id}.character.json`, data: enc.encode(metaText) },
      { name: `${id}/godot_import_guide.md`, data: enc.encode(guide) },
    ];
    if (input.thumbnailDataUrl) {
      entries.push({ name: `${id}/thumbnail.png`, data: dataUrlToBytes(input.thumbnailDataUrl) });
    }
    const zipBlob = createZip(entries);

    // 8 ------------------------------------------------------------------
    step("Round-trip validation");
    let rt: RoundTripReport;
    try {
      rt = await roundTrip(glb.buffer, {
        restSize: built.restBox.size,
        equipment: built.equipment,
        requiredClips: wanted,
      });
    } catch (e) {
      throw new BakeError("Round-trip validation", messageOf(e), validation);
    }

    return {
      id,
      metadata,
      zipBlob,
      zipName: `${id}.zip`,
      glbBlob: glb.blob,
      glbUrl: URL.createObjectURL(glb.blob),
      paletteDataUrl: palette.dataUrl,
      files: entries.map((e) => ({ name: e.name, bytes: e.data.byteLength })),
      validation,
      roundTrip: rt,
      // The exported GLB carries the corrected materials, so the corrections belong in the report.
      sceneWarnings: [...built.warnings, ...built.notices.map((n) => `自動補正: ${n}`)],
    };
  } finally {
    built.dispose();
  }
}

export function downloadBakeResult(result: BakeResult) {
  downloadBlob(result.zipBlob, result.zipName);
}

function messageOf(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function dataUrlToBytes(dataUrl: string): Uint8Array<ArrayBuffer> {
  const base64 = dataUrl.slice(dataUrl.indexOf(",") + 1);
  const bin = atob(base64);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
