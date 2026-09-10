"use client";

import { Suspense, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { useLibraryIndex, refreshLibrary } from "./use-library-index";
import { deriveLibrary, searchCharacters, sortCharacters, CHARACTER_SORTS, allTags, type CharacterSort } from "./derive";
import { useMergedLibrary } from "@/features/asset-library/use-library";
import { libFileUrl } from "./api";
import { importCharacterRecipe } from "./import";
import { reexportCharacter, activeAnimationSetFor } from "./export-helpers";
import { CharacterDetailPanel } from "./character-detail-panel";
import { ExportBadge, LibThumb, RegistryBadge } from "./components/badges";

function CharacterLibraryInner() {
  const params = useSearchParams();
  const { index, error, loading } = useLibraryIndex();
  const library = useMergedLibrary();
  const derived = useMemo(() => deriveLibrary(index), [index]);

  const [query, setQuery] = useState("");
  const [tag, setTag] = useState("all");
  const [sort, setSort] = useState<CharacterSort>("Newest");
  const [filter, setFilter] = useState<string | null>(params.get("filter"));
  const [selectedId, setSelectedId] = useState<string | null>(params.get("id"));
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [autoRegister, setAutoRegister] = useState(false);
  const [batchMsg, setBatchMsg] = useState<string | null>(null);
  const [importMsg, setImportMsg] = useState<string | null>(null);

  const tags = useMemo(() => allTags(index.characters), [index.characters]);

  const rows = useMemo(() => {
    let list = [...index.characters];
    if (tag !== "all") list = list.filter((c) => c.tags.includes(tag));
    if (filter === "reexport") list = list.filter((c) => derived.exportEval.get(c.recipe.id)?.status === "reexport_required");
    if (filter === "missing") list = list.filter((c) => derived.graph.missingByCharacter[c.recipe.id]);
    if (filter === "registry") list = list.filter((c) => c.registry.status !== "registered");
    list = searchCharacters(list, query);
    return sortCharacters(list, sort, derived.exportEval);
  }, [index.characters, tag, filter, query, sort, derived]);

  const selected = selectedId ? derived.charactersById.get(selectedId) ?? null : null;

  function toggleCheck(id: string) {
    setChecked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  async function batchExport() {
    const ids = [...checked];
    if (!ids.length) return;
    setBatchMsg(`Batch export 0/${ids.length}…`);
    let ok = 0;
    for (let i = 0; i < ids.length; i++) {
      const rec = derived.charactersById.get(ids[i]);
      if (!rec) continue;
      const r = await reexportCharacter(rec, library, index, { autoRegister, download: true });
      if (r.ok) ok++;
      setBatchMsg(`Batch export ${i + 1}/${ids.length}… (${r.message})`);
    }
    await refreshLibrary();
    setBatchMsg(`Batch export 完了: ${ok}/${ids.length} 成功`);
  }

  async function onImport(file: File | undefined) {
    if (!file) return;
    setImportMsg("Import 中…");
    try {
      const { record, warnings } = await importCharacterRecipe(file, index);
      await refreshLibrary();
      setSelectedId(record.recipe.id);
      setImportMsg(warnings.length ? `Import 完了 (warning ${warnings.length}: ${warnings[0]})` : `Import 完了: ${record.recipe.id}`);
    } catch (e) {
      setImportMsg(`Import 失敗: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <p className="eyebrow">CHARACTER LIBRARY</p>
          <h1>Character Library</h1>
          <p>Character Builder / Import で作成した Character Recipe を一覧・検索・複製・再Export・Registry 登録します。</p>
        </div>
        <span className="badge">{index.characters.length} CHARACTERS</span>
      </div>

      {error && <p className="err">Library API エラー: {error}</p>}

      <div className="lib-layout">
        <aside className="panel lib-side">
          <div className="panel-heading"><h2>Filter</h2></div>
          <ul className="cat-tree">
            <li><button className={!filter ? "on" : ""} onClick={() => setFilter(null)}>All</button></li>
            <li><button className={filter === "reexport" ? "on" : ""} onClick={() => setFilter("reexport")}>Re-export Required</button></li>
            <li><button className={filter === "missing" ? "on" : ""} onClick={() => setFilter("missing")}>Missing Dependency</button></li>
            <li><button className={filter === "registry" ? "on" : ""} onClick={() => setFilter("registry")}>Not Registered</button></li>
          </ul>
          <label className="lib-side-field">Tag
            <select value={tag} onChange={(e) => setTag(e.target.value)}>
              <option value="all">All tags</option>
              {tags.map((t) => <option key={t}>{t}</option>)}
            </select>
          </label>
          <div className="lib-import">
            <label className="filebtn">Import Character Recipe
              <input type="file" accept=".json" hidden onChange={(e) => onImport(e.target.files?.[0])} />
            </label>
            {importMsg && <p className="muted">{importMsg}</p>}
          </div>
          <div className="lib-import">
            <label className="check"><input type="checkbox" checked={autoRegister} onChange={(e) => setAutoRegister(e.target.checked)} />Export 時に自動 Registry 更新</label>
            <button disabled={checked.size === 0} onClick={batchExport}>Export Selected ({checked.size})</button>
            {batchMsg && <p className="muted">{batchMsg}</p>}
          </div>
        </aside>

        <section className="panel lib-main">
          <div className="lib-toolbar">
            <input className="lib-search" placeholder="Search characters… (id / name / tag)" value={query} onChange={(e) => setQuery(e.target.value)} />
            <label className="inline">Sort
              <select value={sort} onChange={(e) => setSort(e.target.value as CharacterSort)}>
                {CHARACTER_SORTS.map((s) => <option key={s}>{s}</option>)}
              </select>
            </label>
          </div>
          <div className="lib-table char-table">
            <div className="lib-row lib-head">
              <span></span><span></span><span>Name / ID</span><span>Body</span><span>Main Weapon</span><span>Anim</span><span>Ver</span><span>Export</span><span>Registry</span>
            </div>
            {rows.map((r) => {
              const ev = derived.exportEval.get(r.recipe.id);
              const anim = activeAnimationSetFor(r.recipe, library);
              return (
                <div key={r.recipe.id} className={`lib-row char-row ${selectedId === r.recipe.id ? "sel" : ""}`}>
                  <input type="checkbox" checked={checked.has(r.recipe.id)} onChange={() => toggleCheck(r.recipe.id)} onClick={(e) => e.stopPropagation()} />
                  <button className="row-open" onClick={() => setSelectedId(r.recipe.id)}>
                    <LibThumb src={r.thumbnail ? libFileUrl("character", r.recipe.id, "thumbnail.png") : null} symbol="☗" label={r.name} />
                  </button>
                  <button className="row-open lib-name" onClick={() => setSelectedId(r.recipe.id)}>
                    <strong>{r.name}</strong><small>{r.recipe.id}{derived.graph.missingByCharacter[r.recipe.id] ? " · ⚠ missing" : ""}</small>
                  </button>
                  <span onClick={() => setSelectedId(r.recipe.id)}>{r.recipe.body.base}</span>
                  <span>{r.recipe.assets.mainHand ?? "—"}</span>
                  <span>{anim}</span>
                  <span>v{r.recipe.characterVersion ?? 1}</span>
                  <span><ExportBadge status={ev?.status ?? r.export.status} /></span>
                  <span><RegistryBadge status={r.registry.status} /></span>
                </div>
              );
            })}
            {rows.length === 0 && !loading && <p className="empty-list">該当する Character がありません。</p>}
          </div>
        </section>

        <aside className="panel lib-detail-wrap">
          {selected
            ? <CharacterDetailPanel key={selected.recipe.id} record={selected} index={index} derived={derived} autoRegister={autoRegister} />
            : <p className="muted lib-detail-empty">左の一覧から Character を選択してください。</p>}
        </aside>
      </div>
    </>
  );
}

export function CharacterLibraryScreen() {
  return <Suspense fallback={<p className="muted">Loading…</p>}><CharacterLibraryInner /></Suspense>;
}
