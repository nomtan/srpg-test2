"use client";

// Bridge from Asset Creator (Phase 4) to the Phase 7 filesystem Library (spec prompt 37-38).
import { useMemo, useState } from "react";
import type { AssetMetadata } from "@/domain/asset";
import { useLibraryIndex, refreshLibrary } from "./use-library-index";
import { saveAsset } from "./mutations";

export function CreatorLibrarySave({ metadata, modelUrl, textureUrl, thumbnail }: {
  metadata: AssetMetadata;
  modelUrl: string | null;
  textureUrl: string | null;
  thumbnail: string | null;
}) {
  const { index } = useLibraryIndex();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const existing = useMemo(
    () => index.assets.find((a) => a.metadata.id === metadata.id) ?? null,
    [index.assets, metadata.id],
  );

  async function save() {
    if (!metadata.id) { setMsg("ID を入力してください。"); return; }
    setBusy(true); setMsg(null);
    try {
      const modelBlob = modelUrl ? await (await fetch(modelUrl)).blob() : null;
      const textureBlob = textureUrl ? await (await fetch(textureUrl)).blob() : null;
      const rec = await saveAsset({
        metadata, modelBlob, textureBlob, thumbnailDataUrl: thumbnail,
        existing, origin: "creator",
        versionNote: existing ? "updated from Asset Creator" : "created",
      });
      await refreshLibrary();
      setMsg(existing
        ? `Update Existing: ${rec.metadata.id} を v${existing.metadata.assetVersion} → v${rec.metadata.assetVersion} で保存しました。`
        : `Create New: ${rec.metadata.id} (v${rec.metadata.assetVersion}) を Asset Library に登録しました。`);
    } catch (e) {
      setMsg(`保存失敗: ${e instanceof Error ? e.message : String(e)}`);
    } finally { setBusy(false); }
  }

  return (
    <div className="creator-lib-save">
      <button type="button" disabled={busy} onClick={save}>
        {existing ? `Update Existing in Library (v${existing.metadata.assetVersion} → v${existing.metadata.assetVersion + 1})` : "Save to Asset Library (Create New)"}
      </button>
      {existing && <span className="muted"> 既存 ID: 現在 v{existing.metadata.assetVersion}</span>}
      {msg && <p className="save-msg">{msg}</p>}
    </div>
  );
}
