// Phase 7 persistence (spec prompt 47-48): a file-based library index under
// tools/character-editor/library-data/. This is the source of truth for management metadata;
// the actual assets stay file-based (repository dirs / imported packages), never a UI-only blob
// store. Server-only — imported exclusively from route handlers.
import { promises as fs } from "node:fs";
import path from "node:path";
import {
  emptyRegistryFile, type AssetRecord, type CharacterRecord, type LibraryIndex, type RegistryFile,
} from "@/domain/library-index";
import { builtinPresets, parsePreset, type VariationPreset } from "@/domain/variation-preset";
import { parseProductionJob, type ProductionJob, type ProductionStage } from "@/domain/production-job";
import { defaultPaletteLibrary, normalizePaletteLibrary, type PaletteLibrary } from "@/domain/variation-palette";

const ROOT = path.join(process.cwd(), "library-data");
const ASSETS_DIR = path.join(ROOT, "assets");
const CHARS_DIR = path.join(ROOT, "characters");
const REGISTRY_FILE = path.join(ROOT, "registry.json");
// Phase 8 (spec section 41): one JSON per Variation Preset, plus a single Palette Set file.
const PRESETS_DIR = path.join(ROOT, "variation-presets");
const PALETTES_FILE = path.join(ROOT, "palette-sets.json");
// Phase 9 (spec section 36): AI production staging, one directory per asset being produced.
const PRODUCTION_DIR = path.join(ROOT, "asset-production");
const PRODUCTION_STAGES: ProductionStage[] = ["incoming", "approved", "rejected", "reference"];

const SAFE = /^[a-z0-9][a-z0-9_.-]*$/;
export function safeId(id: string): string {
  if (!SAFE.test(id) || id.includes("..")) throw new Error(`Unsafe id: ${id}`);
  return id;
}
const ALLOWED_FILES = new Set(["model.glb", "texture.png", "thumbnail.png"]);
function safeFileName(name: string): string {
  if (!ALLOWED_FILES.has(name)) throw new Error(`Unsupported file: ${name}`);
  return name;
}

async function ensureDirs() {
  await fs.mkdir(ASSETS_DIR, { recursive: true });
  await fs.mkdir(CHARS_DIR, { recursive: true });
}

const PRODUCTION_FILE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$/;
const PRODUCTION_EXT = new Set([".glb", ".png", ".bbmodel", ".jpg", ".jpeg", ".webp"]);
function safeProductionFile(name: string): string {
  if (!PRODUCTION_FILE.test(name) || name.includes("..")) throw new Error(`Unsafe file name: ${name}`);
  const ext = name.slice(name.lastIndexOf(".")).toLowerCase();
  if (!PRODUCTION_EXT.has(ext)) throw new Error(`Unsupported production file: ${name}`);
  return name;
}
function safeStage(stage: string): ProductionStage {
  if (!PRODUCTION_STAGES.includes(stage as ProductionStage)) throw new Error(`Unknown stage: ${stage}`);
  return stage as ProductionStage;
}

async function exists(p: string): Promise<boolean> {
  try { await fs.access(p); return true; } catch { return false; }
}

async function readJson<T>(p: string): Promise<T | null> {
  try { return JSON.parse(await fs.readFile(p, "utf8")) as T; } catch { return null; }
}

async function writeJson(p: string, value: unknown) {
  await fs.mkdir(path.dirname(p), { recursive: true });
  await fs.writeFile(p, JSON.stringify(value, null, 2) + "\n", "utf8");
}

async function listSubdirs(dir: string): Promise<string[]> {
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    return entries.filter((e) => e.isDirectory()).map((e) => e.name);
  } catch { return []; }
}

// ---- Assets ----------------------------------------------------------------
export async function readAssetRecord(id: string): Promise<AssetRecord | null> {
  const rec = await readJson<AssetRecord>(path.join(ASSETS_DIR, safeId(id), "index.json"));
  if (!rec) return null;
  return withAssetFileFlags(id, rec);
}

async function withAssetFileFlags(id: string, rec: AssetRecord): Promise<AssetRecord> {
  const dir = path.join(ASSETS_DIR, id);
  const [model, texture, thumbnail] = await Promise.all([
    exists(path.join(dir, "model.glb")),
    exists(path.join(dir, "texture.png")),
    exists(path.join(dir, "thumbnail.png")),
  ]);
  return { ...rec, files: { ...rec.files, model, texture, thumbnail } };
}

