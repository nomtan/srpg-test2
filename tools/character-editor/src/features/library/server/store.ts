// Phase 7 persistence (spec prompt 47-48): a file-based library index under
// tools/character-editor/library-data/. This is the source of truth for management metadata;
// the actual assets stay file-based (repository dirs / imported packages), never a UI-only blob
// store. Server-only — imported exclusively from route handlers.
import { promises as fs } from "node:fs";
import path from "node:path";
import {
  emptyRegistryFile, type AssetRecord, type CharacterRecord, type LibraryIndex, type RegistryFile,
} from "@/domain/library-index";

const ROOT = path.join(process.cwd(), "library-data");
const ASSETS_DIR = path.join(ROOT, "assets");
const CHARS_DIR = path.join(ROOT, "characters");
const REGISTRY_FILE = path.join(ROOT, "registry.json");

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

// ---- Whole index ----------------------------------------------------------------
export async function readIndex(): Promise<LibraryIndex> {
  await ensureDirs();
  const [assetDirs, charDirs, registry] = await Promise.all([
    listSubdirs(ASSETS_DIR),
    listSubdirs(CHARS_DIR),
    readRegistry(),
  ]);
  const assets = (await Promise.all(assetDirs.map((d) => readAssetRecord(d)))).filter(Boolean) as AssetRecord[];
  const characters = (await Promise.all(charDirs.map((d) => readCharacterRecord(d)))).filter(Boolean) as CharacterRecord[];
  assets.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  characters.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  return { assets, characters, registry };
}

/** Backup blob (spec prompt 41): index + versions + tags + dependencies, not the binaries. */
export async function buildBackup(): Promise<unknown> {
  const index = await readIndex();
  return {
    exportedAt: new Date().toISOString(),
    tool: "srpg-character-editor",
    phase: 7,
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
  };
}
