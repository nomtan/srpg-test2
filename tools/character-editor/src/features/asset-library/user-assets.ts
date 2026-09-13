"use client";

// Legacy Phase 4 persistence. Retired: library-data/ is the Git-tracked store now, and a
// localStorage blob cannot be committed, reviewed or shared.
//
// The read path stays so assets saved before the switch keep showing up in the pickers instead of
// vanishing; re-save them through "Save to Asset Library" to bring them into Git. Nothing writes
// here any more.
import { useSyncExternalStore } from "react";
import type { AssetMetadata } from "@/domain/asset";

const KEY = "srpg-character-editor/user-assets/v1";
const EVENT = "srpg-user-assets-changed";

export interface UserAsset {
  metadata: AssetMetadata;
  /** data: URLs so the entry is self-contained across reloads. */
  model?: string;
  texture?: string;
  thumbnail?: string;
  savedAt: string;
}

function read(): UserAsset[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed.filter((a) => a?.metadata?.id) : [];
  } catch {
    return [];
  }
}

function write(assets: UserAsset[]) {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(assets));
  } catch {
    throw new Error("localStorage への保存に失敗しました（容量超過の可能性）。GLB / Texture のサイズを小さくするか Package Download を使用してください。");
  }
  window.dispatchEvent(new Event(EVENT));
}

export function loadUserAssets(): UserAsset[] {
  return read();
}

/** @deprecated Nothing calls this: assets are saved to library-data/ via the Library API. */
export function saveUserAsset(asset: UserAsset): { replaced: boolean } {
  const assets = read();
  const index = assets.findIndex((a) => a.metadata.id === asset.metadata.id);
  if (index >= 0) assets[index] = asset;
  else assets.push(asset);
  write(assets);
  return { replaced: index >= 0 };
}

export function removeUserAsset(id: string) {
  write(read().filter((a) => a.metadata.id !== id));
}

function subscribe(callback: () => void) {
  const onStorage = (e: StorageEvent) => { if (e.key === KEY) callback(); };
  window.addEventListener(EVENT, callback);
  window.addEventListener("storage", onStorage);
  return () => {
    window.removeEventListener(EVENT, callback);
    window.removeEventListener("storage", onStorage);
  };
}

// Cache the snapshot so useSyncExternalStore sees a stable reference between changes.
let cache: UserAsset[] = [];
let cacheRaw: string | null = null;
function getSnapshot(): UserAsset[] {
  if (typeof window === "undefined") return cache;
  const raw = window.localStorage.getItem(KEY);
  if (raw !== cacheRaw) { cacheRaw = raw; cache = read(); }
  return cache;
}
const EMPTY: UserAsset[] = [];

export function useUserAssets(): UserAsset[] {
  return useSyncExternalStore(subscribe, getSnapshot, () => EMPTY);
}