export async function writeAssetRecord(rec: AssetRecord): Promise<void> {
  await ensureDirs();
  await writeJson(path.join(ASSETS_DIR, safeId(rec.metadata.id), "index.json"), rec);
}

export async function deleteAssetDir(id: string): Promise<void> {
  await fs.rm(path.join(ASSETS_DIR, safeId(id)), { recursive: true, force: true });
}

// ---- Characters ----------------------------------------------------------------
export async function readCharacterRecord(id: string): Promise<CharacterRecord | null> {
  const rec = await readJson<CharacterRecord>(path.join(CHARS_DIR, safeId(id), "index.json"));
  if (!rec) return null;
  const thumbnail = await exists(path.join(CHARS_DIR, id, "thumbnail.png"));
  return { ...rec, thumbnail };
}

export async function writeCharacterRecord(rec: CharacterRecord): Promise<void> {
  await ensureDirs();
  await writeJson(path.join(CHARS_DIR, safeId(rec.recipe.id), "index.json"), rec);
}

export async function deleteCharacterDir(id: string): Promise<void> {
  await fs.rm(path.join(CHARS_DIR, safeId(id)), { recursive: true, force: true });
}

// ---- Binary files ----------------------------------------------------------------
type Kind = "asset" | "character";
function fileDir(kind: Kind, id: string): string {
  return kind === "asset" ? path.join(ASSETS_DIR, safeId(id)) : path.join(CHARS_DIR, safeId(id));
}

export async function writeBinary(kind: Kind, id: string, name: string, bytes: Buffer): Promise<void> {
  const dir = fileDir(kind, id);
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(path.join(dir, safeFileName(name)), bytes);
}

export async function readBinary(kind: Kind, id: string, name: string): Promise<Buffer | null> {
  try { return await fs.readFile(path.join(fileDir(kind, id), safeFileName(name))); }
  catch { return null; }
}

// ---- Registry ----------------------------------------------------------------
export async function readRegistry(): Promise<RegistryFile> {
  return (await readJson<RegistryFile>(REGISTRY_FILE)) ?? emptyRegistryFile();
}

export async function writeRegistry(file: RegistryFile): Promise<void> {
  await ensureDirs();
  await writeJson(REGISTRY_FILE, file);
}

// ---- Variation Presets (Phase 8) --------------------------------------------------
/**
 * First run seeds the built-in presets (kingdom_soldier, villager, ...) onto disk so the
 * Variation Generator opens with something editable. Afterwards the directory is authoritative:
 * a deleted preset stays deleted.
 */
async function ensurePresetDir(): Promise<void> {
  if (await exists(PRESETS_DIR)) return;
  await fs.mkdir(PRESETS_DIR, { recursive: true });
  for (const preset of builtinPresets()) {
    await writeJson(path.join(PRESETS_DIR, `${preset.id}.json`), preset);
  }
}

export async function readPresets(): Promise<VariationPreset[]> {
  await ensurePresetDir();
  let names: string[] = [];
  try {
    names = (await fs.readdir(PRESETS_DIR)).filter((n) => n.endsWith(".json"));
  } catch { return []; }
  const presets: VariationPreset[] = [];
  for (const name of names) {
    const raw = await readJson<unknown>(path.join(PRESETS_DIR, name));
    if (raw) presets.push(parsePreset(raw));
  }
  presets.sort((a, b) => a.id.localeCompare(b.id));
  return presets;
}

export async function writePreset(preset: VariationPreset): Promise<void> {
  await ensurePresetDir();
  await writeJson(path.join(PRESETS_DIR, `${safeId(preset.id)}.json`), preset);
}

export async function deletePreset(id: string): Promise<void> {
  await fs.rm(path.join(PRESETS_DIR, `${safeId(id)}.json`), { force: true });
}

// ---- Palette Sets (Phase 8) --------------------------------------------------------
export async function readPalettes(): Promise<PaletteLibrary> {
  const raw = await readJson<unknown>(PALETTES_FILE);
  if (!raw) {
    const defaults = defaultPaletteLibrary();
    await writeJson(PALETTES_FILE, defaults);
    return defaults;
  }
  return normalizePaletteLibrary(raw);
}

export async function writePalettes(library: PaletteLibrary): Promise<void> {
  await ensureDirs();
  await writeJson(PALETTES_FILE, { ...normalizePaletteLibrary(library), updatedAt: new Date().toISOString() });
}

// ---- Production jobs (Phase 9) ------------------------------------------------------
export async function readProductionJob(id: string): Promise<ProductionJob | null> {
  const raw = await readJson<unknown>(path.join(PRODUCTION_DIR, safeId(id), "job.json"));
  return raw ? parseProductionJob(raw) : null;
}

