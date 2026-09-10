"use client";

// Thin client for the Phase 7 Library API. All calls hit the local Next route handler which
// reads/writes tools/character-editor/library-data/.
import type { AssetRecord, CharacterRecord, LibraryIndex, RegistryFile } from "@/domain/library-index";

const BASE = "/api/library";

async function jfetch<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, { cache: "no-store", ...init });
  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const error = new Error(body?.error ?? body?.message ?? `${res.status} ${res.statusText}`);
    Object.assign(error, { status: res.status, body });
    throw error;
  }
  return body as T;
}

export const fetchLibraryIndex = () => jfetch<LibraryIndex>(BASE);
export const fetchRegistry = () => jfetch<RegistryFile>(`${BASE}/registry`);
export const fetchBackup = () => jfetch<unknown>(`${BASE}/backup`);

export const putAssetRecord = (rec: AssetRecord) =>
  jfetch<{ ok: true }>(`${BASE}/asset/${rec.metadata.id}`, {
    method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify(rec),
  });

export const putCharacterRecord = (rec: CharacterRecord) =>
  jfetch<{ ok: true }>(`${BASE}/character/${rec.recipe.id}`, {
    method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify(rec),
  });

export const putRegistry = (file: RegistryFile) =>
  jfetch<{ ok: true }>(`${BASE}/registry`, {
    method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify(file),
  });

export interface DeleteAssetError { error: "in_use"; usedByCount: number; usedBy: string[] }
export const deleteAsset = (id: string, force = false) =>
  jfetch<{ ok: true }>(`${BASE}/asset/${id}${force ? "?force=1" : ""}`, { method: "DELETE" });

export const deleteCharacter = (id: string, force = false) =>
  jfetch<{ ok: true }>(`${BASE}/character/${id}${force ? "?force=1" : ""}`, { method: "DELETE" });

export type LibFileKind = "asset" | "character";
export type LibFileName = "model.glb" | "texture.png" | "thumbnail.png";

export const libFileUrl = (kind: LibFileKind, id: string, name: LibFileName) =>
  `${BASE}/${kind}/${id}/file/${name}`;

export async function putFile(kind: LibFileKind, id: string, name: LibFileName, data: Blob | ArrayBuffer | Uint8Array) {
  return jfetch<{ ok: true; bytes: number }>(`${BASE}/${kind}/${id}/file/${name}`, {
    method: "PUT", headers: { "content-type": "application/octet-stream" }, body: data as BodyInit,
  });
}

/** Copy files that exist between two library ids (used by Duplicate). */
export async function copyFiles(kind: LibFileKind, fromId: string, toId: string, names: LibFileName[]) {
  for (const name of names) {
    const res = await fetch(libFileUrl(kind, fromId, name), { cache: "no-store" });
    if (!res.ok) continue;
    const buf = await res.arrayBuffer();
    if (buf.byteLength) await putFile(kind, toId, name, buf);
  }
}

export async function dataUrlToBlob(dataUrl: string): Promise<Blob> {
  return (await fetch(dataUrl)).blob();
}
