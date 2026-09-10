"use client";

import { useState } from "react";
import { ASSET_CATEGORIES, CATEGORY_LABELS, type AssetCategory } from "@/domain/constants";
import { assetLibrary } from "./asset-library";
import { listAssets, type AssetLibrary, type AssetLibraryEntry } from "./library";

const PROVENANCE_LABEL: Record<string, string> = { source: "SOURCE BASE", demo: "DEMO", user: "USER" };

export function AssetBrowser({ library = assetLibrary, selectedId, onSelect }: {
  library?: AssetLibrary;
  selectedId: string;
  onSelect: (entry: AssetLibraryEntry) => void;
}) {
  const [category, setCategory] = useState<AssetCategory | undefined>();
  const entries = listAssets(library, { category });
  return <aside className="panel library">
    <div className="panel-heading"><h2>Asset Library</h2><span className="count">{library.ids.length}</span></div>
    <label>カテゴリー<select value={category ?? "all"} onChange={(event) => setCategory(event.target.value === "all" ? undefined : event.target.value as AssetCategory)}>
      <option value="all">すべてのアセット</option>{ASSET_CATEGORIES.map((item) => <option key={item} value={item}>{CATEGORY_LABELS[item]}</option>)}
    </select></label>
    <div className="asset-list">{entries.map((entry) => <button className={`asset-card ${selectedId === entry.metadata.id ? "selected" : ""}`} key={entry.metadata.id} aria-pressed={selectedId === entry.metadata.id} onClick={() => onSelect(entry)}>
      <span className="asset-symbol" aria-hidden="true">{entry.metadata.type === "base" ? "▦" : entry.metadata.type === "weapon" ? "⚔" : "⬡"}</span>
      <span><small>{CATEGORY_LABELS[entry.metadata.type]}</small><strong>{entry.metadata.name}</strong><small>{PROVENANCE_LABEL[entry.provenance ?? ""] ?? "STATIC"} · {entry.metadata.model ? "GLB" : "META"} · v{entry.metadata.assetVersion}</small></span>
    </button>)}{entries.length === 0 && <p className="empty-list">このカテゴリーにはまだアセットがありません。</p>}</div>
    <p className="muted">Baseは指定Sourceから生成した正式基準素体です。USERはAsset Creatorで保存したAssetでこのブラウザのlocalStorageに保存されています。</p>
  </aside>;
}