export async function writeProductionJob(job: ProductionJob): Promise<void> {
  const dir = path.join(PRODUCTION_DIR, safeId(job.id));
  await writeJson(path.join(dir, "job.json"), job);
  for (const stage of PRODUCTION_STAGES) await fs.mkdir(path.join(dir, stage), { recursive: true });
}

export async function deleteProductionJob(id: string): Promise<void> {
  await fs.rm(path.join(PRODUCTION_DIR, safeId(id)), { recursive: true, force: true });
}

export async function readProductionJobs(): Promise<ProductionJob[]> {
  const dirs = await listSubdirs(PRODUCTION_DIR);
  const jobs = (await Promise.all(dirs.map((d) => readProductionJob(d)))).filter(Boolean) as ProductionJob[];
  jobs.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  return jobs;
}

function productionPath(id: string, stage: string, name: string): string {
  return path.join(PRODUCTION_DIR, safeId(id), safeStage(stage), safeProductionFile(name));
}

export async function writeProductionFile(id: string, stage: string, name: string, bytes: Buffer): Promise<void> {
  const target = productionPath(id, stage, name);
  await fs.mkdir(path.dirname(target), { recursive: true });
  await fs.writeFile(target, bytes);
}

export async function readProductionFile(id: string, stage: string, name: string): Promise<Buffer | null> {
  try { return await fs.readFile(productionPath(id, stage, name)); } catch { return null; }
}

export async function deleteProductionFile(id: string, stage: string, name: string): Promise<void> {
  await fs.rm(productionPath(id, stage, name), { force: true });
}

/** Move a delivered file between staging folders on approve / reject (spec section 36). */
export async function moveProductionFile(id: string, from: string, to: string, name: string): Promise<void> {
  const source = productionPath(id, from, name);
  const target = productionPath(id, to, name);
  await fs.mkdir(path.dirname(target), { recursive: true });
  try { await fs.rename(source, target); }
  catch { await fs.copyFile(source, target).then(() => fs.rm(source, { force: true })); }
}

// ---- Whole index ----------------------------------------------------------------
export async function readIndex(): Promise<LibraryIndex> {
  await ensureDirs();
  const [assetDirs, charDirs, registry, presets, palettes, productions] = await Promise.all([
    listSubdirs(ASSETS_DIR),
    listSubdirs(CHARS_DIR),
    readRegistry(),
    readPresets(),
    readPalettes(),
    readProductionJobs(),
  ]);
  const assets = (await Promise.all(assetDirs.map((d) => readAssetRecord(d)))).filter(Boolean) as AssetRecord[];
  const characters = (await Promise.all(charDirs.map((d) => readCharacterRecord(d)))).filter(Boolean) as CharacterRecord[];
  assets.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  characters.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  return { assets, characters, registry, presets, palettes, productions };
}

/** Backup blob (spec prompt 41): index + versions + tags + dependencies, not the binaries. */
export async function buildBackup(): Promise<unknown> {
  const index = await readIndex();
  return {
    exportedAt: new Date().toISOString(),
    tool: "srpg-character-editor",
    phase: 9,
    assets: index.assets.map((a) => ({
      id: a.metadata.id,
      name: a.metadata.name,
      type: a.metadata.type,
      assetVersion: a.metadata.assetVersion,
      tags: a.tags,
      favorite: a.favorite,
      validation: a.validation.status,
      versionHistory: a.versionHistory,
      updatedAt: a.updatedAt,
      metadata: a.metadata,
    })),
    characters: index.characters.map((c) => ({
      id: c.recipe.id,
      name: c.name,
      characterVersion: c.recipe.characterVersion ?? 1,
      tags: c.tags,
      validation: c.validation.status,
      export: c.export,
      registry: c.registry,
      versionHistory: c.versionHistory,
      updatedAt: c.updatedAt,
      recipe: c.recipe,
    })),
    registry: index.registry,
    variationPresets: index.presets,
    paletteSets: index.palettes,
    productions: index.productions.map((job) => ({
      id: job.id,
      name: job.name,
      status: job.status,
      promptVersion: job.promptVersion,
      tags: job.tags,
      revisions: job.revisions.map((r) => ({
        revision: r.revision,
        stage: r.stage,
        decision: r.decision,
        verdict: r.validation.verdict,
        score: r.validation.score,
        createdAt: r.createdAt,
      })),
      updatedAt: job.updatedAt,
    })),
  };
}
