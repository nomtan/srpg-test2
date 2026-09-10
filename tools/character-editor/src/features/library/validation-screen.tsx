"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useLibraryIndex, refreshLibrary } from "./use-library-index";
import { deriveLibrary } from "./derive";
import { validateAssetRecord, validateCharacterRecord, countStatuses } from "@/domain/library-validation";
import { runBulkValidation } from "./mutations";
import { ValidationBadge } from "./components/badges";

export function ValidationScreen() {
  const { index, error } = useLibraryIndex();
  const derived = useMemo(() => deriveLibrary(index), [index]);
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  const assetFindings = useMemo(
    () => index.assets.map((a) => ({ id: a.metadata.id, issues: validateAssetRecord(a) })).filter((f) => f.issues.length),
    [index.assets],
  );
  const charFindings = useMemo(
    () => index.characters.map((c) => ({ id: c.recipe.id, issues: validateCharacterRecord(c, { assetsById: derived.assetsById }) })).filter((f) => f.issues.length),
    [index.characters, derived.assetsById],
  );

  const assetCounts = countStatuses(index.assets);
  const charCounts = countStatuses(index.characters);

  async function run(which: "assets" | "characters" | "both") {
    setBusy(which); setMsg(null);
    try {
      const r = await runBulkValidation(index, which);
      await refreshLibrary();
      setMsg(`Assets — Valid ${r.assets.valid} / Warning ${r.assets.warning} / Error ${r.assets.error} · Characters — Valid ${r.characters.valid} / Warning ${r.characters.warning} / Error ${r.characters.error}`);
    } catch (e) {
      setMsg(`失敗: ${e instanceof Error ? e.message : String(e)}`);
    } finally { setBusy(null); }
  }

  return (
    <>
      <div className="page-heading">
        <div>
          <p className="eyebrow">VALIDATION</p>
          <h1>Library Validation</h1>
          <p>Library 全体を一括 Validation し、Error / Warning を一覧表示します。項目をクリックすると該当 Detail へ移動します。</p>
        </div>
        <span className="badge">PHASE 7</span>
      </div>

      {error && <p className="err">Library API エラー: {error}</p>}

      <div className="val-actions-bar">
        <button disabled={!!busy} onClick={() => run("assets")}>Validate All Assets</button>
        <button disabled={!!busy} onClick={() => run("characters")}>Validate All Characters</button>
        <button disabled={!!busy} onClick={() => run("both")}>Validate Everything</button>
      </div>
      {msg && <p className="save-msg">{msg}</p>}

      <div className="val-summary">
        <div className="panel">
          <div className="panel-heading"><h2>Assets</h2></div>
          <p className="reg-sync">Valid: {assetCounts.valid} · Warning: {assetCounts.warning} · Error: {assetCounts.error} · Not Validated: {assetCounts.unknown}</p>
        </div>
        <div className="panel">
          <div className="panel-heading"><h2>Characters</h2></div>
          <p className="reg-sync">Valid: {charCounts.valid} · Warning: {charCounts.warning} · Error: {charCounts.error} · Not Validated: {charCounts.unknown}</p>
        </div>
      </div>

      <section className="panel">
        <div className="panel-heading"><h2>Asset Findings ({assetFindings.length})</h2></div>
        <ul className="finding-list">
          {assetFindings.map((f) => (
            <li key={f.id}>
              <Link href={`/assets?id=${f.id}`} className="finding-id">{f.id}</Link>
              <ValidationBadge status={derived.assetsById.get(f.id)?.validation.status ?? "unknown"} />
              <ul className="val-list">
                {f.issues.map((i, k) => <li key={k} className={`val ${i.level}`}><span className="val-tag">{i.level.toUpperCase()}</span><span>{i.message}</span></li>)}
              </ul>
            </li>
          ))}
          {assetFindings.length === 0 && <li className="muted">問題なし。</li>}
        </ul>
      </section>

      <section className="panel">
        <div className="panel-heading"><h2>Character Findings ({charFindings.length})</h2></div>
        <ul className="finding-list">
          {charFindings.map((f) => (
            <li key={f.id}>
              <Link href={`/characters?id=${f.id}`} className="finding-id">{f.id}</Link>
              <ul className="val-list">
                {f.issues.map((i, k) => <li key={k} className={`val ${i.level}`}><span className="val-tag">{i.level.toUpperCase()}</span><span>{i.message}</span></li>)}
              </ul>
            </li>
          ))}
          {charFindings.length === 0 && <li className="muted">問題なし。</li>}
        </ul>
      </section>
    </>
  );
}
