"use client";

import { Suspense, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { useLibraryIndex, refreshLibrary } from "./use-library-index";
import {
  deriveLibrary, ASSET_CATEGORY_TREE, assetMatchesCategory, searchAssets, sortAssets,
  ASSET_SORTS, type AssetSort,
} from "./derive";
import { libFileUrl } from "./api";
import { patchAsset } from "./mutations";
import { LibThumb, ValidationBadge } from "./components/badges";
import { AssetDetailPanel } from "./asset-detail-panel";
import { importAssetPackage } from "./import";

function AssetLibraryInner() {
  const params = useSearchParams();
  const { index, loading, error } = useLibraryIndex();
  const derived = useMemo(() => deriveLibrary(index), [index]);

  const [category, setCategory] = useState("all");
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<AssetSort>("Newest");
  const [selectedId, setSelectedId] = useState<string | null>(params.get("id"));
  const [importMsg, setImportMsg] = useState<string | null>(null);

  const rows = useMemo(() => {
    let list = index.assets.filter((r) => assetMatchesCategory(r, category));
    list = searchAssets(list, query);
    return sortAssets(list, sort);
  }, [index.assets, category, query, sort]);

  const selected = selectedId ? derived.assetsById.get(selectedId) ?? null : null;

  async function onImport(files: FileList | null) {
    if (!files?.length) return;
    setImportMsg("Import 中…");
    try {
      const rec = await importAssetPackage(files, index);
      setImportMsg(`Import 完了: ${rec.metadata.id}`);
      await refreshLibrary();
      setSelectedId(rec.metadata.id);
    } catch (e) {
      setImportMsg(`Import 失敗: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <p className="eyebrow">ASSET LIBRARY</p>
          <h1>Asset Library</h1>
          <p>作成・Import した Asset を一覧・検索・複製・更新・バージョン管理します。一覧は Thumbnail と Metadata のみ読み込みます。</p>
        </div>
        <span className="badge">{index.assets.length} ASSETS</span>
      </div>

      {error && <p className="err">Library API エラー: {error}</p>}

      <div className="lib-layout">
        <aside className="panel lib-side">
          <div className="panel-heading"><h2>Categories</h2></div>
          <ul className="cat-tree">
            {ASSET_CATEGORY_TREE.map((n) => (
              <li key={n.id}>
                <button className={`${category === n.id ? "on" : ""} ${n.indent ? "indent" : ""}`} onClick={() => setCategory(n.id)}>{n.label}</button>
              </li>
            ))}
          </ul>
          <div className="lib-import">
            <label className="filebtn">Import Asset Package
              <input type="file" multiple accept=".json,.glb,.png" hidden onChange={(e) => onImport(e.target.files)} />
            </label>
            {importMsg && <p className="muted">{importMsg}</p>}
            <p className="muted">asset.json + model.glb + texture.png を選択。</p>
          </div>
        </aside>

        <section className="panel lib-main">
          <div className="lib-toolbar">
            <input className="lib-search" placeholder="Search assets… (id / name / type / tag)" value={query} onChange={(e) => setQuery(e.target.value)} />
            <label className="inline">Sort
              <select value={sort} onChange={(e) => setSort(e.target.value as AssetSort)}>
                {ASSET_SORTS.map((s) => <option key={s}>{s}</option>)}
              </select>
            </label>
          </div>
          <div className="lib-table">
            <div className="lib-row lib-head">
              <span></span><span>Name / ID</span><span>Type</span><span>Body</span><span>Ver</span><span>Validation</span><span>Updated</span>
            </div>
            {rows.map((r) => (
              <button key={r.metadata.id} className={`lib-row ${selectedId === r.metadata.id ? "sel" : ""}`} onClick={() => setSelectedId(r.metadata.id)}>
                <LibThumb src={r.files.thumbnail ? libFileUrl("asset", r.metadata.id, "thumbnail.png") : null} symbol={r.metadata.type === "weapon" ? "⚔" : "⬡"} label={r.metadata.name} />
                <span className="lib-name">
                  <strong>{r.favorite ? "★ " : ""}{r.metadata.name}</strong>
                  <small>{r.metadata.id}</small>
                </span>
                <span>{r.metadata.type}{r.metadata.equipment?.weaponType ? ` / ${r.metadata.equipment.weaponType}` : ""}</span>
                <span>{r.metadata.bodyTypes.join(",") || "—"}</span>
                <span>v{r.metadata.assetVersion}</span>
                <span><ValidationBadge status={r.validation.status} /></span>
                <span className="muted">{new Date(r.updatedAt).toLocaleDateString()}</span>
              </button>
            ))}
            {rows.length === 0 && !loading && <p className="empty-list">該当する Asset がありません。</p>}
          </div>
        </section>

        <aside className="panel lib-detail-wrap">
          {selected ? (
            <>
              <div className="lib-fav-bar">
                <button className="mini" onClick={async () => { await patchAsset(selected, { favorite: !selected.favorite }); await refreshLibrary(); }}>
                  {selected.favorite ? "★ Favorited" : "☆ Favorite"}
                </button>
              </div>
              <AssetDetailPanel key={selected.metadata.id} record={selected} index={index} derived={derived} />
            </>
          ) : <p className="muted lib-detail-empty">左の一覧から Asset を選択してください。</p>}
        </aside>
      </div>
    </>
  );
}

export function AssetLibraryScreen() {
  return <Suspense fallback={<p className="muted">Loading…</p>}><AssetLibraryInner /></Suspense>;
}
