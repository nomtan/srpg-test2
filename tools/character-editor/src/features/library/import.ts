"use client";

// Import existing Asset Packages / Character Recipes into the Library (spec prompt 39-40).
import type { AssetMetadata } from "@/domain/asset";
import { isSnakeCase } from "@/domain/asset-spec";
import { newAssetRecord, newCharacterRecord, type AssetRecord, type CharacterRecord, type LibraryIndex } from "@/domain/library-index";
import { nextDuplicateId } from "@/domain/library-ids";
import { validateRecipeShape } from "@/domain/builder-recipe";
import { validateAssetRecord, validateCharacterRecord, toValidationState } from "@/domain/library-validation";
import { putAssetRecord, putCharacterRecord, putFile } from "./api";

function pick(files: FileList, test: (name: string) => boolean): File | undefined {
  return Array.from(files).find((f) => test(f.name.toLowerCase()));
}

export async function importAssetPackage(files: FileList, index: LibraryIndex): Promise<AssetRecord> {
  const jsonFile = pick(files, (n) => n.endsWith(".json"));
  if (!jsonFile) throw new Error("asset.json が見つかりません。");
  const metadata = JSON.parse(await jsonFile.text()) as AssetMetadata;
  if (!metadata?.id || typeof metadata.id !== "string") throw new Error("asset.json に id がありません。");
  if (metadata.specVersion !== 1) throw new Error("specVersion が 1 ではありません。");

  const taken = new Set(["base_body", ...index.assets.map((a) => a.metadata.id)]);
  let id = metadata.id;
  if (!isSnakeCase(id)) throw new Error(`id が snake_case ではありません: ${id}`);
  if (taken.has(id)) id = nextDuplicateId(id, taken);

  const model = pick(files, (n) => n.endsWith(".glb"));
  const thumb = pick(files, (n) => n.includes("thumb") && n.endsWith(".png"));
  const texture = pick(files, (n) => n.endsWith(".png") && n !== thumb?.name.toLowerCase());

  const record = newAssetRecord(
    { ...metadata, id, assetVersion: metadata.assetVersion ?? 1 },
    "import",
    { model: !!model, texture: !!texture, thumbnail: !!thumb },
  );
  record.tags = Array.isArray(metadata.tags) ? metadata.tags : [];
  record.validation = toValidationState(validateAssetRecord(record));

  await putAssetRecord(record);
  if (model) await putFile("asset", id, "model.glb", model);
  if (texture) await putFile("asset", id, "texture.png", texture);
  if (thumb) await putFile("asset", id, "thumbnail.png", thumb);
  return record;
}

export interface RecipeImportResult {
  record: CharacterRecord;
  warnings: string[];
}

export async function importCharacterRecipe(file: File, index: LibraryIndex): Promise<RecipeImportResult> {
  const parsed = validateRecipeShape(JSON.parse(await file.text()));
  if (!parsed.recipe) {
    throw new Error(parsed.issues.find((i) => i.level === "error")?.message ?? "Recipe が不正です。");
  }
  const taken = new Set(index.characters.map((c) => c.recipe.id));
  let recipe = parsed.recipe;
  if (taken.has(recipe.id)) recipe = { ...recipe, id: nextDuplicateId(recipe.id, taken) };

  const record = newCharacterRecord(recipe, recipe.id, "import");
  const assetsById = new Map(index.assets.map((a) => [a.metadata.id, a]));
  const issues = validateCharacterRecord(record, { assetsById });
  record.validation = toValidationState(issues);

  await putCharacterRecord(record);
  const warnings = [
    ...parsed.issues.filter((i) => i.level === "warning").map((i) => i.message),
    ...issues.filter((i) => i.code === "missing").map((i) => i.message),
  ];
  return { record, warnings };
}
