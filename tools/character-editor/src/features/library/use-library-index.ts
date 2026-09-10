"use client";

// Shared client cache of the Library Index. One fetch, many subscribers; any mutation calls
// refresh() so every screen (Dashboard / Asset Library / Character Library / Validation) stays
// in sync without prop drilling.
import { useCallback, useSyncExternalStore } from "react";
import { emptyLibraryIndex, type LibraryIndex } from "@/domain/library-index";
import { fetchLibraryIndex } from "./api";

let snapshot: LibraryIndex = emptyLibraryIndex();
let status: "idle" | "loading" | "ready" | "error" = "idle";
let error: string | null = null;
let inflight: Promise<void> | null = null;
const listeners = new Set<() => void>();

function emit() { for (const l of listeners) l(); }

export function refreshLibrary(): Promise<void> {
  if (inflight) return inflight;
  status = status === "ready" ? "ready" : "loading";
  emit();
  inflight = fetchLibraryIndex()
    .then((index) => { snapshot = index; status = "ready"; error = null; })
    .catch((e) => { status = "error"; error = e instanceof Error ? e.message : String(e); })
    .finally(() => { inflight = null; emit(); });
  return inflight;
}

function subscribe(cb: () => void) {
  listeners.add(cb);
  if (status === "idle") void refreshLibrary();
  return () => listeners.delete(cb);
}

const getSnapshot = () => snapshot;
const getServerSnapshot = () => snapshot;

export interface UseLibrary {
  index: LibraryIndex;
  loading: boolean;
  error: string | null;
  ready: boolean;
  refresh: () => Promise<void>;
}

export function useLibraryIndex(): UseLibrary {
  const index = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const refresh = useCallback(() => refreshLibrary(), []);
  return {
    index,
    loading: status === "loading",
    error: status === "error" ? error : null,
    ready: status === "ready",
    refresh,
  };
}
